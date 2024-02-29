// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Orbs} from "./Orbs.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

contract OrbInvocationRegistry is OwnableUpgradeable, UUPSUpgradeable {
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

    event InvocationParametersUpdate(
        uint256 previousCooldown,
        uint256 indexed newCooldown,
        uint256 previousResponsePeriod,
        uint256 indexed newResponsePeriod
    );
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
    error ContractNotAuthorized(address externalContract);
    error CooldownExceedsMaximumDuration(uint256 cooldown, uint256 cooldownMaximumDuration);

    // Invoking and Responding Errors
    error CooldownIncomplete(uint256 timeRemaining);
    error InvocationNotFound(uint256 orbId, uint256 invocationId);
    error ResponseNotFound(uint256 orbId, uint256 invocationId);
    error ResponseExists(uint256 orbId, uint256 invocationId);

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

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Invocation Registry version. Value: 1.
    uint256 private constant _VERSION = 1;
    /// Maximum cooldown duration, to prevent potential underflows. Value: 10 years.
    uint256 internal constant _COOLDOWN_MAXIMUM_DURATION = 3650 days;

    address public orbsContract;

    /// Count of invocations made: used to calculate invocationId of the next invocation.
    mapping(uint256 orbId => uint256 count) public invocationCount;
    /// Mapping for invocations: invocationId to InvocationData struct. InvocationId starts at 1.
    mapping(uint256 orbId => mapping(uint256 invocationId => InvocationData invocationData)) public invocations;
    /// Mapping for responses (answers to invocations): matching invocationId to ResponseData struct.
    mapping(uint256 orbId => mapping(uint256 invocationId => ResponseData responseData)) public responses;

    /// Cooldown: how often the Orb can be invoked.
    mapping(uint256 orbId => uint256 cooldown) public cooldown;
    /// Response Period: time period in which the keeper promises to respond to an invocation.
    /// There are no penalties for being late within this contract.
    mapping(uint256 orbId => uint256 responsePeriod) public responsePeriod;
    /// Last invocation time: when the Orb was last invoked. Used together with `cooldown` constant.
    mapping(uint256 orbId => uint256) public lastInvocationTime;

    /// Addresses authorized for external calls in invokeWithXAndCall()
    mapping(address contractAddress => bool authorizedForCalling) public authorizedContracts;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev  Initializes the contract.
    function initialize() public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
    }

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
            revert ContractHoldsOrb();
        }
        // TODO
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOKING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function initializeOrb(uint256 orbId) public onlyOrbsContract {
        cooldown[orbId] = 7 days;
        responsePeriod[orbId] = 7 days;
    }

    /// @notice  Allows the Orb creator to set the new cooldown duration, response period, flagging period (duration for
    ///          how long Orb keeper may flag a response) and cleartext maximum length. This function can only be called
    ///          by the Orb creator when the Orb is in their control.
    /// @dev     Emits `InvocationParametersUpdate`.
    ///          V2 merges `setCooldown()` and `setCleartextMaximumLength()` into one function, and moves
    ///          `responsePeriod` setting here. Events `CooldownUpdate` and `CleartextMaximumLengthUpdate` are merged
    ///          into `InvocationParametersUpdate`.
    /// @param   newCooldown        New cooldown in seconds. Cannot be longer than `COOLDOWN_MAXIMUM_DURATION`.
    /// @param   newResponsePeriod  New flagging period in seconds.
    function setInvocationParameters(uint256 orbId, uint256 newCooldown, uint256 newResponsePeriod)
        external
        virtual
        onlyCreator(orbId)
        onlyCreatorControlled(orbId)
    {
        if (newCooldown > _COOLDOWN_MAXIMUM_DURATION) {
            revert CooldownExceedsMaximumDuration(newCooldown, _COOLDOWN_MAXIMUM_DURATION);
        }

        uint256 previousCooldown = cooldown[orbId];
        cooldown[orbId] = newCooldown;
        uint256 previousResponsePeriod = responsePeriod[orbId];
        responsePeriod[orbId] = newResponsePeriod;
        emit InvocationParametersUpdate(previousCooldown, newCooldown, previousResponsePeriod, newResponsePeriod);
    }

    function chargeOrb(uint256 orbId) external virtual onlyOrbsContract {
        lastInvocationTime[orbId] = block.timestamp - cooldown[orbId];
    }

    /// @notice  Invokes the Orb. Allows the keeper to submit content hash, that represents a question to the Orb
    ///          creator. Puts the Orb on cooldown. The Orb can only be invoked by solvent keepers.
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
        uint256 _cooldown = cooldown[orbId];

        if (block.timestamp < _lastInvocationTime + _cooldown) {
            revert CooldownIncomplete(_lastInvocationTime + _cooldown - block.timestamp);
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
        if (authorizedContracts[addressToCall] == false) {
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
    /// @param   invocationId  Id of an invocation to which the response is being made.
    /// @param   contentHash   keccak256 hash of the response text.
    function respond(uint256 orbId, uint256 invocationId, bytes32 contentHash) external virtual onlyCreator(orbId) {
        if (invocationId > invocationCount[orbId] || invocationId == 0) {
            revert InvocationNotFound(orbId, invocationId);
        }
        if (_responseExists(orbId, invocationId)) {
            revert ResponseExists(orbId, invocationId);
        }

        responses[orbId][invocationId] = ResponseData(contentHash, block.timestamp);

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

    /// @notice  Allows the owner address to authorize externally callable contracts.
    /// @param   addressToAuthorize  Address of the contract to authorize.
    /// @param   authorizationValue  Boolean value to set the authorization to.
    function authorizeContract(address addressToAuthorize, bool authorizationValue) external virtual onlyOwner {
        authorizedContracts[addressToAuthorize] = authorizationValue;
        emit ContractAuthorization(addressToAuthorize, authorizationValue);
    }

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
