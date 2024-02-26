// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase
pragma solidity 0.8.20;

import {IERC1822Proxiable} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC1822.sol";
import {ERC1967Utils} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/// @title   CustomUUPSUpgradeable - UUPSUpgradeable without public functions
/// @author  Jonas Lekevicius
/// @dev     An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade
///          of an `ERC1967Proxy`, when this contract is set as the implementation behind such a proxy. This is a
///          modified version of the OpenZeppelin Contract `UUPSUpgradeable` contract that does not expose any public
///          functions, to allow custom upgradeability logic to be implemented in the `Orb` contract.
///          Also, replaces string errors with custom errors.
/// @custom:security-contact security@orb.land
abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    // Errors
    error UUPSUnauthorizedCallContext();
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    // solhint-disable-next-line immutable-vars-naming
    address private immutable __self = address(this);

    // solhint-disable-next-line no-empty-blocks
    function __UUPSUpgradeable_init() internal onlyInitializing {}

    // solhint-disable-next-line no-empty-blocks
    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {}

    /**
     * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
     * a proxy contract with an implementation (as defined in ERC-1967) pointing to self. This should only be the case
     * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
     * function through ERC-1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
     * fail.
     */
    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    /**
     * @dev Check that the execution is not being performed through a delegate call. This allows a function to be
     * callable on the implementing contract but not through proxies.
     */
    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    /**
     * @dev Implementation of the ERC-1822 {proxiableUUID} function. This returns the storage slot used by the
     * implementation. It is used to validate the implementation's compatibility when performing an upgrade.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier.
     */
    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    /**
     * @dev Reverts if the execution is not performed via delegatecall or the execution
     * context is not of a proxy with an ERC-1967 compliant implementation pointing to self.
     * See {_onlyProxy}.
     */
    function _checkProxy() internal view virtual {
        if (
            address(this) == __self // Must be called through delegatecall
                || ERC1967Utils.getImplementation() != __self // Must be called through an active proxy
        ) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Reverts if the execution is performed via delegatecall.
     * See {notDelegated}.
     */
    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            // Must not be called through delegatecall
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Performs an implementation upgrade with a security check for UUPS proxies, and additional setup call.
     *
     * As a security check, {proxiableUUID} is invoked in the new implementation, and the return value
     * is expected to be the implementation slot in ERC-1967.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) internal {
        try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
                revert UUPSUnsupportedProxiableUUID(slot);
            }
            ERC1967Utils.upgradeToAndCall(newImplementation, data);
        } catch {
            // The implementation is not UUPS
            revert ERC1967Utils.ERC1967InvalidImplementation(newImplementation);
        }
    }

    /// @dev  This empty reserved space is put in place to allow future versions to add new variables without shifting
    ///       down storage in the inheritance chain.
    ///       See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[50] private __gap;
}
