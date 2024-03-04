// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Orbs} from "./Orbs.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {ContractAuthorizationRegistry} from "./ContractAuthorizationRegistry.sol";

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
    event CleartextRevealing(uint256 indexed orbId, uint256 indexed invocationId, string cleartext);

    event InvocationPeriodUpdate(uint256 indexed orbId, uint256 previousInvocationPeriod, uint256 newInvocationPeriod);
    event ContractAuthorization(address indexed contractAddress, bool indexed authorized);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Authorization Errors
    error NotKeeper();
    error NotCreator();
    error NotOrbsContract();
    error ContractHoldsOrb();
    error KeeperInsolvent();
    error CreatorDoesNotControlOrb();
    error ContractNotAuthorized(address externalContract);
    error InvocationPeriodExceedsMaximumDuration(uint256 invocationPeriod, uint256 invocationPeriodMaximumDuration);

    // Invoking and Responding Errors
    error InvocationPeriodIncomplete(uint256 timeRemaining);
    error NoUnrespondedInvocations(uint256 orbId);
    error ResponseNotFound(uint256 orbId, uint256 invocationId);
    error ResponseExists(uint256 orbId, uint256 invocationId);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Invocation Registry version. Value: 1.
    uint256 private constant _VERSION = 1;
    /// Maximum invocationPeriod duration, to prevent potential underflows. Value: 10 years.
    uint256 internal constant _INVOCATION_PERIOD_MAXIMUM_DURATION = 3650 days;

    address public orbsContract;

    address public authorizationsContract;

    /// Count of invocations made: used to calculate invocationId of the next invocation.
    mapping(uint256 orbId => uint256) public invocationCount;
    /// Mapping for invocations: invocationId to InvocationData struct. InvocationId starts at 1.
    mapping(uint256 orbId => mapping(uint256 invocationId => InvocationData)) public invocations;
    /// Mapping for responses (answers to invocations): matching invocationId to ResponseData struct.
    mapping(uint256 orbId => mapping(uint256 invocationId => ResponseData)) public responses;
    /// Mapping indicating if all invocations have responses
    mapping(uint256 orbId => bool) public hasUnrespondedInvocation;
    /// Mapping of missed deadline invocation IDs
    mapping(uint256 orbId => uint256 invocationId) public expiredPeriodInvocation;

    /// InvocationPeriod: how often the Orb can be invoked.
    /// Response Period: time period in which the keeper promises to respond to an invocation.
    /// There are no penalties for being late within this contract.
    mapping(uint256 orbId => uint256) public invocationPeriod;
    /// Last invocation time: when the Orb was last invoked. Used together with `invocationPeriod` constant.
    mapping(uint256 orbId => uint256) public lastInvocationTime;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev  Initializes the contract.
    function initialize(address authorizationsContract_) public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();

        authorizationsContract = authorizationsContract_;
    }

    function isInvokable(uint256 orbId) public view virtual returns (bool) {
        // Can't be called by Orbs contract
        if (Orbs(orbsContract).keeper(orbId) == orbsContract) {
            return false; // TODO we can disable this check
        }

        // TODO check that there is not an outstanding invocation delegation

        // Can't be invoked if there is an unresponded invocation --
        // if invocation period has passed and there is no response, Pledge is claimable!
        if (hasUnrespondedInvocation[orbId]) {
            return false;
        }

        // Invocation period must have passed
        return block.timestamp >= lastInvocationTime[orbId] + invocationPeriod[orbId];
    }

    function hasExpiredPeriodInvocation(uint256 orbId) public view virtual returns (bool) {
        if (expiredPeriodInvocation[orbId] != 0) {
            return true;
        }
        if (hasUnrespondedInvocation[orbId]) {
            uint256 _lastInvocationId = invocationCount[orbId];
            InvocationData memory _lastInvocation = invocations[orbId][_lastInvocationId];
            if (block.timestamp > _lastInvocation.timestamp + invocationPeriod[orbId]) {
                return true;
            }
        }
        // would be set to invocationId when responding, don't need to check last invocation if every invocation is
        // responded
        return false;
    }

    function checkExpiredPeriodInvocation(uint256 orbId) public virtual {
        if (expiredPeriodInvocation[orbId] == 0 && hasExpiredPeriodInvocation(orbId)) {
            // TODO only if keeper held?
            uint256 _lastInvocationId = invocationCount[orbId];
            expiredPeriodInvocation[orbId] = _lastInvocationId;
            // Settle to apply Harberger tax discount, and reset for potential discounts in the future
            Orbs(orbsContract).settle(orbId);
        }
    }

    function resetExpiredPeriodInvocation(uint256 orbId) public virtual onlyOrbsContract {
        expiredPeriodInvocation[orbId] = 0;
    }

    // ;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  MODIFIERS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev    Ensures that the caller owns the Orb. Should only be used in conjuction with `onlyKeeperHeld` or on
    ///         external functions, otherwise does not make sense.
    /// @param  orbId  Address of the Orb.
    modifier onlyKeeper(uint256 orbId) virtual {
        if (_msgSender() != Orbs(orbsContract).keeper(orbId)) {
            revert NotKeeper();
        }
        _;
    }

    /// @dev    Ensures that the Orb belongs to someone, not the contract itself.
    /// @param  orbId  Address of the Orb.
    modifier onlyKeeperHeld(uint256 orbId) virtual {
        if (orbsContract == Orbs(orbsContract).keeper(orbId)) {
            revert ContractHoldsOrb();
        }
        _;
    }

    /// @dev    Ensures that the current Orb keeper has enough funds to cover Harberger tax until now.
    /// @param  orbId  Orb id
    modifier onlyKeeperSolvent(uint256 orbId) virtual {
        if (!Orbs(orbsContract).keeperSolvent(orbId)) {
            revert KeeperInsolvent();
        }
        _;
    }

    /// @dev    Ensures that the caller is the creator of the Orb.
    /// @param  orbId  Address of the Orb.
    modifier onlyCreator(uint256 orbId) virtual {
        if (_msgSender() != Orbs(orbsContract).creator(orbId)) {
            revert NotCreator();
        }
        _;
    }

    modifier onlyOrbsContract() {
        if (_msgSender() != orbsContract) {
            revert NotOrbsContract();
        }
        _;
    }

    modifier onlyCreatorControlled(uint256 orbId) {
        if (Orbs(orbsContract).keeper(orbId) != address(0)) {
            revert CreatorDoesNotControlOrb();
        }
        // TODO
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOKING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function initializeOrb(uint256 orbId) public onlyOrbsContract {
        invocationPeriod[orbId] = 7 days;
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
    function setInvocationPeriod(uint256 orbId, uint256 invocationPeriod_)
        external
        virtual
        onlyCreator(orbId)
        onlyCreatorControlled(orbId)
    {
        // TODO updating response period settles first, as it’s used there

        if (invocationPeriod_ > _INVOCATION_PERIOD_MAXIMUM_DURATION) {
            revert InvocationPeriodExceedsMaximumDuration(invocationPeriod_, _INVOCATION_PERIOD_MAXIMUM_DURATION);
        }

        uint256 previousInvocationPeriod = invocationPeriod[orbId];
        invocationPeriod[orbId] = invocationPeriod_;
        emit InvocationPeriodUpdate(orbId, previousInvocationPeriod, invocationPeriod_);
    }

    function initializeOrbInvocationPeriod(uint256 orbId) external virtual onlyOrbsContract {
        if (lastInvocationTime[orbId] == 0) {
            lastInvocationTime[orbId] = block.timestamp - invocationPeriod[orbId];
        }
    }

    /// @notice  Invokes the Orb. Allows the keeper to submit content hash, that represents a question to the Orb
    ///          creator. Puts the Orb on invocationPeriod. The Orb can only be invoked by solvent keepers.
    /// @dev     Content hash is keccak256 of the cleartext. `invocationCount` is used to track the id of the next
    ///          invocation. Invocation ids start from 1. Emits `Invocation`.
    /// @param   orbId        Address of the Orb.
    /// @param   contentHash  Required keccak256 hash of the cleartext.
    function invokeWithHash(uint256 orbId, bytes32 contentHash)
        public
        virtual
        onlyKeeper(orbId)
        onlyKeeperHeld(orbId)
        onlyKeeperSolvent(orbId)
    {
        uint256 _lastInvocationTime = lastInvocationTime[orbId];
        uint256 _invocationPeriod = invocationPeriod[orbId];

        // TODO Repalce with isInvokable
        if (block.timestamp < _lastInvocationTime + _invocationPeriod) {
            revert InvocationPeriodIncomplete(_lastInvocationTime + _invocationPeriod - block.timestamp);
        }

        invocationCount[orbId] += 1;
        uint256 invocationId = invocationCount[orbId]; // starts at 1

        invocations[orbId][invocationId] = InvocationData(_msgSender(), contentHash, block.timestamp);
        lastInvocationTime[orbId] = block.timestamp;

        emit Invocation(orbId, invocationId, _msgSender(), block.timestamp, contentHash);
    }

    /// @notice  Invokes the Orb with content hash and calls an external contract.
    /// @dev     Calls `invokeWithHash()` and then calls the external contract.
    /// @param   orbId          Id of the Orb.
    /// @param   contentHash    Required keccak256 hash of the cleartext.
    /// @param   addressToCall  Address of the contract to call.
    /// @param   dataToCall     Data to call the contract with.
    function invokeWithHashAndCall(uint256 orbId, bytes32 contentHash, address addressToCall, bytes memory dataToCall)
        external
        virtual
    {
        invokeWithHash(orbId, contentHash);
        _callWithData(addressToCall, dataToCall);
    }

    /// @dev    Internal function that calls an external contract. The contract has to be approved via
    ///         `authorizeCalls()`.
    /// @param  addressToCall  Address of the contract to call.
    /// @param  dataToCall     Data to call the contract with.
    function _callWithData(address addressToCall, bytes memory dataToCall) internal virtual {
        if (ContractAuthorizationRegistry(authorizationsContract).invocationCallableContracts(addressToCall) == false) {
            revert ContractNotAuthorized(addressToCall);
        }
        Address.functionCall(addressToCall, dataToCall);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: RESPONDING AND FLAGGING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  The Orb creator can use this function to respond to any existing invocation, no matter how long ago
    ///          it was made. A response to an invocation can only be written once. There is no way to record response
    ///          cleartext on-chain.
    /// @dev     Emits `Response`.
    /// @param   orbId         Id of the Orb.
    /// @param   contentHash   keccak256 hash of the response text.
    function respond(uint256 orbId, bytes32 contentHash) external virtual onlyCreator(orbId) {
        // There can only be one invocation without a response
        uint256 invocationId = invocationCount[orbId];

        if (hasUnrespondedInvocation[orbId] == false) {
            revert NoUnrespondedInvocations(orbId);
        }
        if (_responseExists(orbId, invocationId)) {
            revert ResponseExists(orbId, invocationId);
        }

        responses[orbId][invocationId] = ResponseData(contentHash, block.timestamp);

        InvocationData memory _lastInvocation = invocations[orbId][invocationId];
        // TODO maybe only if not already marked
        // And only if keeper held
        if (block.timestamp > _lastInvocation.timestamp + invocationPeriod[orbId]) {
            expiredPeriodInvocation[orbId] = invocationId;
            // Settle to apply Harberger tax discount, and reset for potential discounts in the future
            Orbs(orbsContract).settle(orbId);
        }

        emit Response(orbId, invocationId, _msgSender(), block.timestamp, contentHash);
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
        if (responses[orbId][invocationId_].timestamp != 0) {
            return true;
        }
        return false;
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
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
