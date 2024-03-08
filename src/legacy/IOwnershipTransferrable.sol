// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IOwnershipTransferrable {
    function transferOwnership(address newOwner) external;
}
