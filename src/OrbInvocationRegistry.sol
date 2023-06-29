// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IOrb} from "./IOrb.sol";
import {IOrbInvocationRegistry} from "./IOrbInvocationRegistry.sol";
import {IERC165Upgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol";
import {ERC165Upgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/ERC165Upgradeable.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract OrbInvocationRegistry is
    Initializable,
    IOrbInvocationRegistry,
    ERC165Upgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    address public pond;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        pond = msg.sender;
    }

    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Invoking and Responding Events

    /// @dev  Ensures that the caller owns the Orb. Should only be used in conjuction with `onlyKeeperHeld` or on
    ///       external functions, otherwise does not make sense.
    ///       Contract inherits `onlyOwner` modifier from `Ownable`.
    modifier onlyKeeper(address orb) {
        if (msg.sender != IOrb(orb).keeper()) {
            revert NotKeeper();
        }
        _;
    }

    // ORB STATE MODIFIERS

    /// @dev  Ensures that the Orb belongs to someone, not the contract itself.
    modifier onlyKeeperHeld(address orb) {
        if (address(this) == IOrb(orb).keeper()) {
            revert ContractHoldsOrb();
        }
        _;
    }

    /// @dev  Ensures that the current Orb keeper has enough funds to cover Harberger tax until now.
    modifier onlyKeeperSolvent(address orb) {
        if (!IOrb(orb).keeperSolvent()) {
            revert KeeperInsolvent();
        }
        _;
    }

    modifier onlyCreator() {
        _;
    }

    // Invocation and Response State Variables

    /// Structs used to track invocation and response information: keccak256 content hash and block timestamp.
    /// InvocationData is used to determine if the response can be flagged by the keeper.
    /// Invocation timestamp is tracked for the benefit of other contracts.
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

    /// Mapping for invocations: invocationId to InvocationData struct. InvocationId starts at 1.
    mapping(uint256 => InvocationData) public invocations;
    /// Count of invocations made: used to calculate invocationId of the next invocation.
    uint256 public invocationCount;
    /// Mapping for responses (answers to invocations): matching invocationId to ResponseData struct.
    mapping(uint256 => ResponseData) public responses;
    /// Mapping for flagged (reported) responses. Used by the keeper not satisfied with a response.
    mapping(uint256 => bool) public responseFlagged;
    /// Flagged responses count is a convencience count of total flagged responses. Not used by the contract itself.
    uint256 public flaggedResponsesCount;

    /// @dev     ERC-165 supportsInterface. Orb contract supports ERC-721 and IOrb interfaces.
    /// @param   interfaceId           Interface id to check for support.
    /// @return  isInterfaceSupported  If interface with given 4 bytes id is supported.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165Upgradeable, IERC165Upgradeable)
        returns (bool isInterfaceSupported)
    {
        return interfaceId == type(IOrbInvocationRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOKING AND RESPONDING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Invokes the Orb. Allows the keeper to submit cleartext.
    /// @dev     Cleartext is hashed and passed to `invokeWithHash()`. Emits `CleartextRecording`.
    /// @param   cleartext  Invocation cleartext.
    function invokeWithCleartext(address orb, string memory cleartext) external {
        uint256 cleartextMaximumLength = IOrb(orb).cleartextMaximumLength();

        uint256 length = bytes(cleartext).length;
        if (length > cleartextMaximumLength) {
            revert CleartextTooLong(length, cleartextMaximumLength);
        }
        invokeWithHash(orb, keccak256(abi.encodePacked(cleartext)));
        emit CleartextRecording(invocationCount, cleartext);
    }

    /// @notice  Invokes the Orb. Allows the keeper to submit content hash, that represents a question to the Orb
    ///          creator. Puts the Orb on cooldown. The Orb can only be invoked by solvent keepers.
    /// @dev     Content hash is keccak256 of the cleartext. `invocationCount` is used to track the id of the next
    ///          invocation. Invocation ids start from 1. Emits `Invocation`.
    /// @param   contentHash  Required keccak256 hash of the cleartext.
    function invokeWithHash(address orb, bytes32 contentHash)
        public
        onlyKeeper(orb)
        onlyKeeperHeld(orb)
        onlyKeeperSolvent(orb)
    {
        uint256 lastInvocationTime = IOrb(orb).lastInvocationTime();
        uint256 cooldown = IOrb(orb).cooldown();

        if (block.timestamp < lastInvocationTime + cooldown) {
            revert CooldownIncomplete(lastInvocationTime + cooldown - block.timestamp);
        }

        invocationCount += 1;
        uint256 invocationId = invocationCount; // starts at 1

        invocations[invocationId] = InvocationData(msg.sender, contentHash, block.timestamp);
        IOrb(orb).setLastInvocationTime(block.timestamp);

        emit Invocation(invocationId, msg.sender, block.timestamp, contentHash);
    }

    /// @notice  The Orb creator can use this function to respond to any existing invocation, no matter how long ago
    ///          it was made. A response to an invocation can only be written once. There is no way to record response
    ///          cleartext on-chain.
    /// @dev     Emits `Response`.
    /// @param   invocationId  Id of an invocation to which the response is being made.
    /// @param   contentHash   keccak256 hash of the response text.
    function respond(uint256 invocationId, bytes32 contentHash) external onlyCreator {
        if (invocationId > invocationCount || invocationId == 0) {
            revert InvocationNotFound(invocationId);
        }

        if (_responseExists(invocationId)) {
            revert ResponseExists(invocationId);
        }

        responses[invocationId] = ResponseData(contentHash, block.timestamp);

        emit Response(invocationId, msg.sender, block.timestamp, contentHash);
    }

    /// @notice  Orb keeper can flag a response during Response Flagging Period, counting from when the response is
    ///          made. Flag indicates a "report", that the Orb keeper was not satisfied with the response provided.
    ///          This is meant to act as a social signal to future Orb keepers. It also increments
    ///          `flaggedResponsesCount`, allowing anyone to quickly look up how many responses were flagged.
    /// @dev     Only existing responses (with non-zero timestamps) can be flagged. Responses can only be flagged by
    ///          solvent keepers to keep it consistent with `invokeWithHash()` or `invokeWithCleartext()`. Also, the
    ///          keeper must have received the Orb after the response was made; this is to prevent keepers from
    ///          flagging responses that were made in response to others' invocations. Emits `ResponseFlagging`.
    /// @param   invocationId  Id of an invocation to which the response is being flagged.
    function flagResponse(address orb, uint256 invocationId) external onlyKeeper(orb) onlyKeeperSolvent(orb) {
        uint256 keeperReceiveTime = IOrb(orb).keeperReceiveTime();
        uint256 flaggingPeriod = IOrb(orb).flaggingPeriod();

        if (!_responseExists(invocationId)) {
            revert ResponseNotFound(invocationId);
        }

        // Response Flagging Period starts counting from when the response is made.
        uint256 responseTime = responses[invocationId].timestamp;
        if (block.timestamp - responseTime > flaggingPeriod) {
            revert FlaggingPeriodExpired(invocationId, block.timestamp - responseTime, flaggingPeriod);
        }
        if (keeperReceiveTime >= responseTime) {
            revert FlaggingPeriodExpired(invocationId, keeperReceiveTime, responseTime);
        }
        if (responseFlagged[invocationId]) {
            revert ResponseAlreadyFlagged(invocationId);
        }

        responseFlagged[invocationId] = true;
        flaggedResponsesCount += 1;

        emit ResponseFlagging(invocationId, msg.sender);
    }

    /// @dev     Returns if a response to an invocation exists, based on the timestamp of the response being non-zero.
    /// @param   invocationId_  Id of an invocation to which to check the existance of a response of.
    /// @return  isResponseFound  If a response to an invocation exists or not.
    function _responseExists(uint256 invocationId_) internal view returns (bool isResponseFound) {
        if (responses[invocationId_].timestamp != 0) {
            return true;
        }
        return false;
    }
}
