// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165Upgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol";

interface IOrbInvocationRegistry is IERC165Upgradeable {
    event Invocation(
        uint256 indexed invocationId, address indexed invoker, uint256 indexed timestamp, bytes32 contentHash
    );
    event Response(
        uint256 indexed invocationId, address indexed responder, uint256 indexed timestamp, bytes32 contentHash
    );
    event CleartextRecording(uint256 indexed invocationId, string cleartext);
    event ResponseFlagging(uint256 indexed invocationId, address indexed flagger);

    error NotKeeper();
    error ContractHoldsOrb();
    error KeeperInsolvent();
    // Invoking and Responding Errors
    error CooldownIncomplete(uint256 timeRemaining);
    error CleartextTooLong(uint256 cleartextLength, uint256 cleartextMaximumLength);
    error InvocationNotFound(uint256 invocationId);
    error ResponseNotFound(uint256 invocationId);
    error ResponseExists(uint256 invocationId);
    error FlaggingPeriodExpired(uint256 invocationId, uint256 currentTimeValue, uint256 timeValueLimit);
    error ResponseAlreadyFlagged(uint256 invocationId);
}
