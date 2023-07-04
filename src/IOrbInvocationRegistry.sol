// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165Upgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol";

interface IOrbInvocationRegistry is IERC165Upgradeable {
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

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Authorization Errors
    error NotKeeper();
    error NotCreator();
    error ContractHoldsOrb();
    error KeeperInsolvent();

    // Invoking and Responding Errors
    error CooldownIncomplete(uint256 timeRemaining);
    error CleartextTooLong(uint256 cleartextLength, uint256 cleartextMaximumLength);
    error InvocationNotFound(address orb, uint256 invocationId);
    error ResponseNotFound(address orb, uint256 invocationId);
    error ResponseExists(address orb, uint256 invocationId);
    error FlaggingPeriodExpired(address orb, uint256 invocationId, uint256 currentTimeValue, uint256 timeValueLimit);
    error ResponseAlreadyFlagged(address orb, uint256 invocationId);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function invocations(address orb, uint256 invocationId)
        external
        view
        returns (address invoker, bytes32 contentHash, uint256 timestamp);
    function invocationCount(address orb) external view returns (uint256);

    function responses(address orb, uint256 invocationId)
        external
        view
        returns (bytes32 contentHash, uint256 timestamp);
    function responseFlagged(address orb, uint256 invocationId) external view returns (bool);
    function flaggedResponsesCount(address orb) external view returns (uint256);

    function version() external view returns (uint256);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function invokeWithCleartext(address orb, string memory cleartext) external;
    function invokeWithHash(address orb, bytes32 contentHash) external;
    function respond(address orb, uint256 invocationId, bytes32 contentHash) external;
    function flagResponse(address orb, uint256 invocationId) external;
}
