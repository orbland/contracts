// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {OrbSystem} from "./OrbSystem.sol";
import {OwnershipRegistry} from "./OwnershipRegistry.sol";
import {HarbergerTaxKeepership} from "./HarbergerTaxKeepership.sol";
import {PledgeLocker} from "./PledgeLocker.sol";
import {InvocationTipJar} from "./InvocationTipJar.sol";
import {IDelegationMethod} from "./delegation/IDelegationMethod.sol";

/// Structs used to track invocation and response information: keccak256 content hash and block timestamp.
/// InvocationData is used to determine if the response can be flagged by the keeper.
/// Invocation timestamp and invoker address is tracked for the benefit of other contracts.
struct InvocationData {
    address invoker;
    // keccak256 hash of the cleartext
    bytes32 contentHash;
    uint256 timestamp;
}

struct ResponseData {
    // keccak256 hash of the cleartext
    bytes32 contentHash;
    uint256 timestamp;
}

contract InvocationRegistry is OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event Invocation(
        uint256 indexed orbId,
        uint256 indexed invocationId,
        address indexed invoker,
        uint256 timestamp,
        bytes32 contentHash
    );
    event Response(
        uint256 indexed orbId,
        uint256 indexed invocationId,
        address indexed responder,
        uint256 timestamp,
        bytes32 contentHash
    );

    event InvocationPeriodUpdate(uint256 indexed orbId, uint256 newInvocationPeriod);
    event DelegationContractUpdate(uint256 indexed orbId, address delegationContract);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Authorization Errors
    error NotKeeper();
    error NotCreator();
    error NotAuthorized();
    error NotOwnershipRegistryContract();
    error ContractHoldsOrb();
    error ContractDoesNotHoldOrb();
    error KeeperInsolvent();
    error CreatorDoesNotControlOrb();
    error ContractNotAuthorized(address externalContract);
    error InvocationPeriodExceedsMaximumDuration(uint256 invocationPeriod, uint256 invocationPeriodMaximumDuration);
    error DelegationActive();

    // Invoking and Responding Errors
    error NotInvokable();
    error NoUnrespondedInvocation();
    error HasUnrespondedInvocation();
    error ResponseNotFound(uint256 orbId, uint256 invocationId);
    error ResponseExists(uint256 orbId, uint256 invocationId);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Invocation Registry version. Value: 1.
    uint256 private constant _VERSION = 1;
    /// Maximum invocationPeriod duration, to prevent potential underflows. Value: 10 years.
    uint256 internal constant _INVOCATION_PERIOD_MAXIMUM_DURATION = 3650 days;
    uint256 internal constant _FEE_DENOMINATOR = 100_00;
    uint256 internal constant _KEEPER_TAX_PERIOD = 365 days;

    /// Addresses of all system contracts
    OrbSystem public orbSystem;
    OwnershipRegistry public ownership;
    HarbergerTaxKeepership public keepership;
    PledgeLocker public pledges;
    InvocationTipJar public tips;

    /// Count of invocations made: used to calculate invocationId of the next invocation.
    /// Also, id of the last invocation.
    mapping(uint256 orbId => uint256) public invocationCount;
    /// Mapping for invocations: invocationId to InvocationData struct. InvocationId starts at 1.
    mapping(uint256 orbId => mapping(uint256 invocationId => InvocationData)) public invocations;
    /// Mapping for responses (answers to invocations): matching invocationId to ResponseData struct.
    mapping(uint256 orbId => mapping(uint256 invocationId => ResponseData)) public responses;
    /// Last invocation time: when the Orb was last invoked. Used together with `invocationPeriod` constant.
    mapping(uint256 orbId => uint256) public lastInvocationTime;
    /// Mapping of missed deadline invocation IDs -- currently only used to allow claiming of pledges
    mapping(uint256 orbId => bool) public lastInvocationResponseWasLate;

    /// InvocationPeriod: how often the Orb can be invoked.
    /// Response Period: time period in which the keeper promises to respond to an invocation.
    /// There are no penalties for being late within this contract.
    mapping(uint256 orbId => uint256) public invocationPeriod;

    /// Mapping of delegation contracts for each Orb
    mapping(uint256 orbId => address) public delegationContract;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev  Initializes the contract.
    function initialize(address os_) public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();

        orbSystem = OrbSystem(os_);
    }

    function setSystemContracts() external {
        ownership = OwnershipRegistry(orbSystem.ownershipRegistryAddress());
        keepership = HarbergerTaxKeepership(orbSystem.harbergerTaxKeepershipAddress());
        pledges = PledgeLocker(orbSystem.pledgeLockerAddress());
        tips = InvocationTipJar(orbSystem.invocationTipJarAddress());
    }

    function hasUnrespondedInvocation(uint256 orbId) external view virtual returns (bool) {
        return _hasUnrespondedInvocation(orbId);
    }

    function _hasUnrespondedInvocation(uint256 orbId) internal view virtual returns (bool) {
        return responses[orbId][invocationCount[orbId]].timestamp == 0;
    }

    function _isKeeperInvokable(uint256 orbId) internal view virtual returns (bool) {
        address _delegationContract = delegationContract[orbId];
        if (_delegationContract != address(0) && IDelegationMethod(_delegationContract).isFinalizable(orbId)) {
            return false;
        }

        return _isInvokable(orbId);
    }

    function isInvokable(uint256 orbId) external view virtual returns (bool) {
        return _isInvokable(orbId);
    }

    function _isInvokable(uint256 orbId) internal view virtual returns (bool) {
        // Can't be invoked if there is an unresponded invocation --
        // if invocation period has passed and there is no response, Pledge is claimable!
        if (_hasUnrespondedInvocation(orbId)) {
            return false;
        }

        // Can't be invoked if there is a claimable pledge - claim it before invoking!
        if (pledges.hasClaimablePledge(orbId)) {
            return false;
        }

        address _keeper = ownership.keeper(orbId);
        if (ownership.creator(orbId) == _keeper) {
            return true;
        }
        if (address(ownership) == _keeper) {
            return false;
        }

        if (keepership.keeperSolvent(orbId) == false) {
            return false;
        }

        // Invocation period must have passed
        return block.timestamp >= lastInvocationTime[orbId] + invocationPeriod[orbId];
    }

    function hasLateResponse(uint256 orbId) external view virtual returns (bool) {
        return _hasLateResponse(orbId);
    }

    function _hasLateResponse(uint256 orbId) internal view virtual returns (bool) {
        return (
            (lastInvocationResponseWasLate[orbId])
                || (
                    _hasUnrespondedInvocation(orbId)
                        && block.timestamp > lastInvocationTime[orbId] + invocationPeriod[orbId]
                )
        );
    }

    function maximumKeeperTax(uint256 orbId) external view virtual returns (uint256) {
        if (invocationPeriod[orbId] == 0) {
            return type(uint256).max;
        }
        // 1000 is used to avoid floating point arithmetic
        uint256 invocationsInTaxPeriod = _KEEPER_TAX_PERIOD * 1000 / invocationPeriod[orbId];
        return (invocationsInTaxPeriod * _FEE_DENOMINATOR) / 1000;

        // test for 14 days invocation period:
        // invocationsInTaxPeriod = 31536000 * 1000 / (14 * 86400) = 31536000000 / 1209600 = 26071
        // maximumKeeperTax = 26071 * 100_00 / 1000 = 2607_10 or 2607.10%

        // test for 2 days invocation period:
        // invocationsInTaxPeriod = 31536000 * 1000 / (2 * 86400) = 31536000000 / 172800 = 182500
        // maximumKeeperTax = 182500 * 100_00 / 1000 = 18250_00 or 18250.00%
    }

    function _maximumInvocationPeriod(uint256 orbId) internal virtual returns (uint256) {
        uint256 keeperTax_ = ownership.keeperTax(orbId);
        if (keeperTax_ == 0) {
            return type(uint256).max;
        }
        // 1000 is used to avoid floating point arithmetic
        uint256 buybacksInTaxPeriod = keeperTax_ * 1000 / _FEE_DENOMINATOR;
        return _KEEPER_TAX_PERIOD * 1000 / buybacksInTaxPeriod;

        // buybacksInTaxPeriod for 100% tax  = 100_00  * 1000 / 100_00 = 100_000_00  / 100_00 = 1000.00 or 1
        // buybacksInTaxPeriod for 200% tax  = 200_00  * 1000 / 100_00 = 200_000_00  / 100_00 = 2000.00 or 2
        // buybacksInTaxPeriod for 2400% tax = 2400_00 * 1000 / 100_00 = 2400_000_00 / 100_00 = 24000.00 or 24

        // buybackPeriod for 100% tax  = 31536000 * 1000 / 1000  = 31536000000 / 1000  = 31536000 (1 year)
        // buybackPeriod for 200% tax  = 31536000 * 1000 / 2000  = 31536000000 / 2000  = 15768000 (6 months)
        // buybackPeriod for 2400% tax = 31536000 * 1000 / 24000 = 31536000000 / 24000 = 1314000  (15.2 days)
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  MODIFIERS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev    Ensures that the caller owns the Orb.
    /// @param  orbId  Address of the Orb.
    modifier onlyKeeper(uint256 orbId) virtual {
        if (_msgSender() != ownership.keeper(orbId)) {
            revert NotKeeper();
        }
        _;
    }

    modifier onlyKeeperInvokable(uint256 orbId) virtual {
        if (_isKeeperInvokable(orbId) == false) {
            revert NotInvokable();
        }
        _;
    }

    /// @dev    Ensures that the caller is the creator of the Orb.
    /// @param  orbId  Address of the Orb.
    modifier onlyCreator(uint256 orbId) virtual {
        if (_msgSender() != ownership.creator(orbId)) {
            revert NotCreator();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOKING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function initializeOrb(uint256 orbId) public {
        if (_msgSender() != address(ownership)) {
            revert NotOwnershipRegistryContract();
        }
        invocationPeriod[orbId] = 7 days;
    }

    function setDelegationContract(uint256 orbId, address delegationContract_) external virtual onlyKeeper(orbId) {
        address currentDelegationContract = delegationContract[orbId];
        if (currentDelegationContract != address(0) && IDelegationMethod(currentDelegationContract).isActive(orbId)) {
            revert DelegationActive();
        }

        if (orbSystem.delegationContractAuthorized(delegationContract_) == false) {
            revert ContractNotAuthorized(delegationContract_);
        }

        delegationContract[orbId] = delegationContract_;
        IDelegationMethod(delegationContract_).initializeOrb(orbId);

        emit DelegationContractUpdate(orbId, delegationContract_);
    }

    /// @notice  Allows the Orb creator to set the new invocationPeriod duration, response period, flagging period
    ///          (duration for how long Orb keeper may flag a response) and cleartext maximum length. This function can
    ///          only be called by the Orb creator when the Orb is in their control.
    /// @dev     Emits `InvocationPeriodUpdate`.
    ///          V2 merges `setInvocationPeriod()` and `setCleartextMaximumLength()` into one function, and moves
    ///          `invocationPeriod` setting here. Events `InvocationPeriodUpdate` and `CleartextMaximumLengthUpdate`
    ///          are merged into `InvocationPeriodUpdate`.
    /// @param   invocationPeriod_  New invocationPeriod in seconds. Cannot be longer than
    ///          `_INVOCATION_PERIOD_MAXIMUM_DURATION`.
    function setInvocationPeriod(uint256 orbId, uint256 invocationPeriod_) external virtual onlyCreator(orbId) {
        if (orbSystem.isCreatorControlled(orbId) == false) {
            revert CreatorDoesNotControlOrb();
        }

        if (
            (ownership.keeper(orbId) == address(ownership) || ownership.keeper(orbId) == ownership.creator(orbId))
                && _hasUnrespondedInvocation(orbId)
        ) {
            revert HasUnrespondedInvocation();
        }

        if (invocationPeriod_ > _INVOCATION_PERIOD_MAXIMUM_DURATION) {
            revert InvocationPeriodExceedsMaximumDuration(invocationPeriod_, _INVOCATION_PERIOD_MAXIMUM_DURATION);
        }
        if (invocationPeriod_ > _maximumInvocationPeriod(orbId)) {
            revert InvocationPeriodExceedsMaximumDuration(invocationPeriod_, _maximumInvocationPeriod(orbId));
        }

        // Must settle, so tax pausing is accounted for
        keepership.settle(orbId);

        invocationPeriod[orbId] = invocationPeriod_;
        emit InvocationPeriodUpdate(orbId, invocationPeriod_);
    }

    function initializeOrbInvocationPeriod(uint256 orbId) external virtual {
        if (_msgSender() != address(ownership) && _msgSender() != address(keepership)) {
            revert NotOwnershipRegistryContract();
        }

        if (lastInvocationTime[orbId] == 0) {
            lastInvocationTime[orbId] = block.timestamp - invocationPeriod[orbId];
        }
    }

    /// @notice  Invokes the Orb. Allows the keeper to submit content hash, that represents a question to the Orb
    ///          creator. Puts the Orb on invocationPeriod. The Orb can only be invoked by solvent keepers.
    /// @dev     Content hash is keccak256 of the cleartext. `invocationCount` is used to track the id of the next
    ///          invocation. Invocation ids start from 1. Emits `Invocation`.
    /// @param   orbId         Address of the Orb.
    /// @param   contentHash_  Required keccak256 hash of the cleartext.
    function invoke(uint256 orbId, bytes32 contentHash_)
        external
        virtual
        onlyKeeper(orbId)
        onlyKeeperInvokable(orbId)
    {
        _invoke(orbId, _msgSender(), contentHash_);
    }

    /// @notice  Invokes the Orb with content hash and calls an external contract.
    /// @dev     Calls `invokeWithHash()` and then calls the external contract.
    /// @param   orbId          Id of the Orb.
    /// @param   contentHash_    Required keccak256 hash of the cleartext.
    function invokeAndClaimTips(uint256 orbId, bytes32 contentHash_, uint256 minimumTipTotal_)
        external
        virtual
        onlyKeeper(orbId)
        onlyKeeperInvokable(orbId)
    {
        _invoke(orbId, _msgSender(), contentHash_);
        tips.claim(orbId, invocationCount[orbId], minimumTipTotal_);
    }

    function invokeDelegated(uint256 orbId, address invoker_, bytes32 contentHash_) external virtual {
        if (_msgSender() != delegationContract[orbId]) {
            revert NotAuthorized();
        }

        if (_isInvokable(orbId) == false) {
            revert NotInvokable();
        }

        _invoke(orbId, invoker_, contentHash_);

        if (tips.totalTips(orbId, contentHash_) > 0) {
            tips.claim(orbId, invocationCount[orbId], 0);
        }
    }

    function _invoke(uint256 orbId, address invoker_, bytes32 contentHash_) internal virtual {
        // Keeper shouldn't be able to invoke the Orb if there's a Purchase Order
        (, address purchaser,,) = keepership.purchaseOrder(orbId);
        if (purchaser != address(0)) {
            revert NotInvokable();
        }

        invocationCount[orbId] += 1;
        uint256 invocationId = invocationCount[orbId]; // starts at 1

        invocations[orbId][invocationId] = InvocationData(invoker_, contentHash_, block.timestamp);
        lastInvocationTime[orbId] = block.timestamp;

        // Should never be reached if pledge is claimable, so this is ok:
        if (lastInvocationResponseWasLate[orbId] == true) {
            lastInvocationResponseWasLate[orbId] = false;
        }

        emit Invocation(orbId, invocationId, invoker_, block.timestamp, contentHash_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: RESPONDING AND FLAGGING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  The Orb creator can use this function to respond to any existing invocation, no matter how long ago
    ///          it was made. A response to an invocation can only be written once. There is no way to record response
    ///          cleartext on-chain.
    /// @dev     Emits `Response`.
    /// @param   orbId          Id of the Orb.
    /// @param   contentHash_   keccak256 hash of the response text.
    function respond(uint256 orbId, bytes32 contentHash_) external virtual onlyCreator(orbId) {
        // There can only be one invocation without a response
        uint256 invocationId = invocationCount[orbId];

        if (_responseExists(orbId, invocationId)) {
            revert ResponseExists(orbId, invocationId);
        }

        if (block.timestamp > lastInvocationTime[orbId] + invocationPeriod[orbId]) {
            if (pledges.hasPledge(orbId)) {
                lastInvocationResponseWasLate[orbId] = true;
            }
            if (ownership.keeper(orbId) != address(ownership)) {
                // Settle to apply Harberger tax discount, and reset for potential discounts in the future
                keepership.settle(orbId);
            }
        }

        responses[orbId][invocationId] = ResponseData(contentHash_, block.timestamp);

        emit Response(orbId, invocationId, _msgSender(), block.timestamp, contentHash_);
    }

    /// @dev     Returns if a response to an invocation exists, based on the timestamp of the response being non-zero.
    /// @param   orbId          Id of the Orb.
    /// @param   invocationId_  Id of an invocation to which to check the existence of a response of.
    /// @return  isResponseFound  If a response to an invocation exists or not.
    function _responseExists(uint256 orbId, uint256 invocationId_)
        internal
        view
        virtual
        returns (bool isResponseFound)
    {
        return responses[orbId][invocationId_].timestamp != 0;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: UPGRADING AND MANAGEMENT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Returns the version of the Orb Invocation Registry. Internal constant `_VERSION` will be increased with
    ///          each upgrade.
    /// @return  orbInvocationRegistryVersion  Version of the Orb Invocation Registry contract.
    function version() public view virtual returns (uint256 orbInvocationRegistryVersion) {
        return _VERSION;
    }

    /// @dev  Authorizes owner address to upgrade the contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address) internal virtual override onlyOwner {}
}
