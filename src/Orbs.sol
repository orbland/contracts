// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {InvocationRegistry} from "./InvocationRegistry.sol";
import {PledgeLocker} from "./PledgeLocker.sol";
import {AllocationMethod} from "./allocation/AllocationMethod.sol";

/// @title   Orbs - Shared registry for Harberger-taxed tokens with on-chain invocations
/// @author  Jonas Lekevicius
/// @author  Eric Wall
/// @custom:security-contact security@orb.land
contract Orbs is OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event Creation(uint256 indexed orbId, address indexed creator);

    // Funding Events
    event Deposit(uint256 indexed orbId, address indexed depositor, uint256 amount);
    event Withdrawal(uint256 indexed orbId, address indexed recipient, uint256 amount);
    event Settlement(uint256 indexed orbId, address indexed keeper, uint256 amount);

    // Purchasing Events
    event PriceUpdate(uint256 indexed orbId, address indexed keeper, uint256 previousPrice, uint256 newPrice);
    event Purchase(uint256 indexed orbId, address indexed seller, address indexed buyer, uint256 price);

    // Orb Ownership Events
    event Foreclosure(uint256 indexed orbId, address indexed formerKeeper);
    event Relinquishment(uint256 indexed orbId, address indexed formerKeeper);
    event Recall(uint256 indexed orbId, address indexed formerKeeper);

    // Allocation
    event AllocationStart(uint256 indexed orbId, address indexed beneficiary);
    event AllocationFinalization(
        uint256 indexed orbId, address indexed beneficiary, address indexed recipient, uint256 proceeds
    );

    // Orb Parameter Events
    event FeesUpdate(
        uint256 indexed orbId,
        uint256 previousKeeperTax,
        uint256 newKeeperTax,
        uint256 previousPurchaseRoyalty,
        uint256 newPurchaseRoyalty,
        uint256 previousReallocationRoyalty,
        uint256 newReallocationRoyalty
    );
    event AllocationContractUpdate(uint256 indexed orbId, address previousContract, address indexed newContract);

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

    // Orb Parameter Errors
    error RoyaltyNumeratorExceedsDenominator(uint256 royalty, uint256 feeDenominator);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS

    /// Orb version. Value: 1.
    uint256 private constant _VERSION = 1;
    /// Fee Nominator: basis points (100.00%). Other fees are in relation to this, and formatted as such.
    uint256 internal constant _FEE_DENOMINATOR = 100_00;
    /// Orb Land revenue share - 5% when withdrawing earnings
    uint256 internal constant _PLATFORM_FEE = 5_00;
    /// Harberger tax period: for how long the tax rate applies. Value: 1 year.

    uint256 internal constant _KEEPER_TAX_PERIOD = 365 days;
    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;

    // STATE

    // Address Variables

    /// Orb count: how many Orbs have been created.
    uint256 public orbCount;

    /// Orb Invocation Registry
    address public registry;
    /// Orb Token Locker
    address public pledgeLocker;
    /// Orb Land signing authority. Used to verify Orb creation authorization.
    address public signingAuthority;
    /// Address of the Orb creator.

    mapping(uint256 orbId => address) public creator;
    /// Address of the Orb keeper. The keeper is the address that owns the Orb and has the right to invoke the Orb and
    /// receive a response. The keeper is also the address that pays the Harberger tax.
    mapping(uint256 orbId => address) public keeper;
    /// Contract used for Orb Keeper Allocation process
    mapping(uint256 orbId => address) public allocationContract;

    // Funds Variables

    /// Funds tracker, per Orb and per address. Modified by deposits, withdrawals and settlements.
    /// The value is without settlement.
    /// It means effective user funds (withdrawable) would be different for keeper (subtracting
    /// `_owedSinceLastSettlement()`) and beneficiary (adding `_owedSinceLastSettlement()`). If Orb is held by the
    /// creator, funds are not subtracted, as Harberger tax does not apply to the creator.
    mapping(uint256 orbId => mapping(address => uint256)) public fundsOf;
    /// Earnings are:
    /// - The auction winning bid amount;
    /// - Royalties from Orb purchase when not purchased from the Orb creator;
    /// - Full purchase price when purchased from the Orb creator;
    /// - Harberger tax revenue.
    mapping(uint256 orbId => uint256) public earnings;
    /// Orb Land earnings
    uint256 public platformEarnings;

    // Fees State Variables

    /// Harberger tax for holding. Initial value is 120.00%.
    mapping(uint256 orbId => uint256) public keeperTax;
    /// Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 10.00%.
    mapping(uint256 orbId => uint256) public purchaseRoyalty;
    /// Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 30.00%.
    mapping(uint256 orbId => uint256) public reallocationRoyalty;
    /// Price of the Orb. Also used during auction to store future purchase price. Has no meaning if the Orb is held by
    /// the contract and the auction is not running.
    mapping(uint256 orbId => uint256) public price;
    /// Last time Orb keeper's funds were settled. Used to calculate amount owed since last settlement. Has no meaning
    /// if the Orb is held by the contract.
    mapping(uint256 orbId => uint256) public lastSettlementTime;

    /// Allocation Beneficiary: address that receives most of the auction proceeds. Zero address if run by creator.
    mapping(uint256 orbId => address) public allocationBeneficiary;

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
        _;
    }

    // ORB STATE MODIFIERS

    /// @dev  Ensures that the Orb belongs to someone (possibly creator), not the contract itself.
    modifier onlyKeeperHeld(uint256 orbId) virtual {
        if (address(this) == keeper[orbId]) {
            revert ContractHoldsOrb();
        }
        _;
    }

    modifier onlyCreatorControlled(uint256 orbId) virtual {
        if (!isCreatorControlled(orbId)) {
            revert CreatorDoesNotControlOrb();
        }
        _;
    }

    // AUCTION MODIFIERS

    /// @dev  Ensures that an auction is currently not running. Can be multiple states: auction not started, auction
    ///       over but not finalized, or auction finalized.
    modifier notDuringAllocation(uint256 orbId) virtual {
        if (_isAllocationActive(orbId)) {
            revert AllocationActive();
        }
        _;
    }

    // FUNDS-RELATED MODIFIERS

    /// @dev  Ensures that the current Orb keeper has enough funds to cover Harberger tax until now.
    modifier onlyKeeperSolvent(uint256 orbId) virtual {
        if (!keeperSolvent(orbId)) {
            revert KeeperInsolvent();
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

    function initalize(address registry_, address pledgeLocker_, address signingAuthority_) public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();

        registry = registry_;
        pledgeLocker = pledgeLocker_;
        signingAuthority = signingAuthority_;
    }

    /// @dev  Ensures that the Orb belongs to the contract itself or the creator, and the auction hasn't been started.
    ///       Most setting-adjusting functions should use this modifier. It means that the Orb properties cannot be
    ///       modified while it is held by the keeper or users can bid on the Orb.
    ///       V2 changes to allow setting parameters even during Keeper control, if Oath has expired.
    ///       TODO change this considerably
    /*
        When does creator control Orb?
        - (held by contract OR held by creator) AND allocation is not running
        - held by keeper AND a question is unanswered past the deadline
    */
    // Creator CAN control Orb (does not revert) if any of these FALSE:
    // - Orb is not held by the contract itself
    // - Orb is not held by the creator
    // - Oath is still honored
    // Inverted, this means that the creator CAN control if any of these are TRUE:
    // - Orb is held by the contract itself
    // - Orb is held by the creator
    // - Oath is not honored (even if Orb is held by the Keeper)
    function isCreatorControlled(uint256 orbId) public view virtual returns (bool) {
        if (AllocationMethod(allocationContract[orbId]).isAllocationUnfinalized(orbId)) {
            return false;
        }

        if (address(this) == keeper[orbId] || creator[orbId] == keeper[orbId]) {
            // TODO but only if pledge is not claimable???
            return true;
        }

        // TODO change to: has expired invocation that is no longer claimable, and missing response
        (bool hasExpiredInvocation,) = InvocationRegistry(registry).hasExpiredPeriodInvocation(orbId);
        if (hasExpiredInvocation && InvocationRegistry(registry).hasUnrespondedInvocation(orbId)) {
            // TODO add pledge is not claimable
            return true;
        }

        return true;
    }

    /// @dev     Returns if the auction is currently running. Use `auctionEndTime()` to check when it ends.
    /// @return  isAllocationActive  If the auction is running.
    function _isAllocationActive(uint256 orbId) internal view virtual returns (bool) {
        return AllocationMethod(allocationContract[orbId]).isAllocationActive(orbId);
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
        if (signingAddress != signingAuthority) {
            revert AddressUnauthorized(_msgSender());
        }

        creator[orbId] = _msgSender();
        keeper[orbId] = address(this);

        keeperTax[orbId] = 120_00;
        purchaseRoyalty[orbId] = 10_00;
        reallocationRoyalty[orbId] = 30_00;

        allocationContract[orbId] = allocationContract_;
        AllocationMethod(allocationContract_).initializeOrb(orbId);
        InvocationRegistry(registry).initializeOrb(orbId);
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
        if (purchaseRoyalty_ > _FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(purchaseRoyalty_, _FEE_DENOMINATOR);
        }
        if (reallocationRoyalty_ > _FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(reallocationRoyalty_, _FEE_DENOMINATOR);
        }

        uint256 previousKeeperTax = keeperTax[orbId];
        keeperTax[orbId] = keeperTax_;

        uint256 previousPurchaseRoyalty = purchaseRoyalty[orbId];
        purchaseRoyalty[orbId] = purchaseRoyalty_;

        uint256 previousAuctionRoyalty = reallocationRoyalty[orbId];
        reallocationRoyalty[orbId] = reallocationRoyalty_;

        emit FeesUpdate(
            orbId,
            previousKeeperTax,
            keeperTax_,
            previousPurchaseRoyalty,
            purchaseRoyalty_,
            previousAuctionRoyalty,
            reallocationRoyalty_
        );
    }

    function setAllocationContract(uint256 orbId, address allocationContract_)
        external
        virtual
        onlyCreator(orbId)
        onlyCreatorControlled(orbId)
    {
        allocationContract[orbId] = allocationContract_;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: DISCOVERY
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.
    /// @dev     Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
    ///          after auction is finalized. Emits `AuctionStart`.
    ///          V2 adds `onlyHonored` modifier to require active Oath to start auction.
    function startAllocation(uint256 orbId) external virtual onlyCreator(orbId) notDuringAllocation(orbId) {
        if (address(this) != keeper[orbId]) {
            revert ContractDoesNotHoldOrb();
        }
        if (InvocationRegistry(registry).hasUnrespondedInvocation(orbId)) {
            revert UnrespondedInvocationExists();
        }

        allocationBeneficiary[orbId] = creator[orbId];
        AllocationMethod(allocationContract[orbId]).startAllocation(orbId, false);

        emit AllocationStart(orbId, allocationBeneficiary[orbId]);
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
    function finalizeAllocation(
        uint256 orbId,
        uint256 proceeds_,
        uint256 duration_,
        address recipient_,
        uint256 recipientFunds_,
        uint256 initialPrice_
    ) external virtual notDuringAllocation(orbId) {
        // check that called from allocation contract

        if (recipient_ != address(0)) {
            uint256 _allocationMinimumRoyalty = (keeperTax[orbId] * duration_) / _KEEPER_TAX_PERIOD;
            uint256 _actualAllocationRoyalty = _allocationMinimumRoyalty > reallocationRoyalty[orbId]
                ? _allocationMinimumRoyalty
                : reallocationRoyalty[orbId];
            _splitProceeds(orbId, proceeds_, allocationBeneficiary[orbId], _actualAllocationRoyalty);

            fundsOf[orbId][recipient_] += recipientFunds_;

            lastSettlementTime[orbId] = block.timestamp;
            if (allocationBeneficiary[orbId] == creator[orbId]) {
                InvocationRegistry(registry).initializeOrbInvocationPeriod(orbId);
            }

            _setPrice(orbId, initialPrice_);
            emit AllocationFinalization(orbId, allocationBeneficiary[orbId], recipient_, proceeds_);

            keeper[orbId] = recipient_;
        } else {
            emit AllocationFinalization(orbId, allocationBeneficiary[orbId], address(0), 0);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: FUNDS AND HOLDING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Allows depositing funds on the contract. Not allowed for insolvent keepers.
    /// @dev     Deposits are not allowed for insolvent keepers to prevent cheating via front-running. If the user
    ///          becomes insolvent, the Orb will always be returned to the contract as the next step. Emits `Deposit`.
    function deposit(uint256 orbId) external payable virtual {
        if (_msgSender() == keeper[orbId] && !keeperSolvent(orbId)) {
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
        _withdraw(orbId, _msgSender(), amount_);
    }

    /// @notice  Function to withdraw all funds on the contract. Not recommended for current Orb keepers if the price
    ///          is not zero, as they will become immediately foreclosable. To give up the Orb, call `relinquish()`.
    /// @dev     Not allowed for the leading auction bidder.
    function withdrawAll(uint256 orbId) external virtual {
        _withdraw(orbId, _msgSender(), fundsOf[orbId][_msgSender()]);
    }

    /// @notice  Function to withdraw all beneficiary funds on the contract. Settles if possible.
    /// @dev     Allowed for anyone at any time, does not use `_msgSender()` in its execution.
    ///          Emits `Withdrawal`.
    ///          V2 changes to withdraw to `beneficiaryWithdrawalAddress` if set to a non-zero address, and copies
    ///          `_withdraw()` functionality to this function, as it modifies funds of a different address (always
    ///          `beneficiary`) than the withdrawal destination (potentially `beneficiaryWithdrawalAddress`).
    function withdrawAllEarnings(uint256 orbId) external virtual {
        if (keeper[orbId] != address(this)) {
            _settle(orbId);
        }

        address _creator = creator[orbId];

        uint256 amount = earnings[orbId];
        uint256 platformShare = (amount * _PLATFORM_FEE) / _FEE_DENOMINATOR;
        uint256 creatorShare = amount - platformShare;

        earnings[orbId] = 0;
        platformEarnings += platformShare;

        emit Withdrawal(orbId, _creator, creatorShare);
        Address.sendValue(payable(_creator), creatorShare);
    }

    function withdrawPlatformEarnings() external virtual {
        uint256 amount = platformEarnings;
        platformEarnings = 0;

        emit Withdrawal(0, owner(), amount);
        Address.sendValue(payable(owner()), amount);
    }

    /// @notice  Settlements transfer funds from Orb keeper to the beneficiary. Orb accounting minimizes required
    ///          transactions: Orb keeper's foreclosure time is only dependent on the price and available funds. Fund
    ///          transfers are not necessary unless these variables (price, keeper funds) are being changed. Settlement
    ///          transfers funds owed since the last settlement, and a new period of virtual accounting begins.
    /// @dev     See also `_settle()`.
    function settle(uint256 orbId) external virtual onlyKeeperHeld(orbId) {
        _settle(orbId);
    }

    /// @dev     Returns if the current Orb keeper has enough funds to cover Harberger tax until now. Always true if
    ///          creator holds the Orb.
    /// @return  isKeeperSolvent  If the current keeper is solvent.
    function keeperSolvent(uint256 orbId) public view virtual returns (bool isKeeperSolvent) {
        if (creator[orbId] == keeper[orbId]) {
            return true;
        }
        return fundsOf[orbId][keeper[orbId]] >= _owedSinceLastSettlement(orbId);
    }

    /// @dev     Calculates how much money Orb keeper owes Orb beneficiary. This amount would be transferred between
    ///          accounts during settlement. **Owed amount can be higher than keeper's funds!** It's important to check
    ///          if keeper has enough funds before transferring.
    /// @return  owedValue  Wei Orb keeper owes Orb beneficiary since the last settlement time.
    function _owedSinceLastSettlement(uint256 orbId) internal view virtual returns (uint256 owedValue) {
        uint256 taxedUntil = block.timestamp;
        // TODO review
        if (InvocationRegistry(registry).hasUnrespondedInvocation(orbId)) {
            // Settles during response, so we only need to account for pause if an invocation has no response
            uint256 invocationTimestamp = InvocationRegistry(registry).lastInvocationTime(orbId);
            uint256 invocationPeriod = InvocationRegistry(registry).invocationPeriod(orbId);
            if (block.timestamp > invocationTimestamp + invocationPeriod) {
                taxedUntil = invocationTimestamp + invocationPeriod;
            }
        }
        uint256 secondsSinceLastSettlement =
            taxedUntil > lastSettlementTime[orbId] ? taxedUntil - lastSettlementTime[orbId] : 0;
        return (price[orbId] * keeperTax[orbId] * secondsSinceLastSettlement) / (_KEEPER_TAX_PERIOD * _FEE_DENOMINATOR);
    }

    /// @dev    Executes the withdrawal for a given amount, does the actual value transfer from the contract to user's
    ///         wallet. The only function in the contract that sends value and has re-entrancy risk. Does not check if
    ///         the address is payable, as the Address library reverts if it is not. Emits `Withdrawal`.
    /// @param  recipient_  The address to send the value to.
    /// @param  amount_     The value in wei to withdraw from the contract.
    function _withdraw(uint256 orbId, address recipient_, uint256 amount_) internal virtual {
        if (recipient_ == keeper[orbId]) {
            _settle(orbId);
        }

        if (fundsOf[orbId][recipient_] < amount_) {
            revert InsufficientFunds(fundsOf[orbId][recipient_], amount_);
        }

        fundsOf[orbId][recipient_] -= amount_;

        emit Withdrawal(orbId, recipient_, amount_);

        Address.sendValue(payable(recipient_), amount_);
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
        earnings[orbId] += transferableToEarnings;

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
    function setPrice(uint256 orbId, uint256 newPrice_) external virtual onlyKeeper(orbId) onlyKeeperSolvent(orbId) {
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
    function listForSale(uint256 orbId, uint256 listingPrice_) external virtual onlyCreator(orbId) {
        if (address(this) != keeper[orbId]) {
            revert ContractDoesNotHoldOrb();
        }
        if (InvocationRegistry(registry).hasUnrespondedInvocation(orbId)) {
            revert UnrespondedInvocationExists();
        }

        if (AllocationMethod(allocationContract[orbId]).isAllocationActive(orbId)) {
            revert AllocationActive();
        }

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
    /// @param  orbId                      ID of the Orb to purchase.
    /// @param  newPrice_                  New price to use after the purchase.
    /// @param  currentPrice_              Current price, to prevent front-running.
    /// @param  currentKeeperTax_          Current keeper tax numerator, to prevent front-running.
    /// @param  currentPurchaseRoyalty_    Current royalty numerator, to prevent front-running.
    /// @param  currentAllocationRoyalty_  Current keeper auction royalty numerator, to prevent front-running.
    /// @param  currentInvocationPeriod_   Current invocation period, to prevent front-running.
    /// @param  currentPledgedUntil_       Current honored until timestamp, to prevent front-running.
    function purchase(
        uint256 orbId,
        uint256 newPrice_,
        uint256 currentPrice_,
        uint256 currentKeeperTax_,
        uint256 currentPurchaseRoyalty_,
        uint256 currentAllocationRoyalty_,
        uint256 currentInvocationPeriod_,
        uint256 currentPledgedUntil_
    ) external payable virtual onlyKeeperHeld(orbId) onlyKeeperSolvent(orbId) {
        if (currentPrice_ != price[orbId]) {
            revert CurrentValueIncorrect(currentPrice_, price[orbId]);
        }
        if (currentKeeperTax_ != keeperTax[orbId]) {
            revert CurrentValueIncorrect(currentKeeperTax_, keeperTax[orbId]);
        }
        if (currentPurchaseRoyalty_ != purchaseRoyalty[orbId]) {
            revert CurrentValueIncorrect(currentPurchaseRoyalty_, purchaseRoyalty[orbId]);
        }
        if (currentAllocationRoyalty_ != reallocationRoyalty[orbId]) {
            revert CurrentValueIncorrect(currentAllocationRoyalty_, reallocationRoyalty[orbId]);
        }
        if (currentInvocationPeriod_ != InvocationRegistry(registry).invocationPeriod(orbId)) {
            revert CurrentValueIncorrect(currentInvocationPeriod_, InvocationRegistry(registry).invocationPeriod(orbId));
        }
        if (currentPledgedUntil_ != PledgeLocker(pledgeLocker).pledgedUntil(orbId)) {
            revert CurrentValueIncorrect(currentPledgedUntil_, PledgeLocker(pledgeLocker).pledgedUntil(orbId));
        }

        if (lastSettlementTime[orbId] >= block.timestamp) {
            revert PurchasingNotPermitted();
        }

        _settle(orbId);

        address _keeper = keeper[orbId];

        if (_msgSender() == _keeper) {
            revert AlreadyKeeper();
        }

        fundsOf[orbId][_msgSender()] += msg.value;
        uint256 totalFunds = fundsOf[orbId][_msgSender()];

        if (totalFunds < currentPrice_) {
            revert InsufficientFunds(totalFunds, currentPrice_);
        }

        fundsOf[orbId][_msgSender()] -= currentPrice_;
        if (creator[orbId] == _keeper) {
            InvocationRegistry(registry).initializeOrbInvocationPeriod(orbId);
            earnings[orbId] += currentPrice_;
        } else {
            _splitProceeds(orbId, currentPrice_, _keeper, purchaseRoyalty[orbId]);
        }

        _setPrice(orbId, newPrice_);

        emit Purchase(orbId, _keeper, _msgSender(), currentPrice_);

        keeper[orbId] = _msgSender();
    }

    /// @notice  Allows the Orb creator to reclaim the Orb from the Keeper, if the Oath is no longer honored. This is an
    ///          alternative to just extending the Oath or swearing it while held by Keeper. It benefits the Orb creator
    ///          as they can set a new Oath and run a new auction. This acts as an alternative to just abandoning the
    ///          Orb after Oath expires.
    /// @dev     Emits `Recall`. Does not transfer remaining funds to the Keeper to allow reclaiming even if the Keeper
    ///          is a smart contract rejecting ether transfers.
    function reclaim(uint256 orbId) external virtual onlyCreator(orbId) {
        address _keeper = keeper[orbId];
        if (address(this) == _keeper || creator[orbId] == _keeper) {
            revert KeeperDoesNotHoldOrb();
        }

        // TODO pledge must not be claimable

        // TODO add some conditions, or the whole isCreatorControlled

        (bool hasExpiredInvocation,) = InvocationRegistry(registry).hasExpiredPeriodInvocation(orbId);
        if (!hasExpiredInvocation || !InvocationRegistry(registry).hasUnrespondedInvocation(orbId)) {
            revert OrbNotReclaimable();
            // TODO require that NFT would not be claimable
        }
        // Auction cannot be running while held by Keeper, no check needed

        _settle(orbId);

        price[orbId] = 0;
        keeper[orbId] = address(this);
        InvocationRegistry(registry).resetExpiredPeriodInvocation(orbId);

        emit Recall(orbId, _keeper);
    }

    /// @dev    Assigns proceeds to beneficiary and primary receiver, accounting for royalty. Used by `purchase()` and
    ///         `finalizeAuction()`. Fund deducation should happen before calling this function. Receiver might be
    ///         beneficiary if no split is needed.
    /// @param  proceeds_  Total proceeds to split between beneficiary and receiver.
    /// @param  receiver_  Address of the receiver of the proceeds minus royalty.
    /// @param  royalty_   Beneficiary royalty numerator to use for the split.
    function _splitProceeds(uint256 orbId, uint256 proceeds_, address receiver_, uint256 royalty_) internal virtual {
        uint256 royaltyShare = (proceeds_ * royalty_) / _FEE_DENOMINATOR;
        uint256 receiverShare = proceeds_ - royaltyShare;
        earnings[orbId] += royaltyShare;
        fundsOf[orbId][receiver_] += receiverShare;
    }

    /// @dev    Does not check if the new price differs from the previous price: no risk. Limits the price to
    ///         MAXIMUM_PRICE to prevent potential overflows in math. Emits `PriceUpdate`.
    /// @param  price_  New price for the Orb.
    function _setPrice(uint256 orbId, uint256 price_) internal virtual {
        if (price_ > _MAXIMUM_PRICE) {
            revert InvalidPrice(price_);
        }

        uint256 previousPrice = price[orbId];
        price[orbId] = price_;

        emit PriceUpdate(orbId, keeper[orbId], previousPrice, price_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: RELINQUISHMENT AND FORECLOSURE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Relinquishment is a voluntary giving up of the Orb. It's a combination of withdrawing all funds not
    ///          owed to the beneficiary since last settlement and transferring the Orb to the contract. Keepers giving
    ///          up the Orb may start an auction for it for their own benefit. Once auction is finalized, most of the
    ///          proceeds (minus the royalty) go to the relinquishing Keeper. Alternatives to relinquisment are setting
    ///          the price to zero or withdrawing all funds. Orb creator cannot start the keeper auction via this
    ///          function, and must call `relinquish(false)` and `startAuction()` separately to run the creator
    ///          auction.
    /// @dev     Calls `_withdraw()`, which does value transfer from the contract. Emits `Relinquishment`,
    ///          `Withdrawal`, and optionally `AuctionStart`.
    function relinquish(uint256 orbId) external virtual onlyKeeper(orbId) onlyKeeperSolvent(orbId) {
        _settle(orbId);

        price[orbId] = 0;
        emit Relinquishment(orbId, _msgSender());

        if (creator[orbId] != _msgSender() && AllocationMethod(allocationContract[orbId]).isReallocationEnabled(orbId))
        {
            allocationBeneficiary[orbId] = _msgSender();
            AllocationMethod(allocationContract[orbId]).startAllocation(orbId, true);
            // TODO somehow communicate that its Keeper auction
            // initialAllocation and reallocation

            emit AllocationStart(orbId, allocationBeneficiary[orbId]);
        }

        // TODO pledge must not be claimable
        keeper[orbId] = address(this);
        InvocationRegistry(registry).resetExpiredPeriodInvocation(orbId);

        _withdraw(orbId, _msgSender(), fundsOf[orbId][_msgSender()]);
    }

    /// @notice  Foreclose can be called by anyone after the Orb keeper runs out of funds to cover the Harberger tax.
    ///          It returns the Orb to the contract and starts a auction to find the next keeper. Most of the proceeds
    ///          (minus the royalty) go to the previous keeper.
    /// @dev     Emits `Foreclosure`, and optionally `AuctionStart`.
    function foreclose(uint256 orbId) external virtual onlyKeeperHeld(orbId) {
        if (keeperSolvent(orbId)) {
            revert KeeperSolvent();
        }

        _settle(orbId);

        address _keeper = keeper[orbId];
        price[orbId] = 0;

        emit Foreclosure(orbId, _keeper);

        if (AllocationMethod(allocationContract[orbId]).isReallocationEnabled(orbId)) {
            allocationBeneficiary[orbId] = _keeper;
            AllocationMethod(allocationContract[orbId]).startAllocation(orbId, true);
            // TODO somehow communicate that its Keeper auction
            // initialAllocation and reallocation

            emit AllocationStart(orbId, allocationBeneficiary[orbId]);
        }

        // TODO pledge must not be claimable
        keeper[orbId] = address(this);
        InvocationRegistry(registry).resetExpiredPeriodInvocation(orbId);
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
}

// TODOs:
// - everything about token locking
// - allocation running check
// - admin, upgrade functions
// - expose is creator controlled logic
// - documentation
//   - first, for myself: to understand when all actions can be taken
//   - particularly token and settings related
