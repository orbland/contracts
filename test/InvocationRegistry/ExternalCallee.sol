// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title   External Callee for Orb Invocation Registry test
/// @author  Jonas Lekevicius
/// @dev     Contract used to test `invokeWithXAndCall()` functions
contract ExternalCallee {
    error InvalidNumber(uint256 number);

    event NumberUpdate(uint256 number);

    uint256 public number = 42;

    function setNumber(uint256 newNumber) public {
        if (newNumber == 0) revert InvalidNumber(newNumber);
        number = newNumber;
        emit NumberUpdate(number);
    }
}
