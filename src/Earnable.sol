// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

/// @title   Earnable contract functions
/// @author  Jonas Lekevicius
/// @custom:security-contact security@orb.land
abstract contract Earnable is ContextUpgradeable {
    event EarningsWithdrawal(address indexed user, uint256 amount);

    error NoEarningsAvailable();

    /// Earnings are:
    /// - Royalties from Orb purchase when not purchased from the Orb creator;
    /// - Full purchase price when purchased from the Orb creator;
    /// - Harberger tax revenue.
    mapping(address user => uint256 earnings) public earningsOf;

    function _earningsWithdrawalAddress(address) internal virtual returns (address);

    function _addEarnings(address user, uint256 amount) internal {
        uint256 platformShare = (amount * 5_00) / 100_00;
        uint256 userShare = amount - platformShare;

        earningsOf[address(0)] += platformShare;
        earningsOf[user] += userShare;
    }

    /// @notice  Function to withdraw all beneficiary funds on the contract. Settles if possible.
    /// @dev     Allowed for anyone at any time, does not use `_msgSender()` in its execution.
    ///          Emits `Withdrawal`.
    ///          V2 changes to withdraw to `beneficiaryWithdrawalAddress` if set to a non-zero address, and copies
    ///          `_withdraw()` functionality to this function, as it modifies funds of a different address (always
    ///          `beneficiary`) than the withdrawal destination (potentially `beneficiaryWithdrawalAddress`).
    function withdrawAllEarnings() external virtual {
        _withdrawAllEarnings(_msgSender());
    }

    function withdrawPlatformEarnings() external virtual {
        _withdrawAllEarnings(address(0));
    }

    function _withdrawAllEarnings(address user) internal {
        uint256 amount = earningsOf[user];
        earningsOf[user] = 0;

        if (amount == 0) {
            revert NoEarningsAvailable();
        }

        emit EarningsWithdrawal(user, amount);

        address withdrawalAddressRedirect = _earningsWithdrawalAddress(user);
        address withdrawalAddress = withdrawalAddressRedirect == address(0) ? user : withdrawalAddressRedirect;

        Address.sendValue(payable(withdrawalAddress), amount);
    }
}
