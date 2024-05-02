// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IDelegationMethod} from "./IDelegationMethod.sol";
import {Earnable} from "../Earnable.sol";
import {OrbSystem} from "../OrbSystem.sol";
import {OwnershipRegistry} from "../OwnershipRegistry.sol";
import {InvocationRegistry} from "../InvocationRegistry.sol";
import {PledgeLocker} from "../PledgeLocker.sol";

abstract contract DelegationMethod is IDelegationMethod, Earnable {
    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;

    /// Addresses of all system contracts
    OrbSystem public orbSystem;
    OwnershipRegistry public ownership;
    InvocationRegistry public invocations;

    mapping(uint256 orbId => bool) public isDelegated;
    mapping(uint256 orbId => address) public delegateAddress;
    mapping(uint256 orbId => bytes32) public delegationHash;
    mapping(uint256 orbId => uint256) public delegationExpiration;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    modifier onlyActive(uint256 orbId) virtual {
        if (!isActive(orbId)) {
            revert DelegationNotActive();
        }
        _;
    }

    modifier onlyInactive(uint256 orbId) virtual {
        if (isActive(orbId)) {
            revert DelegationActive();
        }
        _;
    }

    modifier onlyCancelable(uint256 orbId) virtual {
        if (!isCancelable(orbId)) {
            revert DelegationNotCancelable();
        }
        _;
    }

    modifier onlyFinalizable(uint256 orbId) virtual {
        if (!isFinalizable(orbId)) {
            revert DelegationNotFinalizable();
        }
        _;
    }

    modifier onlyDelegated(uint256 orbId) virtual {
        if (isDelegated[orbId] == false) {
            revert NotDelegated();
        }
        _;
    }

    modifier onlyUndelegated(uint256 orbId) virtual {
        if (isDelegated[orbId]) {
            revert Delegated();
        }
        _;
    }

    modifier onlyKeeper(uint256 orbId) virtual {
        if (_msgSender() != OwnershipRegistry(ownership).keeper(orbId)) {
            revert NotKeeper();
        }
        _;
    }

    modifier onlyInvocationRegistry() virtual {
        if (_msgSender() != address(invocations)) {
            revert NotInvocationRegistry();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function isActive(uint256) public view virtual override returns (bool);
    function isCancelable(uint256) public view virtual override returns (bool);
    function isFinalizable(uint256) public view virtual override returns (bool);

    function start(uint256 orbId) public virtual override {
        uint256 pledgedUntil = PledgeLocker(orbSystem.pledgeLockerAddress()).pledgedUntil(orbId);
        // pledge set but expired
        if (pledgedUntil > 0 && pledgedUntil < block.timestamp) {
            revert PledgeInactive();
        }
    }

    function setSystemContracts() external {
        ownership = OwnershipRegistry(orbSystem.ownershipRegistryAddress());
        invocations = InvocationRegistry(orbSystem.invocationRegistryAddress());
    }

    function _expirationDuration(uint256 orbId) internal virtual returns (uint256) {
        return invocations.invocationPeriod(orbId) * 3;
    }

    function _earningsWithdrawalAddress(address user) internal virtual override returns (address) {
        return orbSystem.earningsWithdrawalAddress(user);
    }
}
