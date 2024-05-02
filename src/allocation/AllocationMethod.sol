// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IAllocationMethod} from "./IAllocationMethod.sol";
import {Earnable} from "../Earnable.sol";
import {OrbSystem} from "../OrbSystem.sol";
import {OwnershipRegistry} from "../OwnershipRegistry.sol";

abstract contract AllocationMethod is IAllocationMethod, Earnable {
    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;
    uint256 internal constant _KEEPER_TAX_PERIOD = 365 days;

    /// Addresses of all system contracts
    OrbSystem public orbSystem;
    OwnershipRegistry public ownership;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    modifier onlyOwnershipRegistry() virtual {
        if (_msgSender() != orbSystem.ownershipRegistryAddress()) {
            revert NotOwnershipRegistryContract();
        }
        _;
    }

    modifier onlyActive(uint256 orbId) virtual {
        if (!isActive(orbId)) {
            revert AllocationNotActive();
        }
        _;
    }

    modifier onlyInactive(uint256 orbId) virtual {
        if (isActive(orbId)) {
            revert AllocationActive();
        }
        _;
    }

    modifier onlyCancelable(uint256 orbId) virtual {
        if (!isCancelable(orbId)) {
            revert AllocationNotCancelable();
        }
        _;
    }

    modifier onlyFinalizable(uint256 orbId) virtual {
        if (!isFinalizable(orbId)) {
            revert AllocationNotFinalizable();
        }
        _;
    }

    modifier onlyCreator(uint256 orbId) virtual {
        if (_msgSender() != OwnershipRegistry(orbSystem.ownershipRegistryAddress()).creator(orbId)) {
            revert NotCreator();
        }
        _;
    }

    modifier onlyCreatorControlled(uint256 orbId) virtual {
        if (orbSystem.isCreatorControlled(orbId) == false) {
            revert CreatorDoesNotControlOrb();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function _isReallocation(uint256 orbId) internal view virtual returns (bool);
    function isActive(uint256) public view virtual override returns (bool);
    function isCancelable(uint256) public view virtual override returns (bool);
    function isFinalizable(uint256) public view virtual override returns (bool);

    function setSystemContracts() external {
        ownership = OwnershipRegistry(orbSystem.ownershipRegistryAddress());
    }

    function _earningsWithdrawalAddress(address user) internal virtual override returns (address) {
        return orbSystem.earningsWithdrawalAddress(user);
    }
}
