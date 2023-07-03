// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Orb} from "./Orb.sol";
import {OrbInvocationRegistry} from "./OrbInvocationRegistry.sol";

/// @title   Orb Invocation Registry v2 - Record-keeping contract for Orb invocations and responses
/// @author  Jonas Lekevicius
/// @notice  The Orb Invocation Registry is used to track invocations and responses for any Orb.
/// @dev     `Orb`s using an `OrbInvocationRegistry` must implement `IOrb` interface. Uses `Ownable`'s `owner()` to
///          guard upgrading.
///          V2 records Late Response Receipts if the response is made after the response period. Together with the
///          `LateResponseDeposit` contract, it can allow Creators to compensate Keepers for late responses.
contract OrbInvocationRegistryV2 is OrbInvocationRegistry {
    struct LateResponseReceipt {
        uint256 lateDuration;
        uint256 price;
        uint256 keeperTaxNumerator;
    }

    error Unauthorized();
    error LateResponseReceiptClaimed(uint256 invocationId);

    event LateResponse(
        address indexed orb, uint256 indexed invocationId, address indexed responder, uint256 lateDuration
    );

    /// Orb Invocation Registry version. Value: 2.
    uint256 private constant _VERSION = 2;

    /// The address of the Late Response Deposit contract.
    address public lateResponseFund;
    /// Mapping for late response receipts. Used to track late response receipts for invocations that have not been
    mapping(address orb => mapping(uint256 invocationId => LateResponseReceipt receipt)) public lateResponseReceipts;
    /// Mapping for late response receipts. Used to track late response receipts for invocations that have not been
    mapping(address orb => mapping(uint256 invocationId => bool receiptClaimed)) public lateResponseReceiptClaimed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice  Re-initializes the contract after upgrade
    /// @param   lateResponseFund_  The address of the Late Response Compensation Fund.
    function initializeV2(address lateResponseFund_) public reinitializer(2) {
        lateResponseFund = lateResponseFund_;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: RESPONDING AND FLAGGING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  The Orb creator can use this function to respond to any existing invocation, no matter how long ago
    ///          it was made. A response to an invocation can only be written once. There is no way to record response
    ///          cleartext on-chain.
    /// @dev     Emits `Response`, and sometimes `LateResponse` if the response was made after the response period.
    /// @param   invocationId  Id of an invocation to which the response is being made.
    /// @param   contentHash   keccak256 hash of the response text.
    function respond(address orb, uint256 invocationId, bytes32 contentHash)
        external
        virtual
        override
        onlyCreator(orb)
    {
        if (invocationId > invocationCount[orb] || invocationId == 0) {
            revert InvocationNotFound(orb, invocationId);
        }
        if (_responseExists(orb, invocationId)) {
            revert ResponseExists(orb, invocationId);
        }

        responses[orb][invocationId] = ResponseData(contentHash, block.timestamp);

        uint256 invocationTime = invocations[orb][invocationId].timestamp;
        uint256 responseDuration = block.timestamp - invocationTime;
        if (responseDuration > Orb(orb).responsePeriod()) {
            uint256 lateDuration = responseDuration - Orb(orb).responsePeriod();
            lateResponseReceipts[orb][invocationId] =
                LateResponseReceipt(lateDuration, Orb(orb).price(), Orb(orb).keeperTaxNumerator());
            emit LateResponse(orb, invocationId, msg.sender, lateDuration);
        }

        emit Response(orb, invocationId, msg.sender, block.timestamp, contentHash);
    }

    function setLateResponseReceiptClaimed(address orb, uint256 invocationId) external {
        if (msg.sender != lateResponseFund) {
            revert Unauthorized();
        }
        if (lateResponseReceipts[orb][invocationId].lateDuration == 0) {
            revert ResponseNotFound(orb, invocationId);
        }
        if (!lateResponseReceiptClaimed[orb][invocationId]) {
            revert LateResponseReceiptClaimed(invocationId);
        }

        lateResponseReceiptClaimed[orb][invocationId] = true;
    }

    /// @notice  Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbInvocationRegistryVersion  Version of the Orb Invocation Registry contract.
    function version() public virtual override returns (uint256 orbInvocationRegistryVersion) {
        return _VERSION;
    }
}
