// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {OrbInvocationRegistry} from "./OrbInvocationRegistry.sol";
import {OrbTokenLocker} from "./OrbTokenLocker.sol";
import {IKeeperDiscovery} from "./discovery/IKeeperDiscovery.sol";

/// @title   Orbs - Shared registry for Harberger-taxed tokens with on-chain invocations
/// @author  Jonas Lekevicius
/// @author  Eric Wall
/// @custom:security-contact security@orb.land
contract Orbs is OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STRUCTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    struct ERC721Token {
        address contractAddress;
        uint256 tokenId;
    }

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

    // Discovery
    event DiscoveryStart(uint256 indexed orbId, address indexed discoveryBeneficiary, uint256 discoveryStartTime);
    event DiscoveryFinalization(
        uint256 indexed orbId,
        address indexed discoveryBeneficiary,
        address indexed discoveryWinner,
        uint256 discoveryWinningAmount,
        uint256 discoveryEndTime
    );

    // Orb Parameter Events
    event FeesUpdate(
        uint256 indexed orbId,
        uint256 previousKeeperTaxNumerator,
        uint256 newKeeperTaxNumerator,
        uint256 previousPurchaseRoyaltyNumerator,
        uint256 newPurchaseRoyaltyNumerator,
        uint256 previousDiscoveryRoyaltyNumerator,
        uint256 newDiscoveryRoyaltyNumerator
    );

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Authorization Errors
    error NotCreator();
    error NotKeeper();
    error AlreadyKeeper();
    error ContractHoldsOrb();
    error ContractDoesNotHoldOrb();
    error CreatorDoesNotControlOrb();

    // Discovery Errors
    error DiscoveryActive();

    // Funding Errors
    error KeeperSolvent();
    error KeeperInsolvent();
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);

    // Purchasing Errors
    error CurrentValueIncorrect(uint256 valueProvided, uint256 currentValue);
    error PurchasingNotPermitted();
    error InvalidNewPrice(uint256 priceProvided);

    // Orb Parameter Errors
    error LockedUntilNotDecreasable();
    error RoyaltyNumeratorExceedsDenominator(uint256 royaltyNumerator, uint256 feeDenominator);

    error AddressNotPermitted(address unauthorizedAddress);
    error KeeperDoesNotHoldOrb();
    error TokenStillLocked();

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS

    /// Orb version. Value: 1.
    uint256 private constant _VERSION = 1;
    /// Fee Nominator: basis points (100.00%). Other fees are in relation to this, and formatted as such.
    uint256 internal constant _FEE_DENOMINATOR = 100_00;
    /// Harberger tax period: for how long the tax rate applies. Value: 1 year.
    uint256 internal constant _KEEPER_TAX_PERIOD = 365 days;
    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;
    /// Orb Land revenue share - 5% when withdrawing earnings
    uint256 internal constant _PLATFORM_REVENUE_SHARE = 5_00;

    // STATE

    // Address Variables

    /// Orb count: how many Orbs have been created.
    uint256 public orbCount;

    /// Orb Invocation Registry
    address public registry;
    /// Orb Token Locker
    address public tokenLocker;
    /// Orb Land signing authority. Used to verify Orb creation authorization.
    address public signingAuthority;
    /// Address of the Orb creator.
    mapping(uint256 ordId => address creator) public creator;
    /// Address of the Orb keeper. The keeper is the address that owns the Orb and has the right to invoke the Orb and
    /// receive a response. The keeper is also the address that pays the Harberger tax.
    mapping(uint256 ordId => address keeper) public keeper;
    /// Contract used for Orb Keeper Discovery process
    mapping(uint256 orbId => address discoveryContract) public keeperDiscoveryContract;

    // Funds Variables

    /// Funds tracker, per Orb and per address. Modified by deposits, withdrawals and settlements.
    /// The value is without settlement.
    /// It means effective user funds (withdrawable) would be different for keeper (subtracting
    /// `_owedSinceLastSettlement()`) and beneficiary (adding `_owedSinceLastSettlement()`). If Orb is held by the
    /// creator, funds are not subtracted, as Harberger tax does not apply to the creator.
    mapping(uint256 orbId => mapping(address => uint256 funds)) public fundsOf;
    /// Earnings are:
    /// - The auction winning bid amount;
    /// - Royalties from Orb purchase when not purchased from the Orb creator;
    /// - Full purchase price when purchased from the Orb creator;
    /// - Harberger tax revenue.
    mapping(uint256 orbId => uint256 earnings) public earnings;
    /// Orb Land earnings
    uint256 public platformFunds;

    // Fees State Variables

    /// Harberger tax for holding. Initial value is 120.00%.
    mapping(uint256 orbId => uint256) public keeperTaxNumerator;
    /// Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 10.00%.
    mapping(uint256 orbId => uint256) public purchaseRoyaltyNumerator;
    /// Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 30.00%.
    mapping(uint256 orbId => uint256) public discoveryRoyaltyNumerator;
    /// Price of the Orb. Also used during auction to store future purchase price. Has no meaning if the Orb is held by
    /// the contract and the auction is not running.
    mapping(uint256 orbId => uint256) public price;
    /// Last time Orb keeper's funds were settled. Used to calculate amount owed since last settlement. Has no meaning
    /// if the Orb is held by the contract.
    mapping(uint256 orbId => uint256) public lastSettlementTime;

    /// Discovery Beneficiary: address that receives most of the auction proceeds. Zero address if run by creator.
    mapping(uint256 orbId => address) public discoveryBeneficiary;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initalize(address registry_, address tokenLocker_, address signingAuthority_) public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();

        registry = registry_;
        tokenLocker = tokenLocker_;
        signingAuthority = signingAuthority_;
    }

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
        if (!creatorControlled(orbId)) {
            revert CreatorDoesNotControlOrb();
        }
        _;
    }

    // AUCTION MODIFIERS

    /// @dev  Ensures that an auction is currently not running. Can be multiple states: auction not started, auction
    ///       over but not finalized, or auction finalized.
    modifier notDuringDiscovery(uint256 orbId) virtual {
        if (_discoveryActive(orbId)) {
            revert DiscoveryActive();
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

    /// @dev  Ensures that the Orb belongs to the contract itself or the creator, and the auction hasn't been started.
    ///       Most setting-adjusting functions should use this modifier. It means that the Orb properties cannot be
    ///       modified while it is held by the keeper or users can bid on the Orb.
    ///       V2 changes to allow setting parameters even during Keeper control, if Oath has expired.
    ///       TODO change this considerably
    /*
        When does creator control Orb?
        - (held by contract OR held by creator) AND discovery is not running
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
    function creatorControlled(uint256 orbId) public view virtual returns (bool) {
        if (IKeeperDiscovery(keeperDiscoveryContract[orbId]).discoveryActive(orbId)) {
            revert DiscoveryActive();
        }

        if (address(this) != keeper[orbId] && creator[orbId] != keeper[orbId]) {
            revert CreatorDoesNotControlOrb();
        }
        // lockedUntil[orbId] >= block.timestamp

        return true;
    }

    /// @dev     Returns if the auction is currently running. Use `auctionEndTime()` to check when it ends.
    /// @return  isDiscoveryActive  If the auction is running.
    function _discoveryActive(uint256 orbId) internal view virtual returns (bool isDiscoveryActive) {
        return IKeeperDiscovery(keeperDiscoveryContract[orbId]).discoveryActive(orbId);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ORB CREATION AND SETTINGS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev    When deployed, contract mints the only token that will ever exist, to itself.
    ///         This token represents the Orb and is called the Orb elsewhere in the contract.
    ///         `Ownable` sets the deployer to be the `owner()`, and also the creator in the Orb context.
    ///         V2 changes initial values and sets `auctionKeeperMinimumDuration`.
    function createAuthorized(address discoveryContract, bytes memory authorizationPayload)
        public
        virtual
        initializer
    {
        // check that authorizationPayload is signed from signing authority
        address signingAddress =
            ECDSA.recover(keccak256(abi.encodePacked(_msgSender(), discoveryContract)), authorizationPayload);
        if (signingAddress != signingAuthority) {
            revert AddressNotPermitted(_msgSender());
        }

        uint256 orbId = orbCount;
        creator[orbId] = _msgSender();
        keeper[orbId] = address(this);

        keeperTaxNumerator[orbId] = 120_00;
        purchaseRoyaltyNumerator[orbId] = 10_00;
        discoveryRoyaltyNumerator[orbId] = 30_00;

        keeperDiscoveryContract[orbId] = discoveryContract;
        IKeeperDiscovery(discoveryContract).initializeOrb(orbId);
        OrbInvocationRegistry(registry).initializeOrb(orbId);
        // Token Locker does not need to be initialized.

        orbCount++;

        emit Creation(orbId, _msgSender());
    }

    /// @notice  Allows the Orb creator to set the new keeper tax and royalty. This function can only be called by the
    ///          Orb creator when the Orb is in their control.
    /// @dev     Emits `FeesUpdate`.
    ///          V2 changes to allow setting Keeper auction royalty separately from purchase royalty, with releated
    ///          parameter and event changes.
    /// @param   newKeeperTaxNumerator        New keeper tax numerator, in relation to `feeDenominator()`.
    /// @param   newPurchaseRoyaltyNumerator  New royalty numerator for royalties from `purchase()`, in relation to
    ///                                       `feeDenominator()`. Cannot be larger than `feeDenominator()`.
    /// @param   newAuctionRoyaltyNumerator   New royalty numerator for royalties from keeper auctions, in relation to
    ///                                       `feeDenominator()`. Cannot be larger than `feeDenominator()`.
    function setFees(
        uint256 orbId,
        uint256 newKeeperTaxNumerator,
        uint256 newPurchaseRoyaltyNumerator,
        uint256 newAuctionRoyaltyNumerator
    ) external virtual onlyCreator(orbId) onlyCreatorControlled(orbId) {
        if (keeper[orbId] != address(this)) {
            _settle(orbId);
        }
        if (newPurchaseRoyaltyNumerator > _FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(newPurchaseRoyaltyNumerator, _FEE_DENOMINATOR);
        }
        if (newAuctionRoyaltyNumerator > _FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(newAuctionRoyaltyNumerator, _FEE_DENOMINATOR);
        }

        uint256 previousKeeperTaxNumerator = keeperTaxNumerator[orbId];
        keeperTaxNumerator[orbId] = newKeeperTaxNumerator;

        uint256 previousPurchaseRoyaltyNumerator = purchaseRoyaltyNumerator[orbId];
        purchaseRoyaltyNumerator[orbId] = newPurchaseRoyaltyNumerator;

        uint256 previousAuctionRoyaltyNumerator = discoveryRoyaltyNumerator[orbId];
        discoveryRoyaltyNumerator[orbId] = newAuctionRoyaltyNumerator;

        emit FeesUpdate(
            orbId,
            previousKeeperTaxNumerator,
            newKeeperTaxNumerator,
            previousPurchaseRoyaltyNumerator,
            newPurchaseRoyaltyNumerator,
            previousAuctionRoyaltyNumerator,
            newAuctionRoyaltyNumerator
        );
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: DISCOVERY
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.
    /// @dev     Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
    ///          after auction is finalized. Emits `AuctionStart`.
    ///          V2 adds `onlyHonored` modifier to require active Oath to start auction.
    function startDiscovery(uint256 orbId) external virtual onlyCreator(orbId) notDuringDiscovery(orbId) {
        if (address(this) != keeper[orbId]) {
            revert ContractDoesNotHoldOrb();
        }

        discoveryBeneficiary[orbId] = creator[orbId];
        IKeeperDiscovery(keeperDiscoveryContract[orbId]).startDiscovery(orbId, false);

        emit DiscoveryStart(orbId, discoveryBeneficiary[orbId], block.timestamp);
    }

    /// @notice  Finalizes the auction, transferring the winning bid to the beneficiary, and the Orb to the winner.
    ///          If the auction was started by previous Keeper with `relinquish(true)`, then most of the auction
    ///          proceeds (minus the royalty) will be sent to the previous Keeper. Sets `lastInvocationTime` so that
    ///          the Orb could be invoked immediately. The price has been set when bidding, now becomes relevant. If no
    ///          bids were made, resets the state to allow the auction to be started again later.
    /// @dev     Critical state transition function. Called after `auctionEndTime`, but only if it's not 0. Can be
    ///          called by anyone, although probably will be called by the creator or the winner. Emits `PriceUpdate`
    ///          and `AuctionFinalization`.
    ///          V2 fixes a bug with Keeper auctions changing lastInvocationTime, and uses `auctionRoyaltyNumerator`
    ///          instead of `purchaseRoyaltyNumerator` for auction royalty (only relevant for Keeper auctions).
    function finalizeDiscovery(
        uint256 orbId,
        address discoveryWinner,
        uint256 discoveryProceeds,
        uint256 winnerFunds,
        uint256 initialPrice,
        uint256 discoveryDuration
    ) external virtual notDuringDiscovery(orbId) {
        // check that called from discovery contract

        if (discoveryWinner != address(0)) {
            uint256 discoveryMinimumRoyaltyNumerator =
                (keeperTaxNumerator[orbId] * discoveryDuration) / _KEEPER_TAX_PERIOD;
            uint256 discoveryRoyalty = discoveryMinimumRoyaltyNumerator > discoveryRoyaltyNumerator[orbId]
                ? discoveryMinimumRoyaltyNumerator
                : discoveryRoyaltyNumerator[orbId];
            _splitProceeds(orbId, discoveryProceeds, discoveryBeneficiary[orbId], discoveryRoyalty);

            fundsOf[orbId][discoveryWinner] += winnerFunds;

            lastSettlementTime[orbId] = block.timestamp;
            if (discoveryBeneficiary[orbId] == creator[orbId]) {
                OrbInvocationRegistry(registry).chargeOrb(orbId);
            }

            _setPrice(orbId, initialPrice);
            emit DiscoveryFinalization(
                orbId, discoveryBeneficiary[orbId], discoveryWinner, discoveryProceeds, block.timestamp
            );

            keeper[orbId] = discoveryWinner;
        } else {
            emit DiscoveryFinalization(orbId, discoveryBeneficiary[orbId], address(0), 0, block.timestamp);
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
    /// @param   amount  The amount to withdraw.
    function withdraw(uint256 orbId, uint256 amount) external virtual {
        _withdraw(orbId, _msgSender(), amount);
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
        uint256 platformShare = (amount * _PLATFORM_REVENUE_SHARE) / _FEE_DENOMINATOR;
        uint256 creatorShare = amount - platformShare;

        earnings[orbId] = 0;
        platformFunds += platformShare;

        emit Withdrawal(orbId, _creator, creatorShare);
        Address.sendValue(payable(_creator), creatorShare);
    }

    function withdrawPlatformEarnings() external virtual {
        uint256 amount = platformFunds;
        platformFunds = 0;

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
        uint256 secondsSinceLastSettlement = block.timestamp - lastSettlementTime[orbId];
        return (price[orbId] * keeperTaxNumerator[orbId] * secondsSinceLastSettlement)
            / (_KEEPER_TAX_PERIOD * _FEE_DENOMINATOR);
    }

    /// @dev    Executes the withdrawal for a given amount, does the actual value transfer from the contract to user's
    ///         wallet. The only function in the contract that sends value and has re-entrancy risk. Does not check if
    ///         the address is payable, as the Address library reverts if it is not. Emits `Withdrawal`.
    /// @param  recipient  The address to send the value to.
    /// @param  amount     The value in wei to withdraw from the contract.
    function _withdraw(uint256 orbId, address recipient, uint256 amount) internal virtual {
        if (recipient == keeper[orbId]) {
            _settle(orbId);
        }

        if (fundsOf[orbId][recipient] < amount) {
            revert InsufficientFunds(fundsOf[orbId][recipient], amount);
        }

        fundsOf[orbId][recipient] -= amount;

        emit Withdrawal(orbId, recipient, amount);

        Address.sendValue(payable(recipient), amount);
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
    /// @param   newPrice  New price for the Orb.
    function setPrice(uint256 orbId, uint256 newPrice) external virtual onlyKeeper(orbId) onlyKeeperSolvent(orbId) {
        _settle(orbId);
        _setPrice(orbId, newPrice);
    }

    /// @notice  Lists the Orb for sale at the given price to buy directly from the Orb creator. This is an alternative
    ///          to the auction mechanism, and can be used to simply have the Orb for sale at a fixed price, waiting
    ///          for the buyer. Listing is only allowed if the auction has not been started and the Orb is held by the
    ///          contract. When the Orb is purchased from the creator, all proceeds go to the beneficiary and the Orb
    ///          comes fully charged, with no cooldown.
    /// @dev     Emits `Transfer` and `PriceUpdate`.
    /// @param   listingPrice  The price to buy the Orb from the creator.
    function listWithPrice(uint256 orbId, uint256 listingPrice) external virtual onlyCreator(orbId) {
        if (address(this) != keeper[orbId]) {
            revert ContractDoesNotHoldOrb();
        }

        if (IKeeperDiscovery(keeperDiscoveryContract[orbId]).discoveryActive(orbId)) {
            revert DiscoveryActive();
        }

        keeper[orbId] = _msgSender();
        _setPrice(orbId, listingPrice);
    }

    /// @notice  Purchasing is the mechanism to take over the Orb. With Harberger tax, the Orb can always be purchased
    ///          from its keeper. Purchasing is only allowed while the keeper is solvent. If not, the Orb has to be
    ///          foreclosed and re-auctioned. This function does not require the purchaser to have more funds than
    ///          required, but purchasing without any reserve would leave the new owner immediately foreclosable.
    ///          Beneficiary receives either just the royalty, or full price if the Orb is purchased from the creator.
    /// @dev     Requires to provide key Orb parameters (current price, Harberger tax rate, royalty, cooldown and
    ///          cleartext maximum length) to prevent front-running: without these parameters Orb creator could
    ///          front-run purcaser and change Orb parameters before the purchase; and without current price anyone
    ///          could purchase the Orb ahead of the purchaser, set the price higher, and profit from the purchase.
    ///          Does not modify `lastInvocationTime` unless buying from the creator.
    ///          Does not allow settlement in the same block before `purchase()` to prevent transfers that avoid
    ///          royalty payments. Does not allow purchasing from yourself. Emits `PriceUpdate` and `Purchase`.
    ///          V2 changes to require providing Keeper auction royalty to prevent front-running.
    /// @param   newPrice                          New price to use after the purchase.
    /// @param   currentPrice                      Current price, to prevent front-running.
    /// @param   currentKeeperTaxNumerator         Current keeper tax numerator, to prevent front-running.
    /// @param   currentPurchaseRoyaltyNumerator   Current royalty numerator, to prevent front-running.
    /// @param   currentDiscoveryRoyaltyNumerator  Current keeper auction royalty numerator, to prevent front-running.
    /// @param   currentCooldown                   Current cooldown, to prevent front-running.
    /// @param   currentLockedUntil                Current honored until timestamp, to prevent front-running.
    function purchase(
        uint256 orbId,
        uint256 newPrice,
        uint256 currentPrice,
        uint256 currentKeeperTaxNumerator,
        uint256 currentPurchaseRoyaltyNumerator,
        uint256 currentDiscoveryRoyaltyNumerator,
        uint256 currentCooldown,
        uint256 currentLockedUntil
    ) external payable virtual onlyKeeperHeld(orbId) onlyKeeperSolvent(orbId) {
        if (currentPrice != price[orbId]) {
            revert CurrentValueIncorrect(currentPrice, price[orbId]);
        }
        if (currentKeeperTaxNumerator != keeperTaxNumerator[orbId]) {
            revert CurrentValueIncorrect(currentKeeperTaxNumerator, keeperTaxNumerator[orbId]);
        }
        if (currentPurchaseRoyaltyNumerator != purchaseRoyaltyNumerator[orbId]) {
            revert CurrentValueIncorrect(currentPurchaseRoyaltyNumerator, purchaseRoyaltyNumerator[orbId]);
        }
        if (currentDiscoveryRoyaltyNumerator != discoveryRoyaltyNumerator[orbId]) {
            revert CurrentValueIncorrect(currentDiscoveryRoyaltyNumerator, discoveryRoyaltyNumerator[orbId]);
        }
        if (currentCooldown != OrbInvocationRegistry(registry).cooldown(orbId)) {
            revert CurrentValueIncorrect(currentCooldown, OrbInvocationRegistry(registry).cooldown(orbId));
        }
        if (currentLockedUntil != OrbTokenLocker(tokenLocker).lockedUntil(orbId)) {
            revert CurrentValueIncorrect(currentLockedUntil, OrbTokenLocker(tokenLocker).lockedUntil(orbId));
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

        if (totalFunds < currentPrice) {
            revert InsufficientFunds(totalFunds, currentPrice);
        }

        fundsOf[orbId][_msgSender()] -= currentPrice;
        if (creator[orbId] == _keeper) {
            OrbInvocationRegistry(registry).chargeOrb(orbId);
            earnings[orbId] += currentPrice;
        } else {
            _splitProceeds(orbId, currentPrice, _keeper, purchaseRoyaltyNumerator[orbId]);
        }

        _setPrice(orbId, newPrice);

        emit Purchase(orbId, _keeper, _msgSender(), currentPrice);

        keeper[orbId] = _msgSender();
    }

    /// @notice  Allows the Orb creator to recall the Orb from the Keeper, if the Oath is no longer honored. This is an
    ///          alternative to just extending the Oath or swearing it while held by Keeper. It benefits the Orb creator
    ///          as they can set a new Oath and run a new auction. This acts as an alternative to just abandoning the
    ///          Orb after Oath expires.
    /// @dev     Emits `Recall`. Does not transfer remaining funds to the Keeper to allow recalling even if the Keeper
    ///          is a smart contract rejecting ether transfers.
    function recall(uint256 orbId) external virtual onlyCreator(orbId) {
        address _keeper = keeper[orbId];
        if (address(this) == _keeper || creator[orbId] == _keeper) {
            revert KeeperDoesNotHoldOrb();
        }
        // if (lockedUntil >= block.timestamp) {
        //     revert OathStillHonored();
        // } TODO
        // Auction cannot be running while held by Keeper, no check needed

        _settle(orbId);

        price[orbId] = 0;
        emit Recall(orbId, _keeper);

        keeper[orbId] = address(this);
    }

    /// @dev    Assigns proceeds to beneficiary and primary receiver, accounting for royalty. Used by `purchase()` and
    ///         `finalizeAuction()`. Fund deducation should happen before calling this function. Receiver might be
    ///         beneficiary if no split is needed.
    /// @param  proceeds  Total proceeds to split between beneficiary and receiver.
    /// @param  receiver  Address of the receiver of the proceeds minus royalty.
    /// @param  royalty   Beneficiary royalty numerator to use for the split.
    function _splitProceeds(uint256 orbId, uint256 proceeds, address receiver, uint256 royalty) internal virtual {
        uint256 royaltyShare = (proceeds * royalty) / _FEE_DENOMINATOR;
        uint256 receiverShare = proceeds - royaltyShare;
        earnings[orbId] += royaltyShare;
        fundsOf[orbId][receiver] += receiverShare;
    }

    /// @dev    Does not check if the new price differs from the previous price: no risk. Limits the price to
    ///         MAXIMUM_PRICE to prevent potential overflows in math. Emits `PriceUpdate`.
    /// @param  newPrice  New price for the Orb.
    function _setPrice(uint256 orbId, uint256 newPrice) internal virtual {
        if (newPrice > _MAXIMUM_PRICE) {
            revert InvalidNewPrice(newPrice);
        }

        uint256 previousPrice = price[orbId];
        price[orbId] = newPrice;

        emit PriceUpdate(orbId, keeper[orbId], previousPrice, newPrice);
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

        if (
            creator[orbId] != _msgSender() && IKeeperDiscovery(keeperDiscoveryContract[orbId]).rediscoveryEnabled(orbId)
        ) {
            discoveryBeneficiary[orbId] = _msgSender();
            IKeeperDiscovery(keeperDiscoveryContract[orbId]).startDiscovery(orbId, true);
            // TODO somehow communicate that its Keeper auction
            // initialDiscovery and rediscovery

            emit DiscoveryStart(orbId, discoveryBeneficiary[orbId], block.timestamp);
        }

        keeper[orbId] = address(this);
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

        if (IKeeperDiscovery(keeperDiscoveryContract[orbId]).rediscoveryEnabled(orbId)) {
            discoveryBeneficiary[orbId] = _keeper;
            IKeeperDiscovery(keeperDiscoveryContract[orbId]).startDiscovery(orbId, true);
            // TODO somehow communicate that its Keeper auction
            // initialDiscovery and rediscovery

            emit DiscoveryStart(orbId, discoveryBeneficiary[orbId], block.timestamp);
        }

        keeper[orbId] = address(this);
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
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}

// TODOs:
// - everything about token locking
// - indicate if discovery is initial or rediscovery
// - discovery running check
// - admin, upgrade functions
// - expose is creator controlled logic
// - establish is deadline missed logic
// - documentation
//   - first, for myself: to understand when all actions can be taken
//   - particularly token and settings related
