// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentSplitterUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/finance/PaymentSplitterUpgradeable.sol";

/// @title   CustomPaymentSplitter - Payment Splitter with initializer
/// @author  Jonas Lekevicius
/// @dev     An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade
///          of an `ERC1967Proxy`, when this contract is set as the implementation behind such a proxy. This is a
///          modified version of the OpenZeppelin Contract `UUPSUpgradeable` contract that does not expose any public
///          functions, to allow custom upgradeability logic to be implemented in the `Orb` contract.
///          Also, replaces string errors with custom errors.
contract PaymentSplitter is PaymentSplitterUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev    When deployed, contract mints the only token that will ever exist, to itself.
    ///         This token represents the Orb and is called the Orb elsewhere in the contract.
    ///         `Ownable` sets the deployer to be the `owner()`, and also the creator in the Orb context.
    /// @param  payees_   Address to receive all Orb proceeds.
    /// @param  shares_   Orb name, used in ERC-721 metadata.
    function initialize(address[] memory payees_, uint256[] memory shares_) public initializer {
        __PaymentSplitter_init(payees_, shares_);
    }
}
