// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (proxy/utils/UUPSUpgradeable.sol)

pragma solidity ^0.8.20;

// solhint-disable func-name-mixedcase

import {IERC1822ProxiableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/interfaces/draft-IERC1822Upgradeable.sol";
import {ERC1967UpgradeUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/// @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
/// {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
///
/// A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
/// reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
/// `UUPSUpgradeable` with a custom implementation of upgrades.
///
/// The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
///
/// _Available since v4.1._

abstract contract UUPSUpgradeable is Initializable, IERC1822ProxiableUpgradeable, ERC1967UpgradeUpgradeable {
    // solhint-disable-next-line no-empty-blocks
    function __UUPSUpgradeable_init() internal onlyInitializing {}

    // solhint-disable-next-line no-empty-blocks
    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {}

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable state-variable-assignment
    address private immutable __self = address(this);

    /// @dev Check that the execution is being performed through a delegatecall call and that the execution context is
    /// a proxy contract with an implementation (as defined in ERC1967) pointing to self. This should only be the case
    /// for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
    /// function through ERC1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
    /// fail.
    modifier onlyProxy() {
        require(address(this) != __self, "Must be called via delegatecall");
        require(_getImplementation() == __self, "Must be called via active proxy");
        _;
    }

    /// @dev Check that the execution is not being performed through a delegate call. This allows a function to be
    /// callable on the implementing contract but not through proxies.
    modifier notDelegated() {
        require(address(this) == __self, "Cant be called via delegatecall");
        _;
    }

    /// @dev Implementation of the ERC1822 {proxiableUUID} function. This returns the storage slot used by the
    /// implementation. It is used to validate the implementation's compatibility when performing an upgrade.
    /// IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this
    /// risks bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that
    /// this function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier.
    function proxiableUUID() external view virtual override notDelegated returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[50] private __gap;
}
