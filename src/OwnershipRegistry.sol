// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import {OrbSystem} from "./OrbSystem.sol";
import {HarbergerTaxKeepership} from "./HarbergerTaxKeepership.sol";
import {InvocationRegistry} from "./InvocationRegistry.sol";
import {IAllocationMethod} from "./allocation/IAllocationMethod.sol";

/// @title   Orb Ownership Registry
/// @author  Jonas Lekevicius
/// @author  Eric Wall
/// @custom:security-contact security@orb.land
contract OwnershipRegistry is OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event Creation(uint256 indexed orbId, address indexed creator);

    // Purchasing Events
    event PriceUpdate(uint256 indexed orbId, address indexed keeper, uint256 newPrice);

    // Orb Ownership Events
    event Foreclosure(uint256 indexed orbId, address indexed formerKeeper);
    event Relinquishment(uint256 indexed orbId, address indexed formerKeeper);
    event Recall(uint256 indexed orbId, address indexed formerKeeper);
    event OrbTransfer(uint256 indexed orbId, address indexed formerKeeper, address indexed newKeeper);

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
    error AddressUnauthorized(address unauthorizedAddress);
    error NotAllocationContract();
    error Unauthorized();
    error OrbDoesNotExist();
    error AddressInvalid(address invalidAddress);
    error NotPermitted();

    // Allocation Errors
    error AllocationActive();

    // Funding Errors
    error KeeperSolvent();
    error KeeperInsolvent();
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);

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
    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;
    uint256 internal constant _FEE_DENOMINATOR = 100_00;

    // STATE

    OrbSystem public orbSystem;
    HarbergerTaxKeepership public keepership;
    InvocationRegistry public invocations;

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
        if (keepership.keeperSolvent(orbId) == false) {
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
        if (orbSystem.isCreatorControlled(orbId) == false) {
            revert CreatorDoesNotControlOrb();
        }
        _;
    }

    modifier onlyKeepership() virtual {
        if (_msgSender() != orbSystem.harbergerTaxKeepershipAddress()) {
            revert NotPermitted();
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

        orbSystem = OrbSystem(os_);
    }

    function setSystemContracts() external {
        keepership = HarbergerTaxKeepership(orbSystem.harbergerTaxKeepershipAddress());
        invocations = InvocationRegistry(orbSystem.invocationRegistryAddress());
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
        if (signingAddress != orbSystem.platformSignerAddress()) {
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
        invocations.initializeOrb(orbId);
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
            keepership.settle(orbId);
        }
        if (purchaseRoyalty_ > _FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(purchaseRoyalty_, _FEE_DENOMINATOR);
        }
        if (reallocationRoyalty_ > _FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(reallocationRoyalty_, _FEE_DENOMINATOR);
        }

        uint256 maximumKeeperTax = invocations.maximumKeeperTax(orbId);
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
        if (orbSystem.allocationContractAuthorized(allocationContract_) == false) {
            revert AddressUnauthorized(allocationContract_);
        }
        if (
            reallocationContract_ != address(0)
                && orbSystem.allocationContractAuthorized(reallocationContract_) == false
        ) {
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
            keepership.assignFunds{value: recipientFunds_}(orbId, recipient_);
            keepership.resetSettlementTime(orbId);

            if (allocationBeneficiary[orbId] == creator[orbId]) {
                invocations.initializeOrbInvocationPeriod(orbId);
            }

            uint256 effectiveInitialPrice = initialPrice_ > minimumPrice[orbId] ? initialPrice_ : minimumPrice[orbId];
            _setPrice(orbId, effectiveInitialPrice);

            keeper[orbId] = recipient_;
        }
    }

    /// @notice  Sets the new purchase price for the Orb. Harberger tax means the asset is always for sale. The price
    ///          can be set to zero, making foreclosure time to be never. Can only be called by a solvent keeper.
    ///          Settles before adjusting the price, as the new price will change foreclosure time.
    /// @dev     Emits `Settlement` and `PriceUpdate`. See also `_setPrice()`.
    /// @param   newPrice_  New price for the Orb.
    function setPrice(uint256 orbId, uint256 newPrice_) external virtual onlyKeeper(orbId) {
        if (keepership.hasPurchaseOrder(orbId)) {
            revert NotPermitted();
        }
        keepership.settle(orbId);
        _setPrice(orbId, newPrice_);
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

    function setPriceInternal(uint256 orbId, uint256 price_) external virtual onlyKeepership {
        _setPrice(orbId, price_);
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

        keepership.settle(orbId);

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
        if (keepership.hasPurchaseOrder(orbId)) {
            revert NotPermitted();
        }
        keepership.settle(orbId);

        price[orbId] = 0;
        keeper[orbId] = address(this);

        emit Relinquishment(orbId, _msgSender());

        address reallocation = reallocationContract[orbId];

        if (creator[orbId] != _msgSender() && reallocation != address(0)) {
            allocationBeneficiary[orbId] = _msgSender();
            IAllocationMethod(reallocation).start(orbId);
        }

        keepership.withdrawAllFor(orbId, _msgSender()); // TODO test that it works, might need to force it
    }

    function setKeeper(uint256 orbId, address newKeeper_) external virtual onlyKeepership {
        keeper[orbId] = newKeeper_;
    }

    /// @notice  Foreclose can be called by anyone after the Orb keeper runs out of funds to cover the Harberger tax.
    ///          It returns the Orb to the contract and starts a auction to find the next keeper. Most of the proceeds
    ///          (minus the royalty) go to the previous keeper.
    /// @dev     Emits `Foreclosure`, and optionally `AuctionStart`.
    function foreclose(uint256 orbId) external virtual onlyKeeperHeld(orbId) {
        if (keepership.keeperSolvent(orbId)) {
            revert KeeperSolvent();
        }

        if (keepership.hasPurchaseOrder(orbId)) {
            return keepership.finalizePurchase(orbId);
        }

        keepership.settle(orbId);

        address _keeper = keeper[orbId];
        price[orbId] = 0;
        keeper[orbId] = address(this);

        emit Foreclosure(orbId, _keeper);

        address reallocation = reallocationContract[orbId];

        if (reallocation != address(0)) {
            allocationBeneficiary[orbId] = _keeper;
            IAllocationMethod(reallocation).start(orbId);
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

        keepership.settle(orbId);
        keepership.transferFunds(orbId, _msgSender(), newKeeper_);

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
}
