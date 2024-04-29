// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IDelegationMethod {
    event DelegationStart(uint256 indexed orbId, uint256 indexed startTime, uint256 indexed endTime);
    event DelegationCancellation(uint256 indexed orbId);
    event DelegationFinalization(uint256 indexed orbId, address indexed delegate, uint256 indexed proceeds);
    event Withdrawal(uint256 indexed orbId, address indexed user, uint256 funds);

    error InvalidPrice(uint256 priceProvided);
    error PriceTooLow(uint256 priceProvided, uint256 minimumPrice);

    error DelegationActive();
    error DelegationNotActive();
    error DelegationNotCancelable();
    error DelegationNotFinalizable();
    error DelegationNotStarted();
    error ContractDoesNotHoldOrb();
    error NotOwnershipRegistryContract();
    error NotCreator();
    error CreatorDoesNotControlOrb();
    error NotSupported();
    error Delegated();
    error NotDelegated();
    error NotInvocationRegistry();
    error NotKeeper();
    error PledgeInactive();
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
