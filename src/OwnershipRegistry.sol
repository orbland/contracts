// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {Earnable} from "./Earnable.sol";
import {OrbSystem} from "./OrbSystem.sol";
import {InvocationRegistry} from "./InvocationRegistry.sol";
import {IAllocationMethod} from "./allocation/IAllocationMethod.sol";

struct PurchaseOrder {
    uint256 index; // starts from 0, so shouldn't be used to check if the order exists
    address purchaser;
    uint256 price; // price if finalized
    uint256 timestamp; // when the order was placed
}

/// @title   Orb Ownership Registry
/// @author  Jonas Lekevicius
/// @author  Eric Wall
/// @custom:security-contact security@orb.land
contract OwnershipRegistry is Earnable, OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event Creation(uint256 indexed orbId, address indexed creator);

    // Funding Events
    event Deposit(uint256 indexed orbId, address indexed depositor, uint256 amount);
    event Withdrawal(uint256 indexed orbId, address indexed recipient, uint256 amount);
    event Settlement(uint256 indexed orbId, address indexed keeper, uint256 amount);

    // Purchasing Events
    event PriceUpdate(uint256 indexed orbId, address indexed keeper, uint256 newPrice);
    event Purchase(uint256 indexed orbId, address indexed seller, address indexed buyer, uint256 price);
    event PurchaseFinalized(uint256 indexed orbId, address indexed seller, address indexed buyer, uint256 price);
    event PurchaseCancelled(uint256 indexed orbId);

    // Orb Ownership Events
    event Foreclosure(uint256 indexed orbId, address indexed formerKeeper);
    event Relinquishment(uint256 indexed orbId, address indexed formerKeeper);
    event Recall(uint256 indexed orbId, address indexed formerKeeper);
    event OrbTransfer(uint256 indexed orbId, address indexed formerKeeper, address indexed newKeeper);

    // Allocation
    event AllocationStart(uint256 indexed orbId, address indexed allocationContract, address indexed beneficiary);
    event AllocationFinalization(
        uint256 indexed orbId, address indexed beneficiary, address indexed recipient, uint256 proceeds
    );

    // Orb Parameter Events
    event FeesUpdate(
        uint256 indexed orbId, uint256 newKeeperTax, uint256 newPurchaseRoyalty, uint256 newReallocationRoyalty
    );
    event MinimumPriceUpdate(uint256 indexed orbId, uint256 indexed newMinimumPrice);
    event AllocationContractUpdate(
        uint256 indexed orbId, address indexed newAllocationContract, address indexed newReallocationContract
    );
    event CreatorUpdate(uint256 indexed orbId, address indexed newCreator);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Authorization Errors
    error NotCreator();
    error NotKeeper();
    error ContractHoldsOrb();
    error ContractDoesNotHoldOrb();
    error KeeperDoesNotHoldOrb();
    error CreatorDoesNotControlOrb();
    error AlreadyKeeper();
    error AddressUnauthorized(address unauthorizedAddress);
    error OrbNotReclaimable();
    error NotAllocationContract();
    error Unauthorized();
    error OrbDoesNotExist();
    error AddressInvalid(address invalidAddress);
    error NotPermitted();
    error OrbInvokable();
    error InsufficientKeeperFunds();
    error AlreadyLastPurchaser();
    error NoPurchaseOrder();
    error PurchaseOrderExpired();
    error OrbNotInvokable();

    // Allocation Errors
    error AllocationActive();
    error UnrespondedInvocationExists();

    // Funding Errors
    error KeeperSolvent();
    error KeeperInsolvent();
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);

    // Purchasing Errors
    error CurrentValueIncorrect(uint256 valueProvided, uint256 currentValue);
    error PurchasingNotPermitted();
    error InvalidPrice(uint256 price);
    error PriceTooLow(uint256 priceProvided, uint256 minimumPrice);
    error KeeperTaxTooHigh(uint256 keeperTax, uint256 maximumKeeperTax);

    // Orb Parameter Errors
    error RoyaltyNumeratorExceedsDenominator(uint256 royalty, uint256 feeDenominator);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS

    /// Orb version. Value: 1.
    uint256 private constant _VERSION = 1;
    /// Harberger tax period: for how long the tax rate applies. Value: 1 year.
    uint256 internal constant _KEEPER_TAX_PERIOD = 365 days;
    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;
    /// Next purchase order price multiplier. Value: 1.2x of the previous price.
    uint256 internal constant _NEXT_PURCHASE_PRICE_MULTIPLIER = 120_00;

    // STATE

    OrbSystem public os;

    /// Orb count: how many Orbs have been created.
    uint256 public orbCount;

    mapping(uint256 orbId => address) public creator;
    /// Address of the Orb keeper. The keeper is the address that owns the Orb and has the right to invoke the Orb and
    /// receive a response. The keeper is also the address that pays the Harberger tax.
    mapping(uint256 orbId => address) public keeper;
    /// Contract used for Orb Keeper Allocation process
    mapping(uint256 orbId => address) public allocationContract;
    /// Contract used for Orb Keeper Reallocation process
    mapping(uint256 orbId => address) public reallocationContract;

    // Funds Variables

    /// Funds tracker, per Orb and per address. Modified by deposits, withdrawals and settlements.
    /// The value is without settlement.
    /// It means effective user funds (withdrawable) would be different for keeper (subtracting
    /// `_owedSinceLastSettlement()`) and beneficiary (adding `_owedSinceLastSettlement()`). If Orb is held by the
    /// creator, funds are not subtracted, as Harberger tax does not apply to the creator.
    mapping(uint256 orbId => mapping(address => uint256)) public fundsOf;

    // Fees State Variables

    /// Harberger tax for holding. Initial value is 120.00%.
    mapping(uint256 orbId => uint256) public keeperTax;
    /// Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 10.00%.
    mapping(uint256 orbId => uint256) public purchaseRoyalty;
    /// Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 30.00%.
    mapping(uint256 orbId => uint256) public reallocationRoyalty;
    /// Minimum price for the Orb. Used to prevent the Orb from being listed for sale at too low of a price.
    mapping(uint256 orbId => uint256) public minimumPrice;
    /// Price of the Orb. Also used during auction to store future purchase price. Has no meaning if the Orb is held by
    /// the contract and the auction is not running.
    mapping(uint256 orbId => uint256) public price;
    /// Last time Orb keeper's funds were settled. Used to calculate amount owed since last settlement. Has no meaning
    /// if the Orb is held by the contract.
    mapping(uint256 orbId => uint256) public lastSettlementTime;

    /// Allocation Beneficiary: address that receives most of the auction proceeds. Zero address if run by creator.
    mapping(uint256 orbId => address) public allocationBeneficiary;

    mapping(uint256 orbId => PurchaseOrder) public purchaseOrder;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  MODIFIERS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // AUTHORIZATION MODIFIERS

    /// @dev  Ensures that the caller created the Orb.
    modifier onlyCreator(uint256 orbId) virtual {
        if (_msgSender() != creator[orbId]) {
            revert NotCreator();
        }
        _;
    }

    /// @dev  Ensures that the caller owns the Orb. Should only be used in conjuction with `onlyKeeperHeld` or on
    ///       external functions, otherwise does not make sense.
    modifier onlyKeeper(uint256 orbId) virtual {
        if (_msgSender() != keeper[orbId]) {
            revert NotKeeper();
        }
        if (_keeperSolvent(orbId) == false) {
            revert KeeperInsolvent();
        }
        _;
    }

    // ORB STATE MODIFIERS

    /// @dev  Ensures that the Orb belongs to someone (possibly creator), not the contract itself.
    modifier onlyKeeperHeld(uint256 orbId) virtual {
        if (address(0) == keeper[orbId]) {
            revert OrbDoesNotExist();
        }
        if (address(this) == keeper[orbId]) {
            revert ContractHoldsOrb();
        }
        _;
    }

    /// @dev  Ensures that the Orb belongs to the contract itself.
    modifier onlyContractHeld(uint256 orbId) virtual {
        if (address(this) != keeper[orbId]) {
            revert ContractDoesNotHoldOrb();
        }
        _;
    }

    modifier onlyCreatorControlled(uint256 orbId) virtual {
        if (os.isCreatorControlled(orbId) == false) {
            revert CreatorDoesNotControlOrb();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initalize(address os_) public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();

        os = OrbSystem(os_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ORB CREATION AND SETTINGS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev    When deployed, contract mints the only token that will ever exist, to itself.
    ///         This token represents the Orb and is called the Orb elsewhere in the contract.
    ///         `Ownable` sets the deployer to be the `owner()`, and also the creator in the Orb context.
    ///         V2 changes initial values and sets `auctionKeeperMinimumDuration`.
    function createAuthorized(address allocationContract_, bytes memory authorizationSignature_)
        public
        virtual
        initializer
    {
        uint256 orbId = orbCount;

        // check that authorizationSignature is signed from signing authority
        // even a properly signed message can fail if an Orb is created between message signing and contract call
        address signingAddress = ECDSA.recover(
            keccak256(abi.encodePacked(_msgSender(), allocationContract_, orbId)), authorizationSignature_
        );
        if (signingAddress != os.platformSignerAddress()) {
            revert Unauthorized();
        }

        creator[orbId] = _msgSender();
        keeper[orbId] = address(this);

        keeperTax[orbId] = 120_00;
        purchaseRoyalty[orbId] = 10_00;
        reallocationRoyalty[orbId] = 30_00;

        allocationContract[orbId] = allocationContract_;
        reallocationContract[orbId] = allocationContract_;
        IAllocationMethod(allocationContract_).initializeOrb(orbId);
        os.invocations().initializeOrb(orbId);
        // Pledge Locker does not need to be initialized.

        orbCount++;

        emit Creation(orbId, _msgSender());
    }

    /// @notice  Allows the Orb creator to set the new keeper tax and royalty. This function can only be called by the
    ///          Orb creator when the Orb is in their control.
    /// @dev     Emits `FeesUpdate`.
    ///          V2 changes to allow setting Keeper auction royalty separately from purchase royalty, with releated
    ///          parameter and event changes.
    /// @param   keeperTax_        New keeper tax numerator, in relation to `feeDenominator()`.
    /// @param   purchaseRoyalty_  New royalty numerator for royalties from `purchase()`, in relation to
    ///                                       `feeDenominator()`. Cannot be larger than `feeDenominator()`.
    /// @param   reallocationRoyalty_   New royalty numerator for royalties from keeper auctions, in relation to
    ///                                       `feeDenominator()`. Cannot be larger than `feeDenominator()`.
    function setFees(uint256 orbId, uint256 keeperTax_, uint256 purchaseRoyalty_, uint256 reallocationRoyalty_)
        external
        virtual
        onlyCreator(orbId)
        onlyCreatorControlled(orbId)
    {
        if (keeper[orbId] != address(this)) {
            _settle(orbId);
        }
        if (purchaseRoyalty_ > os.feeDenominator()) {
            revert RoyaltyNumeratorExceedsDenominator(purchaseRoyalty_, os.feeDenominator());
        }
        if (reallocationRoyalty_ > os.feeDenominator()) {
            revert RoyaltyNumeratorExceedsDenominator(reallocationRoyalty_, os.feeDenominator());
        }

        uint256 maximumKeeperTax = os.invocations().maximumKeeperTax(orbId);
        if (keeperTax_ > maximumKeeperTax) {
            revert KeeperTaxTooHigh(keeperTax_, maximumKeeperTax);
        }

        keeperTax[orbId] = keeperTax_;
        purchaseRoyalty[orbId] = purchaseRoyalty_;
        reallocationRoyalty[orbId] = reallocationRoyalty_;

        emit FeesUpdate(orbId, keeperTax_, purchaseRoyalty_, reallocationRoyalty_);
    }

    /// @notice  Allows the Orb creator to set minimum price Orb can be sold at. This function can only be called by the
    ///          Orb creator when the Orb is in their control. Setting the minimum price does not adjust the current
    ///          price, even if it's invalid: rule will apply on future Orb price settings.
    /// @dev     Emits `MinimumPriceUpdate`.
    /// @param   newMinimumPrice  New minimum price
    function setMinimumPrice(uint256 orbId, uint256 newMinimumPrice)
        external
        virtual
        onlyCreator(orbId)
        onlyCreatorControlled(orbId)
    {
        if (newMinimumPrice > _MAXIMUM_PRICE) {
            revert InvalidPrice(newMinimumPrice);
        }

        minimumPrice[orbId] = newMinimumPrice;

        emit MinimumPriceUpdate(orbId, newMinimumPrice);
    }

    function setAllocationContracts(uint256 orbId, address allocationContract_, address reallocationContract_)
        external
        virtual
        onlyCreator(orbId)
        onlyCreatorControlled(orbId)
    {
        if (
            IAllocationMethod(allocationContract[orbId]).isActive(orbId)
                || (
                    reallocationContract[orbId] != address(0)
                        && IAllocationMethod(reallocationContract[orbId]).isActive(orbId)
                )
        ) {
            revert AllocationActive();
        }
        if (os.allocationContractAuthorized(allocationContract_) == false) {
            revert AddressUnauthorized(allocationContract_);
        }
        if (reallocationContract_ != address(0) && os.allocationContractAuthorized(reallocationContract_) == false) {
            revert AddressUnauthorized(reallocationContract_);
        }

        allocationContract[orbId] = allocationContract_;
        reallocationContract[orbId] = reallocationContract_;
        emit AllocationContractUpdate(orbId, allocationContract_, reallocationContract_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: DISCOVERY
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.
    /// @dev     Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
    ///          after auction is finalized. Emits `AuctionStart`.
    ///          V2 adds `onlyHonored` modifier to require active Oath to start auction.
    function startAllocation(uint256 orbId)
        external
        virtual
        onlyCreator(orbId)
        onlyCreatorControlled(orbId)
        onlyContractHeld(orbId)
    {
        address _creator = creator[orbId];
        IAllocationMethod allocation = IAllocationMethod(allocationContract[orbId]);

        allocationBeneficiary[orbId] = _creator;
        allocation.start(orbId);

        emit AllocationStart(orbId, allocationContract[orbId], _creator);
    }

    /// @notice  Finalizes the auction, transferring the winning bid to the beneficiary, and the Orb to the winner.
    ///          If the auction was started by previous Keeper with `relinquish(true)`, then most of the auction
    ///          proceeds (minus the royalty) will be sent to the previous Keeper. Sets `lastInvocationTime` so that
    ///          the Orb could be invoked immediately. The price has been set when bidding, now becomes relevant. If no
    ///          bids were made, resets the state to allow the auction to be started again later.
    /// @dev     Critical state transition function. Called after `auctionEndTime`, but only if it's not 0. Can be
    ///          called by anyone, although probably will be called by the creator or the winner. Emits `PriceUpdate`
    ///          and `AuctionFinalization`.
    ///          V2 fixes a bug with Keeper auctions changing lastInvocationTime, and uses `auctionRoyalty`
    ///          instead of `purchaseRoyalty` for auction royalty (only relevant for Keeper auctions).
    function finalizeAllocation(uint256 orbId, address recipient_, uint256 recipientFunds_, uint256 initialPrice_)
        external
        payable
        virtual
    {
        if (_msgSender() != allocationContract[orbId]) {
            revert NotAllocationContract();
        }

        if (recipient_ != address(0)) {
            if (msg.value != recipientFunds_) {
                revert InsufficientFunds(msg.value, recipientFunds_);
            }
            fundsOf[orbId][recipient_] += recipientFunds_;

            lastSettlementTime[orbId] = block.timestamp;
            if (allocationBeneficiary[orbId] == creator[orbId]) {
                os.invocations().initializeOrbInvocationPeriod(orbId);
            }

            uint256 effectiveInitialPrice = initialPrice_ > minimumPrice[orbId] ? initialPrice_ : minimumPrice[orbId];
            _setPrice(orbId, effectiveInitialPrice);

            keeper[orbId] = recipient_;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: FUNDS AND HOLDING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Allows depositing funds on the contract. Not allowed for insolvent keepers.
    /// @dev     Deposits are not allowed for insolvent keepers to prevent cheating via front-running. If the user
    ///          becomes insolvent, the Orb will always be returned to the contract as the next step. Emits `Deposit`.
    function deposit(uint256 orbId) external payable virtual {
        if (_msgSender() == keeper[orbId] && !_keeperSolvent(orbId)) {
            revert KeeperInsolvent();
        }

        fundsOf[orbId][_msgSender()] += msg.value;
        emit Deposit(orbId, _msgSender(), msg.value);
    }

    /// @notice  Function to withdraw given amount from the contract. For current Orb keepers, reduces the time until
    ///          foreclosure.
    /// @dev     Not allowed for the leading auction bidder.
    /// @param   amount_  The amount to withdraw.
    function withdraw(uint256 orbId, uint256 amount_) external virtual {
        if (_msgSender() == keeper[orbId]) {
            if (purchaseOrder[orbId].purchaser != address(0)) {
                revert NotPermitted();
            }
            _settle(orbId);
        }
        _withdraw(orbId, _msgSender(), amount_);
    }

    /// @notice  Function to withdraw all funds on the contract. Not recommended for current Orb keepers if the price
    ///          is not zero, as they will become immediately foreclosable. To give up the Orb, call `relinquish()`.
    /// @dev     Not allowed for the leading auction bidder.
    function withdrawAll(uint256 orbId) external virtual {
        if (_msgSender() == keeper[orbId]) {
            if (purchaseOrder[orbId].purchaser != address(0)) {
                revert NotPermitted();
            }
            _settle(orbId);
        }
        _withdraw(orbId, _msgSender(), fundsOf[orbId][_msgSender()]);
    }

    /// @dev    Executes the withdrawal for a given amount, does the actual value transfer from the contract to user's
    ///         wallet. The only function in the contract that sends value and has re-entrancy risk. Does not check if
    ///         the address is payable, as the Address library reverts if it is not. Emits `Withdrawal`.
    /// @param  recipient_  The address to send the value to.
    /// @param  amount_     The value in wei to withdraw from the contract.
    function _withdraw(uint256 orbId, address recipient_, uint256 amount_) internal virtual {
        if (fundsOf[orbId][recipient_] < amount_) {
            revert InsufficientFunds(fundsOf[orbId][recipient_], amount_);
        }

        fundsOf[orbId][recipient_] -= amount_;

        emit Withdrawal(orbId, recipient_, amount_);

        Address.sendValue(payable(recipient_), amount_);
    }

    function keeperTaxPeriod() external pure virtual returns (uint256) {
        return _KEEPER_TAX_PERIOD;
    }

    /// @notice  Settlements transfer funds from Orb keeper to the beneficiary. Orb accounting minimizes required
    ///          transactions: Orb keeper's foreclosure time is only dependent on the price and available funds. Fund
    ///          transfers are not necessary unless these variables (price, keeper funds) are being changed. Settlement
    ///          transfers funds owed since the last settlement, and a new period of virtual accounting begins.
    /// @dev     See also `_settle()`.
    function settle(uint256 orbId) external virtual onlyKeeperHeld(orbId) {
        _settle(orbId);
    }

    function keeperSolvent(uint256 orbId) external view virtual returns (bool isKeeperSolvent) {
        return _keeperSolvent(orbId);
    }

    /// @dev     Returns if the current Orb keeper has enough funds to cover Harberger tax until now. Always true if
    ///          creator holds the Orb.
    /// @return  isKeeperSolvent  If the current keeper is solvent.
    function _keeperSolvent(uint256 orbId) internal view virtual returns (bool) {
        if (creator[orbId] == keeper[orbId]) {
            return true;
        }
        return fundsOf[orbId][keeper[orbId]] >= _owedSinceLastSettlement(orbId);
    }

    function _foreclosureTimestamp(uint256 orbId) internal view virtual returns (uint256) {
        if (
            creator[orbId] == keeper[orbId] || keeper[orbId] == address(this) || price[orbId] == 0
                || keeperTax[orbId] == 0
        ) {
            return type(uint256).max;
        }
        uint256 owedFunds = _owedSinceLastSettlement(orbId);
        uint256 availableFunds = fundsOf[orbId][keeper[orbId]];
        uint256 effectiveFunds = availableFunds <= owedFunds ? 0 : availableFunds - owedFunds;
        return effectiveFunds * _KEEPER_TAX_PERIOD * os.feeDenominator() / (price[orbId] * keeperTax[orbId]);
    }

    /// @dev     Calculates how much money Orb keeper owes Orb beneficiary. This amount would be transferred between
    ///          accounts during settlement. **Owed amount can be higher than keeper's funds!** It's important to check
    ///          if keeper has enough funds before transferring.
    /// @return  owedValue  Wei Orb keeper owes Orb beneficiary since the last settlement time.
    function _owedSinceLastSettlement(uint256 orbId) internal view virtual returns (uint256 owedValue) {
        uint256 taxedUntil = block.timestamp;
        InvocationRegistry invocations = os.invocations();

        // Settles during response, so we only need to account for pause if an invocation has no response
        if (invocations.hasUnrespondedInvocation(orbId)) {
            uint256 invocationTimestamp = invocations.lastInvocationTime(orbId);
            uint256 invocationPeriod = invocations.invocationPeriod(orbId);
            if (block.timestamp > invocationTimestamp + invocationPeriod) {
                taxedUntil = invocationTimestamp + invocationPeriod;
            }
        }
        uint256 secondsSinceLastSettlement =
            taxedUntil > lastSettlementTime[orbId] ? taxedUntil - lastSettlementTime[orbId] : 0;
        return
            (price[orbId] * keeperTax[orbId] * secondsSinceLastSettlement) / (_KEEPER_TAX_PERIOD * os.feeDenominator());
    }

    /// @dev  Keeper might owe more than they have funds available: it means that the keeper is foreclosable.
    ///       Settlement would transfer all keeper funds to the beneficiary, but not more. Does not transfer funds if
    ///       the creator holds the Orb, but always updates `lastSettlementTime`. Should never be called if Orb is
    ///       owned by the contract. Emits `Settlement`.
    function _settle(uint256 orbId) internal virtual {
        address _keeper = keeper[orbId];
        address _creator = creator[orbId];

        if (_creator == _keeper) {
            lastSettlementTime[orbId] = block.timestamp;
            return;
        }

        uint256 availableFunds = fundsOf[orbId][_keeper];
        uint256 owedFunds = _owedSinceLastSettlement(orbId);
        uint256 transferableToEarnings = availableFunds <= owedFunds ? availableFunds : owedFunds;

        fundsOf[orbId][_keeper] -= transferableToEarnings;
        _addEarnings(_creator, transferableToEarnings);

        lastSettlementTime[orbId] = block.timestamp;

        emit Settlement(orbId, _keeper, transferableToEarnings);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: PURCHASING AND LISTING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Sets the new purchase price for the Orb. Harberger tax means the asset is always for sale. The price
    ///          can be set to zero, making foreclosure time to be never. Can only be called by a solvent keeper.
    ///          Settles before adjusting the price, as the new price will change foreclosure time.
    /// @dev     Emits `Settlement` and `PriceUpdate`. See also `_setPrice()`.
    /// @param   newPrice_  New price for the Orb.
    function setPrice(uint256 orbId, uint256 newPrice_) external virtual onlyKeeper(orbId) {
        if (purchaseOrder[orbId].purchaser != address(0)) {
            revert NotPermitted();
        }
        _settle(orbId);
        _setPrice(orbId, newPrice_);
    }

    /// @notice  Lists the Orb for sale at the given price to buy directly from the Orb creator. This is an alternative
    ///          to the auction mechanism, and can be used to simply have the Orb for sale at a fixed price, waiting
    ///          for the buyer. Listing is only allowed if the auction has not been started and the Orb is held by the
    ///          contract. When the Orb is purchased from the creator, all proceeds go to the beneficiary and the Orb
    ///          comes fully charged, with no invocationPeriod.
    /// @dev     Emits `Transfer` and `PriceUpdate`.
    /// @param   listingPrice_  The price to buy the Orb from the creator.
    function listForSale(uint256 orbId, uint256 listingPrice_)
        external
        virtual
        onlyCreator(orbId)
        onlyCreatorControlled(orbId)
        onlyContractHeld(orbId)
    {
        keeper[orbId] = _msgSender();
        _setPrice(orbId, listingPrice_);
    }

    /// @notice  Purchasing is the mechanism to take over the Orb. With Harberger tax, the Orb can always be purchased
    ///          from its keeper. Purchasing is only allowed while the keeper is solvent. If not, the Orb has to be
    ///          foreclosed and re-auctioned. This function does not require the purchaser to have more funds than
    ///          required, but purchasing without any reserve would leave the new owner immediately foreclosable.
    ///          Beneficiary receives either just the royalty, or full price if the Orb is purchased from the creator.
    /// @dev     Requires to provide key Orb parameters (current price, Harberger tax rate, royalty, invocationPeriod
    ///          and cleartext maximum length) to prevent front-running: without these parameters Orb creator could
    ///          front-run purcaser and change Orb parameters before the purchase; and without current price anyone
    ///          could purchase the Orb ahead of the purchaser, set the price higher, and profit from the purchase.
    ///          Does not modify `lastInvocationTime` unless buying from the creator.
    ///          Does not allow settlement in the same block before `purchase()` to prevent transfers that avoid
    ///          royalty payments. Does not allow purchasing from yourself. Emits `PriceUpdate` and `Purchase`.
    ///          V2 changes to require providing Keeper auction royalty to prevent front-running.
    /// @param  orbId      ID of the Orb to purchase.
    /// @param  newPrice_  New price to use after the purchase.
    function purchase(uint256 orbId, uint256 newPrice_) external payable virtual onlyKeeperHeld(orbId) {
        if (_keeperSolvent(orbId) == false) {
            revert KeeperInsolvent();
        }
        if (lastSettlementTime[orbId] >= block.timestamp) {
            revert PurchasingNotPermitted();
        }

        _settle(orbId);

        address _keeper = keeper[orbId];
        address _creator = creator[orbId];
        // how much you have to pay now:
        uint256 _currentPrice = _nextPurchaseOrderPrice(orbId);
        // might be 0 if there isn't a purchase order:
        uint256 _lastOrderPrice = _lastPurchaseOrderPrice(orbId);

        if (_msgSender() == _keeper) {
            revert AlreadyKeeper();
        }

        fundsOf[orbId][_msgSender()] += msg.value;
        uint256 totalFunds = fundsOf[orbId][_msgSender()];

        if (totalFunds < _currentPrice) {
            revert InsufficientFunds(totalFunds, _currentPrice);
        }

        fundsOf[orbId][_msgSender()] -= _currentPrice;
        address _lastPurchaser = purchaseOrder[orbId].purchaser;
        uint256 _keeperEarnings = _currentPrice;
        if (_lastPurchaser != address(0)) {
            // last order price will not be 0
            // maker of last purchase order earns the difference as usual
            _addEarnings(_lastPurchaser, _currentPrice - _lastOrderPrice);
            // they also get refund for the purchase order funds that were standing
            fundsOf[orbId][_lastPurchaser] += _lastOrderPrice;
            _keeperEarnings = _lastOrderPrice;
            _resetPurchaseOrder(orbId);
        }
        if (_creator == _keeper) {
            os.invocations().initializeOrbInvocationPeriod(orbId);
            // if there was a purchase order, it should get the _purchaseOrderFunds
            // if not, it should get keeper price
            _addEarnings(_creator, _keeperEarnings);
        } else {
            uint256 royaltyShare = (_keeperEarnings * purchaseRoyalty[orbId]) / os.feeDenominator();
            _addEarnings(_creator, royaltyShare);
            _addEarnings(_keeper, _keeperEarnings - royaltyShare);
        }

        _setPrice(orbId, newPrice_);

        emit Purchase(orbId, _keeper, _msgSender(), _currentPrice);

        keeper[orbId] = _msgSender();
    }

    function _nextPurchaseOrderPrice(uint256 orbId) internal view virtual returns (uint256) {
        if (purchaseOrder[orbId].purchaser != address(0)) {
            return price[orbId] * (_NEXT_PURCHASE_PRICE_MULTIPLIER ** (purchaseOrder[orbId].index + 1))
                / os.feeDenominator();
        }
        return price[orbId];
    }

    function _lastPurchaseOrderPrice(uint256 orbId) internal view virtual returns (uint256) {
        if (purchaseOrder[orbId].purchaser != address(0)) {
            // uses index before updating during purchase order
            return price[orbId] * (_NEXT_PURCHASE_PRICE_MULTIPLIER ** purchaseOrder[orbId].index) / os.feeDenominator();
        }
        return 0;
    }

    function nextPurchasePrice(uint256 orbId) external view virtual returns (uint256) {
        return _nextPurchaseOrderPrice(orbId);
    }

    function placePurchaseOrder(uint256 orbId, uint256 priceIfFinalized_) external payable virtual {
        // - Only allowed if Orb is charging -- otherwise please use `purchase()`
        if (os.invocations().isInvokable(orbId)) {
            revert OrbInvokable();
        }

        // Only allowed if Keeper has enough funds to go until Orb is invokable again
        uint256 lastInvocationTime = os.invocations().lastInvocationTime(orbId);
        uint256 invocationPeriod = os.invocations().invocationPeriod(orbId);
        if (_foreclosureTimestamp(orbId) < lastInvocationTime + invocationPeriod) {
            revert InsufficientKeeperFunds();
        }

        uint256 _purchasePrice = _nextPurchaseOrderPrice(orbId);
        if (msg.value < _purchasePrice) {
            revert InsufficientFunds(msg.value, _purchasePrice);
        }

        address _lastPurchaser = purchaseOrder[orbId].purchaser;
        if (_msgSender() == _lastPurchaser) {
            revert AlreadyLastPurchaser();
        }

        fundsOf[orbId][_msgSender()] += msg.value - _purchasePrice;
        uint256 _purchaseIndex = purchaseOrder[orbId].index;
        // 0 if there isn't a purchase order
        // potentially 0 if there is one
        if (_lastPurchaser != address(0)) {
            _purchaseIndex++;
            // price paid by last purchaser, will not be 0 here
            uint256 _lastPrice = _lastPurchaseOrderPrice(orbId);
            uint256 _priceDifference = _purchasePrice - _lastPrice;
            _addEarnings(_lastPurchaser, _priceDifference);
        }
        purchaseOrder[orbId] = PurchaseOrder(_purchaseIndex, _msgSender(), priceIfFinalized_, block.timestamp);
    }

    /// @dev    Does not check if the new price differs from the previous price: no risk. Limits the price to
    ///         MAXIMUM_PRICE to prevent potential overflows in math. Emits `PriceUpdate`.
    /// @param  price_  New price for the Orb.
    function _setPrice(uint256 orbId, uint256 price_) internal virtual {
        if (price_ > _MAXIMUM_PRICE) {
            revert InvalidPrice(price_);
        }
        if (price_ < minimumPrice[orbId]) {
            revert PriceTooLow(price_, minimumPrice[orbId]);
        }

        price[orbId] = price_;

        // TODO unique event emits for all methods
        emit PriceUpdate(orbId, keeper[orbId], price_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: RELINQUISHMENT AND FORECLOSURE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function finalizePurchase(uint256 orbId) public virtual {
        if (purchaseOrder[orbId].purchaser == address(0)) {
            revert NoPurchaseOrder();
        }
        if (block.timestamp > purchaseOrder[orbId].timestamp + os.invocations().invocationPeriod(orbId) * 2) {
            revert PurchaseOrderExpired();
        }
        if (!os.invocations().isInvokable(orbId)) {
            revert OrbNotInvokable();
        }

        _settle(orbId);

        address _keeper = keeper[orbId];
        address _creator = creator[orbId];

        // might be 0 if there isn't a purchase order:
        uint256 _purchaseFunds = _purchaseOrderFunds(orbId);
        address _lastPurchaser = purchaseOrder[orbId].purchaser;

        if (_creator == _keeper) {
            os.invocations().initializeOrbInvocationPeriod(orbId);
            _addEarnings(_creator, _purchaseFunds);
        } else {
            uint256 royaltyShare = (_purchaseFunds * purchaseRoyalty[orbId]) / os.feeDenominator();
            _addEarnings(_creator, royaltyShare);
            _addEarnings(_keeper, _purchaseFunds - royaltyShare);
        }

        _setPrice(orbId, purchaseOrder[orbId].price);
        _resetPurchaseOrder(orbId);
        keeper[orbId] = _lastPurchaser;

        emit PurchaseFinalized(orbId, _keeper, _lastPurchaser, _purchaseFunds);
    }

    function _purchaseOrderFunds(uint256 orbId) internal view virtual returns (uint256) {
        if (purchaseOrder[orbId].purchaser == address(0)) {
            return 0;
        }
        // before first: funds available are 0
        // after first: keeper price (index == 0)
        // after second: also keeper price (index == 1)
        // after third: 2nd purchase price (index == 2)
        uint256 purchaseFundsIndex = purchaseOrder[orbId].index > 1 ? purchaseOrder[orbId].index - 1 : 0;

        return price[orbId] * (_NEXT_PURCHASE_PRICE_MULTIPLIER ** purchaseFundsIndex) / os.feeDenominator();
    }

    function cancelPurchase(uint256 orbId) public virtual {
        bool _canCancel = false;
        if (purchaseOrder[orbId].purchaser == address(0)) {
            revert NoPurchaseOrder();
        }
        if (_msgSender() == os.pledgeLockerAddress()) {
            _canCancel = true;
        }
        if (
            block.timestamp > purchaseOrder[orbId].timestamp + os.invocations().invocationPeriod(orbId) * 2
                && !os.invocations().isInvokable(orbId) && !os.pledges().hasClaimablePledge(orbId)
        ) {
            _canCancel = true;
        }
        if (_canCancel == false) {
            revert NotPermitted();
        }

        // - Purchase funds are returned to purchaserAddress as funds (fee not charged)
        fundsOf[orbId][purchaseOrder[orbId].purchaser] += _purchaseOrderFunds(orbId);
        _resetPurchaseOrder(orbId);

        emit PurchaseCancelled(orbId);
    }

    function _resetPurchaseOrder(uint256 orbId) internal virtual {
        purchaseOrder[orbId] = PurchaseOrder(0, address(0), 0, 0);
    }

    /// @notice  Allows the Orb creator to recall the Orb from the Keeper, if the Oath is no longer honored. This is an
    ///          alternative to just extending the Oath or swearing it while held by Keeper. It benefits the Orb creator
    ///          as they can set a new Oath and run a new auction. This acts as an alternative to just abandoning the
    ///          Orb after Oath expires.
    /// @dev     Emits `Recall`. Does not transfer remaining funds to the Keeper to allow recalling even if the Keeper
    ///          is a smart contract rejecting ether transfers.
    function recall(uint256 orbId) external virtual onlyCreator(orbId) onlyCreatorControlled(orbId) {
        address _keeper = keeper[orbId];
        if (address(this) == _keeper || creator[orbId] == _keeper) {
            revert KeeperDoesNotHoldOrb();
        }

        _settle(orbId);

        price[orbId] = 0;
        keeper[orbId] = address(this);

        emit Recall(orbId, _keeper);
    }

    /// @notice  Relinquishment is a voluntary giving up of the Orb. It's a combination of withdrawing all funds not
    ///          owed to the beneficiary since last settlement and transferring the Orb to the contract. Keepers giving
    ///          up the Orb may start an auction for it for their own benefit. Once auction is finalized, most of the
    ///          proceeds (minus the royalty) go to the relinquishing Keeper. Alternatives to relinquisment are setting
    ///          the price to zero or withdrawing all funds. Orb creator cannot start the keeper auction via this
    ///          function, and must call `relinquish(false)` and `startAuction()` separately to run the creator
    ///          auction.
    /// @dev     Calls `_withdraw()`, which does value transfer from the contract. Emits `Relinquishment`,
    ///          `Withdrawal`, and optionally `AuctionStart`.
    function relinquish(uint256 orbId) external virtual onlyKeeper(orbId) {
        if (purchaseOrder[orbId].purchaser != address(0)) {
            revert NotPermitted();
        }
        _settle(orbId);

        price[orbId] = 0;
        keeper[orbId] = address(this);

        emit Relinquishment(orbId, _msgSender());

        address reallocation = reallocationContract[orbId];

        if (creator[orbId] != _msgSender() && reallocation != address(0)) {
            allocationBeneficiary[orbId] = _msgSender();
            IAllocationMethod(reallocation).start(orbId);

            emit AllocationStart(orbId, reallocation, _msgSender());
        }

        _withdraw(orbId, _msgSender(), fundsOf[orbId][_msgSender()]);
    }

    /// @notice  Foreclose can be called by anyone after the Orb keeper runs out of funds to cover the Harberger tax.
    ///          It returns the Orb to the contract and starts a auction to find the next keeper. Most of the proceeds
    ///          (minus the royalty) go to the previous keeper.
    /// @dev     Emits `Foreclosure`, and optionally `AuctionStart`.
    function foreclose(uint256 orbId) external virtual onlyKeeperHeld(orbId) {
        if (_keeperSolvent(orbId)) {
            revert KeeperSolvent();
        }

        if (purchaseOrder[orbId].purchaser != address(0)) {
            return finalizePurchase(orbId);
        }

        _settle(orbId);

        address _keeper = keeper[orbId];
        price[orbId] = 0;
        keeper[orbId] = address(this);

        emit Foreclosure(orbId, _keeper);

        address reallocation = reallocationContract[orbId];

        if (reallocation != address(0)) {
            allocationBeneficiary[orbId] = _keeper;
            IAllocationMethod(reallocation).start(orbId);

            emit AllocationStart(orbId, reallocation, _keeper);
        }
    }

    function transferCreatorship(uint256 orbId, address newCreator_) external virtual onlyCreator(orbId) {
        // can be transferred even if held by keeper -- creator control not needed
        // can't be changed to keeper address or contract address or zero address
        if (newCreator_ == address(0) || newCreator_ == address(this) || newCreator_ == keeper[orbId]) {
            revert AddressInvalid(newCreator_);
        }
        // if held by creator, transfers the Orb to the new creator, does not touch funds or earnings
        if (keeper[orbId] == creator[orbId]) {
            keeper[orbId] = newCreator_;
        }
        creator[orbId] = newCreator_;
        emit CreatorUpdate(orbId, newCreator_);
    }

    function transfer(uint256 orbId, address newKeeper_) external virtual onlyKeeper(orbId) {
        if (newKeeper_ == address(0) || newKeeper_ == address(this) || newKeeper_ == creator[orbId]) {
            revert AddressInvalid(newKeeper_);
        }
        if (_msgSender() == creator[orbId]) {
            revert NotPermitted();
        }

        _settle(orbId);
        uint256 keeperFunds = fundsOf[orbId][_msgSender()];
        fundsOf[orbId][_msgSender()] = 0;
        fundsOf[orbId][newKeeper_] += keeperFunds;

        keeper[orbId] = newKeeper_;
        emit OrbTransfer(orbId, _msgSender(), newKeeper_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: UPGRADING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbVersion  Version of the Orb.
    function version() public pure virtual returns (uint256 orbVersion) {
        return _VERSION;
    }

    /// @dev  Authorizes owner address to upgrade the contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address newImplementation_) internal virtual override onlyOwner {}

    function _platformFee() internal virtual override returns (uint256) {
        return os.platformFee();
    }

    function _feeDenominator() internal virtual override returns (uint256) {
        return os.feeDenominator();
    }

    function _earningsWithdrawalAddress(address user) internal virtual override returns (address) {
        return os.earningsWithdrawalAddress(user);
    }
}
