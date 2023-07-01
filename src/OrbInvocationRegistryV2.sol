// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Orb} from "./Orb.sol";
import {OrbInvocationRegistry, ResponseData} from "./OrbInvocationRegistry.sol";

struct LateResponseReceipt {
    uint256 lateDuration;
    uint256 price;
    uint256 keeperTaxNumerator;
}

/// @title   Orb Invocation Registry
/// @author  Jonas Lekevicius
/// @notice  Registry to track invocations and responses of all Orbs. Can be used by any Orb. Each OrbPond has a
///          reference to an OrbInvocationRegistry respected by Orbs produced by that OrbPond
/// @dev     Uses `Ownable`'s `owner()` for upgrades.
contract OrbInvocationRegistryV2 is OrbInvocationRegistry {
    error Unauthorized();
    error LateResponseReceiptClaimed(uint256 invocationId);

    /// The address of the Late Response Deposit contract.
    address public lateResponseDepositAddress;
    /// Mapping for late response receipts. Used to track late response receipts for invocations that have not been
    mapping(address orb => mapping(uint256 invocationId => LateResponseReceipt receipt)) public lateResponseReceipts;
    /// Mapping for late response receipts. Used to track late response receipts for invocations that have not been
    mapping(address orb => mapping(uint256 invocationId => bool receiptClaimed)) public lateResponseReceiptClaimed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice  Re-initializes the contract after upgrade
    /// @param   lateResponseDepositAddress_  The address of the Orb Land wallet.
    function initializeV2(address lateResponseDepositAddress_) public reinitializer(2) {
        lateResponseDepositAddress = lateResponseDepositAddress_;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: RESPONDING AND FLAGGING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  The Orb creator can use this function to respond to any existing invocation, no matter how long ago
    ///          it was made. A response to an invocation can only be written once. There is no way to record response
    ///          cleartext on-chain.
    /// @dev     Emits `Response`.
    /// @param   invocationId  Id of an invocation to which the response is being made.
    /// @param   contentHash   keccak256 hash of the response text.
    function respond(address orb, uint256 invocationId, bytes32 contentHash)
        external
        virtual
        override
        onlyCreator(orb)
    {
        if (invocationId > invocationCount[orb] || invocationId == 0) {
            revert InvocationNotFound(invocationId);
        }
        if (_responseExists(orb, invocationId)) {
            revert ResponseExists(invocationId);
        }

        responses[orb][invocationId] = ResponseData(contentHash, block.timestamp);

        uint256 invocationTime = invocations[orb][invocationId].timestamp;
        uint256 responseDuration = block.timestamp - invocationTime;
        if (responseDuration > Orb(orb).responsePeriod()) {
            lateResponseReceipts[orb][invocationId] = LateResponseReceipt(
                responseDuration - Orb(orb).responsePeriod(), Orb(orb).price(), Orb(orb).keeperTaxNumerator()
            );
        }

        emit Response(invocationId, msg.sender, block.timestamp, contentHash);
    }

    function setLateResponseReceiptClaimed(address orb, uint256 invocationId) external {
        if (msg.sender != lateResponseDepositAddress) {
            revert Unauthorized();
        }
        if (lateResponseReceipts[orb][invocationId].lateDuration == 0) {
            revert ResponseNotFound(invocationId);
        }
        if (!lateResponseReceiptClaimed[orb][invocationId]) {
            revert LateResponseReceiptClaimed(invocationId);
        }

        lateResponseReceiptClaimed[orb][invocationId] = true;
    }
}
