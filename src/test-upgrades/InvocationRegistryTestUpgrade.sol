// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {InvocationRegistry, ResponseData} from "../InvocationRegistry.sol";

/// @title   Orb Invocation Registry Test Upgrade - Record-keeping contract for Orb invocations and responses
/// @author  Jonas Lekevicius
/// @notice  The Orb Invocation Registry is used to track invocations and responses for any Orb.
/// @dev     `Orb`s using an `OrbInvocationRegistry` must implement `IOrb` interface. Uses `Ownable`'s `owner()` to
///          guard upgrading.
///          Test Upgrade records Late Response Receipts if the response is made after the response period. Together
///          with the `LateResponseDeposit` contract, it can allow Creators to compensate Keepers for late responses.
contract InvocationRegistryTestUpgrade is InvocationRegistry {
    struct LateResponseReceipt {
        uint256 lateDuration;
        uint256 price;
        uint256 keeperTaxNumerator;
    }

    error InvocationNotFound(uint256 orbId, uint256 invocationId);
    error Unauthorized();
    error LateResponseReceiptClaimed(uint256 invocationId);

    event LateResponse(
        uint256 indexed orbId, uint256 indexed invocationId, address indexed responder, uint256 lateDuration
    );

    /// Orb Invocation Registry version.
    uint256 private constant _VERSION = 100;

    /// The address of the Late Response Deposit contract.
    address public lateResponseFund;
    /// Mapping for late response receipts. Used to track late response receipts for invocations that have not been
    mapping(uint256 orbId => mapping(uint256 invocationId => LateResponseReceipt receipt)) public lateResponseReceipts;
    /// Mapping for late response receipts. Used to track late response receipts for invocations that have not been
    mapping(uint256 orbId => mapping(uint256 invocationId => bool receiptClaimed)) public lateResponseReceiptClaimed;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice  Re-initializes the contract after upgrade
    /// @param   lateResponseFund_  The address of the Late Response Compensation Fund.
    function initializeTestUpgrade(address lateResponseFund_) public reinitializer(100) {
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
    function respond(uint256 orbId, uint256 invocationId, bytes32 contentHash) external virtual onlyCreator(orbId) {
        if (invocationId > invocationCount[orbId] || invocationId == 0) {
            revert InvocationNotFound(orbId, invocationId);
        }
        if (_responseExists(orbId, invocationId)) {
            revert ResponseExists(orbId, invocationId);
        }

        responses[orbId][invocationId] = ResponseData(contentHash, block.timestamp);

        uint256 invocationTime = invocations[orbId][invocationId].timestamp;
        uint256 responseDuration = block.timestamp - invocationTime;
        if (responseDuration > invocationPeriod[orbId]) {
            uint256 lateDuration = responseDuration - invocationPeriod[orbId];
            lateResponseReceipts[orbId][invocationId] =
                LateResponseReceipt(lateDuration, os.ownership().price(orbId), os.ownership().keeperTax(orbId));
            emit LateResponse(orbId, invocationId, msg.sender, lateDuration);
        }

        emit Response(orbId, invocationId, msg.sender, block.timestamp, contentHash);
    }

    function setLateResponseReceiptClaimed(uint256 orbId, uint256 invocationId) external {
        if (msg.sender != lateResponseFund) {
            revert Unauthorized();
        }
        if (lateResponseReceipts[orbId][invocationId].lateDuration == 0) {
            revert ResponseNotFound(orbId, invocationId);
        }
        if (!lateResponseReceiptClaimed[orbId][invocationId]) {
            revert LateResponseReceiptClaimed(invocationId);
        }

        lateResponseReceiptClaimed[orbId][invocationId] = true;
    }

    /// @notice  Returns the version of the Orb Invocation Registry. Internal constant `_VERSION` will be increased with
    ///          each upgrade.
    /// @return  versionNumber  Version of the Orb Invocation Registry contract.
    function version() public view virtual override returns (uint256 versionNumber) {
        return _VERSION;
    }
}
