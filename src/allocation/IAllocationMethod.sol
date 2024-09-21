// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IAllocationMethod {
    event AllocationStart(uint256 indexed orbId, uint256 indexed startTime, uint256 indexed endTime, bool reallocation);
    event AllocationCancellation(uint256 indexed orbId);
    event AllocationFinalization(
        uint256 indexed orbId, address indexed beneficiary, address indexed winner, uint256 proceeds
    );
    event Withdrawal(uint256 indexed orbId, address indexed user, uint256 funds);

    error InvalidPrice(uint256 priceProvided);
    error PriceTooLow(uint256 priceProvided, uint256 minimumPrice);

    error AllocationActive();
    error AllocationNotActive();
    error AllocationNotCancelable();
    error AllocationNotFinalizable();
    error ContractDoesNotHoldOrb();
    error NotOwnershipRegistryContract();
    error NotCreator();
    error CreatorDoesNotControlOrb();
    error NotSupported();
    error NotCancelable();
    error NoFundsAvailable();

    function initializeOrb(uint256 orbId) external;

    function isActive(uint256 orbId) external view returns (bool);

    function isCancelable(uint256 orbId) external view returns (bool);

    function isFinalizable(uint256 orbId) external view returns (bool);

    function start(uint256 orbId) external;

    function cancel(uint256 orbId) external;

    function finalize(uint256 orbId) external;

    function version() external view returns (uint256);
}
