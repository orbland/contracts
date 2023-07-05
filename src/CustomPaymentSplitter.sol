// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentSplitterUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/finance/PaymentSplitterUpgradeable.sol";

/// @title   CustomPaymentSplitter - Payment Splitter with initializer
/// @author  Jonas Lekevicius
/// @dev     This is a non-abstract version of the OpenZeppelin Contract `PaymentSplitterUpgradeable` contract that
///          implements an initializer, and has a constructor to disable the initializer on base deployment. Meant to be
///          used as an implementation to a EIP-1167 clone factory. This contract is not actually upgradeable despite
///          the name of the base contract.
contract PaymentSplitter is PaymentSplitterUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev    Calls the initializer of the `PaymentSplitterUpgradeable` contract, with payees and their shares.
    /// @param  payees_   Payees addresses.
    /// @param  shares_   Payees shares.
    function initialize(address[] memory payees_, uint256[] memory shares_) public initializer {
        __PaymentSplitter_init(payees_, shares_);
    }
}
