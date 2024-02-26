// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract OrbInvocationRegistry is OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event Invocation(
        address indexed orb,
        uint256 indexed invocationId,
        address indexed invoker,
        uint256 timestamp,
        bytes32 contentHash
    );
    event Response(
        address indexed orb,
        uint256 indexed invocationId,
        address indexed responder,
        uint256 timestamp,
        bytes32 contentHash
    );
    event CleartextRecording(address indexed orb, uint256 indexed invocationId, string cleartext);
    event ResponseFlagging(address indexed orb, uint256 indexed invocationId, address indexed flagger);

    event ContractAuthorization(address indexed contractAddress, bool indexed authorized);

    event InvocationParametersUpdate(
        uint256 previousCooldown,
        uint256 indexed newCooldown,
        uint256 previousResponsePeriod,
        uint256 indexed newResponsePeriod
    );

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Authorization Errors
    error NotKeeper();
    error NotCreator();
    error ContractHoldsOrb();
    error KeeperInsolvent();
    error ContractNotAuthorized(address externalContract);

    // Invoking and Responding Errors
    error CooldownIncomplete(uint256 timeRemaining);
    error CleartextTooLong(uint256 cleartextLength, uint256 cleartextMaximumLength);
    error InvocationNotFound(address orb, uint256 invocationId);
    error ResponseNotFound(address orb, uint256 invocationId);
    error ResponseExists(address orb, uint256 invocationId);
    error FlaggingPeriodExpired(address orb, uint256 invocationId, uint256 currentTimeValue, uint256 timeValueLimit);
    error ResponseAlreadyFlagged(address orb, uint256 invocationId);

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
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  MODIFIERS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev    Ensures that the caller owns the Orb. Should only be used in conjuction with `onlyKeeperHeld` or on
    ///         external functions, otherwise does not make sense.
    /// @param  orb  Address of the Orb.
    modifier onlyKeeper(address orb) virtual {
        if (msg.sender != Orb(orb).keeper()) {
            revert NotKeeper();
        }
        _;
    }

    /// @dev    Ensures that the Orb belongs to someone, not the contract itself.
    /// @param  orb  Address of the Orb.
    modifier onlyKeeperHeld(address orb) virtual {
        if (orb == Orb(orb).keeper()) {
            revert ContractHoldsOrb();
        }
        _;
    }

    /// @dev    Ensures that the current Orb keeper has enough funds to cover Harberger tax until now.
    /// @param  orb  Address of the Orb.
    modifier onlyKeeperSolvent(address orb) virtual {
        if (!Orb(orb).keeperSolvent()) {
            revert KeeperInsolvent();
        }
        _;
    }

    /// @dev    Ensures that the caller is the creator of the Orb.
    /// @param  orb  Address of the Orb.
    modifier onlyCreator(address orb) virtual {
        if (msg.sender != Orb(orb).creator()) {
            revert NotCreator();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOKING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function initializeOrb() public {
        cooldown = 7 days;
        responsePeriod = 7 days;
    }

    /// @notice  Allows the Orb creator to set the new cooldown duration, response period, flagging period (duration for
    ///          how long Orb keeper may flag a response) and cleartext maximum length. This function can only be called
    ///          by the Orb creator when the Orb is in their control.
    /// @dev     Emits `InvocationParametersUpdate`.
    ///          V2 merges `setCooldown()` and `setCleartextMaximumLength()` into one function, and moves
    ///          `responsePeriod` setting here. Events `CooldownUpdate` and `CleartextMaximumLengthUpdate` are merged
    ///          into `InvocationParametersUpdate`.
    /// @param   newCooldown        New cooldown in seconds. Cannot be longer than `COOLDOWN_MAXIMUM_DURATION`.
    /// @param   newFlaggingPeriod  New flagging period in seconds.
    /// @param   newResponsePeriod  New flagging period in seconds.
    /// @param   newCleartextMaximumLength  New cleartext maximum length. Cannot be 0.
    function setInvocationParameters(
        uint256 newCooldown,
        uint256 newResponsePeriod,
        uint256 newFlaggingPeriod,
        uint256 newCleartextMaximumLength
    ) external virtual onlyOwner onlyCreatorControlled {
        if (newCooldown > _COOLDOWN_MAXIMUM_DURATION) {
            revert CooldownExceedsMaximumDuration(newCooldown, _COOLDOWN_MAXIMUM_DURATION);
        }
        if (newCleartextMaximumLength == 0) {
            revert InvalidCleartextMaximumLength(newCleartextMaximumLength);
        }

        uint256 previousCooldown = cooldown;
        cooldown = newCooldown;
        uint256 previousResponsePeriod = responsePeriod;
        responsePeriod = newResponsePeriod;
        uint256 previousFlaggingPeriod = flaggingPeriod;
        flaggingPeriod = newFlaggingPeriod;
        uint256 previousCleartextMaximumLength = cleartextMaximumLength;
        cleartextMaximumLength = newCleartextMaximumLength;
        emit InvocationParametersUpdate(
            previousCooldown,
            newCooldown,
            previousResponsePeriod,
            newResponsePeriod,
            previousFlaggingPeriod,
            newFlaggingPeriod,
            previousCleartextMaximumLength,
            newCleartextMaximumLength
        );
    }

    function chargeOrb() {
        lastInvocationTime = block.timestamp - cooldown;
    }

    /// @notice  Invokes the Orb. Allows the keeper to submit cleartext.
    /// @dev     Cleartext is hashed and passed to `invokeWithHash()`. Emits `CleartextRecording`.
    /// @param   orb        Address of the Orb.
    /// @param   cleartext  Invocation cleartext.
    function invokeWithCleartext(address orb, string memory cleartext) public virtual {
        uint256 cleartextMaximumLength = Orb(orb).cleartextMaximumLength();

        uint256 length = bytes(cleartext).length;
        if (length > cleartextMaximumLength) {
            revert CleartextTooLong(length, cleartextMaximumLength);
        }
        invokeWithHash(orb, keccak256(abi.encodePacked(cleartext)));
        emit CleartextRecording(orb, invocationCount[orb], cleartext);
    }

    /// @notice  Invokes the Orb with cleartext and calls an external contract.
    /// @dev     Calls `invokeWithCleartext()` and then calls the external contract.
    /// @param   orb            Address of the Orb.
    /// @param   cleartext      Invocation cleartext.
    /// @param   addressToCall  Address of the contract to call.
    /// @param   dataToCall     Data to call the contract with.
    function invokeWithCleartextAndCall(
        address orb,
        string memory cleartext,
        address addressToCall,
        bytes memory dataToCall
    ) external virtual {
        invokeWithCleartext(orb, cleartext);
        _callWithData(addressToCall, dataToCall);
    }

    /// @notice  Invokes the Orb. Allows the keeper to submit content hash, that represents a question to the Orb
    ///          creator. Puts the Orb on cooldown. The Orb can only be invoked by solvent keepers.
    /// @dev     Content hash is keccak256 of the cleartext. `invocationCount` is used to track the id of the next
    ///          invocation. Invocation ids start from 1. Emits `Invocation`.
    /// @param   orb          Address of the Orb.
    /// @param   contentHash  Required keccak256 hash of the cleartext.
    function invokeWithHash(address orb, bytes32 contentHash)
        public
        virtual
        onlyKeeper(orb)
        onlyKeeperHeld(orb)
        onlyKeeperSolvent(orb)
    {
        uint256 lastInvocationTime = Orb(orb).lastInvocationTime();
        uint256 cooldown = Orb(orb).cooldown();

        if (block.timestamp < lastInvocationTime + cooldown) {
            revert CooldownIncomplete(lastInvocationTime + cooldown - block.timestamp);
        }

        invocationCount[orb] += 1;
        uint256 invocationId = invocationCount[orb]; // starts at 1

        invocations[orb][invocationId] = InvocationData(msg.sender, contentHash, block.timestamp);
        Orb(orb).setLastInvocationTime(block.timestamp);

        emit Invocation(orb, invocationId, msg.sender, block.timestamp, contentHash);
    }

    /// @notice  Invokes the Orb with content hash and calls an external contract.
    /// @dev     Calls `invokeWithHash()` and then calls the external contract.
    /// @param   orb            Address of the Orb.
    /// @param   contentHash    Required keccak256 hash of the cleartext.
    /// @param   addressToCall  Address of the contract to call.
    /// @param   dataToCall     Data to call the contract with.
    function invokeWithHashAndCall(address orb, bytes32 contentHash, address addressToCall, bytes memory dataToCall)
        external
        virtual
    {
        invokeWithHash(orb, contentHash);
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
    /// @param   orb           Address of the Orb.
    /// @param   invocationId  Id of an invocation to which the response is being made.
    /// @param   contentHash   keccak256 hash of the response text.
    function respond(address orb, uint256 invocationId, bytes32 contentHash) external virtual onlyCreator(orb) {
        if (invocationId > invocationCount[orb] || invocationId == 0) {
            revert InvocationNotFound(orb, invocationId);
        }
        if (_responseExists(orb, invocationId)) {
            revert ResponseExists(orb, invocationId);
        }

        responses[orb][invocationId] = ResponseData(contentHash, block.timestamp);

        emit Response(orb, invocationId, msg.sender, block.timestamp, contentHash);
    }

    /// @dev     Returns if a response to an invocation exists, based on the timestamp of the response being non-zero.
    /// @param   orb            Address of the Orb.
    /// @param   invocationId_  Id of an invocation to which to check the existence of a response of.
    /// @return  isResponseFound  If a response to an invocation exists or not.
    function _responseExists(address orb, uint256 invocationId_) internal view virtual returns (bool isResponseFound) {
        if (responses[orb][invocationId_].timestamp != 0) {
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
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
