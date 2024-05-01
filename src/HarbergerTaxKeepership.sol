// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {OrbSystem} from "./OrbSystem.sol";
import {OwnershipRegistry} from "./OwnershipRegistry.sol";
import {InvocationRegistry} from "./InvocationRegistry.sol";

import {Earnable} from "./Earnable.sol";

struct PurchaseOrder {
    uint256 index; // starts from 0, so shouldn't be used to check if the order exists
    address purchaser;
    uint256 price; // price if finalized
    uint256 timestamp; // when the order was placed
}

/// @title   Harberger Tax Keepership
/// @author  Jonas Lekevicius
/// @custom:security-contact security@orb.land
contract HarbergerTaxKeepership is Earnable, OwnableUpgradeable, UUPSUpgradeable {
    // Funding Events
    event Deposit(uint256 indexed orbId, address indexed depositor, uint256 amount);
    event Withdrawal(uint256 indexed orbId, address indexed recipient, uint256 amount);
    event Settlement(uint256 indexed orbId, address indexed keeper, uint256 amount);

    event Purchase(uint256 indexed orbId, address indexed seller, address indexed buyer, uint256 price);
    event PurchaseOrderPlacement(uint256 indexed orbId, address indexed purchaser, uint256 price);
    event PurchaseFinalization(uint256 indexed orbId, address indexed seller, address indexed buyer, uint256 price);
    event PurchaseCancellation(uint256 indexed orbId);

    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);
    // Purchasing Errors
    error CurrentValueIncorrect(uint256 valueProvided, uint256 currentValue);
    error PurchasingNotPermitted();
    error AlreadyKeeper();
    error AlreadyLastPurchaser();
    error NoPurchaseOrder();
    error PurchaseOrderExpired();
    error OrbInvokable();
    error InsufficientKeeperFunds();
    error OrbNotInvokable();
    error NotPermitted();
    error NotKeeper();
    error KeeperInsolvent();
    error OrbDoesNotExist();
    error ContractHoldsOrb();

    /// Orb version. Value: 1.
    uint256 private constant _VERSION = 1;
    /// Harberger tax period: for how long the tax rate applies. Value: 1 year.
    uint256 internal constant _KEEPER_TAX_PERIOD = 365 days;
    /// Next purchase order price multiplier. Value: 1.2x of the previous price.
    uint256 internal constant _NEXT_PURCHASE_PRICE_MULTIPLIER = 120_00;

    OrbSystem public os;
    OwnershipRegistry public ownershipRegistry;

    // Funds Variables

    /// Funds tracker, per Orb and per address. Modified by deposits, withdrawals and settlements.
    /// The value is without settlement.
    /// It means effective user funds (withdrawable) would be different for keeper (subtracting
    /// `_owedSinceLastSettlement()`) and beneficiary (adding `_owedSinceLastSettlement()`). If Orb is held by the
    /// creator, funds are not subtracted, as Harberger tax does not apply to the creator.
    mapping(uint256 orbId => mapping(address => uint256)) public fundsOf;

    /// Last time Orb keeper's funds were settled. Used to calculate amount owed since last settlement. Has no meaning
    /// if the Orb is held by the contract.
    mapping(uint256 orbId => uint256) public lastSettlementTime;

    mapping(uint256 orbId => PurchaseOrder) public purchaseOrder;

    modifier onlyOwnershipContract() {
        if (_msgSender() != address(ownershipRegistry)) {
            revert NotPermitted();
        }
        _;
    }

    /// @dev  Ensures that the caller owns the Orb. Should only be used in conjuction with `onlyKeeperHeld` or on
    ///       external functions, otherwise does not make sense.
    modifier onlyKeeper(uint256 orbId) virtual {
        if (_msgSender() != ownershipRegistry.keeper(orbId)) {
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
        if (address(0) == ownershipRegistry.keeper(orbId)) {
            revert OrbDoesNotExist();
        }
        if (address(this) == ownershipRegistry.keeper(orbId)) {
            revert ContractHoldsOrb();
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
    //  FUNCTIONS: FUNDS AND HOLDING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Allows depositing funds on the contract. Not allowed for insolvent keepers.
    /// @dev     Deposits are not allowed for insolvent keepers to prevent cheating via front-running. If the user
    ///          becomes insolvent, the Orb will always be returned to the contract as the next step. Emits `Deposit`.
    function deposit(uint256 orbId) external payable virtual {
        if (_msgSender() == ownershipRegistry.keeper(orbId) && !_keeperSolvent(orbId)) {
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
        if (_msgSender() == ownershipRegistry.keeper(orbId)) {
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
        if (_msgSender() == ownershipRegistry.keeper(orbId)) {
            if (purchaseOrder[orbId].purchaser != address(0)) {
                revert NotPermitted();
            }
            _settle(orbId);
        }
        _withdraw(orbId, _msgSender(), fundsOf[orbId][_msgSender()]);
    }

    function withdrawAllFor(uint256 orbId, address recipient) external virtual onlyOwnershipContract {
        _withdraw(orbId, recipient, fundsOf[orbId][recipient]);
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

    function hasPurchaseOrder(uint256 orbId) external view virtual returns (bool) {
        return purchaseOrder[orbId].purchaser != address(0);
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
    function _keeperSolvent(uint256 orbId) internal view virtual returns (bool) {
        if (ownershipRegistry.creator(orbId) == ownershipRegistry.keeper(orbId)) {
            return true;
        }
        return fundsOf[orbId][ownershipRegistry.keeper(orbId)] >= _owedSinceLastSettlement(orbId);
    }

    function keeperSolvent(uint256 orbId) external view virtual returns (bool isKeeperSolvent) {
        return _keeperSolvent(orbId);
    }

    function _foreclosureTimestamp(uint256 orbId) internal view virtual returns (uint256) {
        if (
            ownershipRegistry.creator(orbId) == ownershipRegistry.keeper(orbId)
                || ownershipRegistry.keeper(orbId) == address(this) || ownershipRegistry.price(orbId) == 0
                || ownershipRegistry.keeperTax(orbId) == 0
        ) {
            return type(uint256).max;
        }
        uint256 owedFunds = _owedSinceLastSettlement(orbId);
        uint256 availableFunds = fundsOf[orbId][ownershipRegistry.keeper(orbId)];
        uint256 effectiveFunds = availableFunds <= owedFunds ? 0 : availableFunds - owedFunds;
        return effectiveFunds * _KEEPER_TAX_PERIOD * os.feeDenominator()
            / (ownershipRegistry.price(orbId) * ownershipRegistry.keeperTax(orbId));
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
        return (ownershipRegistry.price(orbId) * ownershipRegistry.keeperTax(orbId) * secondsSinceLastSettlement)
            / (_KEEPER_TAX_PERIOD * os.feeDenominator());
    }

    /// @dev  Keeper might owe more than they have funds available: it means that the keeper is foreclosable.
    ///       Settlement would transfer all keeper funds to the beneficiary, but not more. Does not transfer funds if
    ///       the creator holds the Orb, but always updates `lastSettlementTime`. Should never be called if Orb is
    ///       owned by the contract. Emits `Settlement`.
    function _settle(uint256 orbId) internal virtual {
        address _keeper = ownershipRegistry.keeper(orbId);
        address _creator = ownershipRegistry.creator(orbId);

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

        address _keeper = ownershipRegistry.keeper(orbId);
        address _creator = ownershipRegistry.creator(orbId);
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
            uint256 royaltyShare = (_keeperEarnings * ownershipRegistry.purchaseRoyalty(orbId)) / os.feeDenominator();
            _addEarnings(_creator, royaltyShare);
            _addEarnings(_keeper, _keeperEarnings - royaltyShare);
        }

        _setPrice(orbId, newPrice_);

        emit Purchase(orbId, _keeper, _msgSender(), _currentPrice);

        ownershipRegistry.setKeeper(orbId, _msgSender());
    }

    function _setPrice(uint256 orbId, uint256 newPrice_) internal virtual {
        ownershipRegistry.setPriceInternal(orbId, newPrice_);
    }

    function _nextPurchaseOrderPrice(uint256 orbId) internal view virtual returns (uint256) {
        if (purchaseOrder[orbId].purchaser != address(0)) {
            return ownershipRegistry.price(orbId)
                * (_NEXT_PURCHASE_PRICE_MULTIPLIER ** (purchaseOrder[orbId].index + 1)) / os.feeDenominator();
        }
        return ownershipRegistry.price(orbId);
    }

    function _lastPurchaseOrderPrice(uint256 orbId) internal view virtual returns (uint256) {
        if (purchaseOrder[orbId].purchaser != address(0)) {
            // uses index before updating during purchase order
            return ownershipRegistry.price(orbId) * (_NEXT_PURCHASE_PRICE_MULTIPLIER ** purchaseOrder[orbId].index)
                / os.feeDenominator();
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
        emit PurchaseOrderPlacement(orbId, _msgSender(), _purchasePrice);
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

        address _keeper = ownershipRegistry.keeper(orbId);
        address _creator = ownershipRegistry.creator(orbId);

        // might be 0 if there isn't a purchase order:
        uint256 _purchaseFunds = _purchaseOrderFunds(orbId);
        address _lastPurchaser = purchaseOrder[orbId].purchaser;

        if (_creator == _keeper) {
            os.invocations().initializeOrbInvocationPeriod(orbId);
            _addEarnings(_creator, _purchaseFunds);
        } else {
            uint256 royaltyShare = (_purchaseFunds * ownershipRegistry.purchaseRoyalty(orbId)) / os.feeDenominator();
            _addEarnings(_creator, royaltyShare);
            _addEarnings(_keeper, _purchaseFunds - royaltyShare);
        }

        _setPrice(orbId, purchaseOrder[orbId].price);
        _resetPurchaseOrder(orbId);
        ownershipRegistry.setKeeper(orbId, _lastPurchaser);

        emit PurchaseFinalization(orbId, _keeper, _lastPurchaser, _purchaseFunds);
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

        return ownershipRegistry.price(orbId) * (_NEXT_PURCHASE_PRICE_MULTIPLIER ** purchaseFundsIndex)
            / os.feeDenominator();
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

        emit PurchaseCancellation(orbId);
    }

    function assignFunds(uint256 orbId, address to) external payable virtual onlyOwnershipContract {
        fundsOf[orbId][to] += msg.value;
    }

    function resetSettlementTime(uint256 orbId) external virtual onlyOwnershipContract {
        lastSettlementTime[orbId] = block.timestamp;
    }

    function transferFunds(uint256 orbId, address from, address to) external virtual onlyOwnershipContract {
        uint256 keeperFunds = fundsOf[orbId][from];
        fundsOf[orbId][from] = 0;
        fundsOf[orbId][to] += keeperFunds;
    }

    function _resetPurchaseOrder(uint256 orbId) internal virtual {
        purchaseOrder[orbId] = PurchaseOrder(0, address(0), 0, 0);
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
