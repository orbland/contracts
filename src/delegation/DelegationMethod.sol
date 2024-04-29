// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IDelegationMethod} from "./IDelegationMethod.sol";
import {Earnable} from "../Earnable.sol";
import {OrbSystem} from "../OrbSystem.sol";

abstract contract DelegationMethod is IDelegationMethod, Earnable {
    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;

    /// Addresses of all system contracts
    OrbSystem public os;

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
        if (_msgSender() != os.ownership().keeper(orbId)) {
            revert NotKeeper();
        }
        _;
    }

    modifier onlyInvocationRegistry() virtual {
        if (_msgSender() != os.invocationRegistryAddress()) {
            revert NotInvocationRegistry();
        }
        _;
    }

    modifier onlyOwnershipRegistry() virtual {
        if (_msgSender() != os.ownershipRegistryAddress()) {
            revert NotOwnershipRegistryContract();
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
        uint256 pledgedUntil = os.pledges().pledgedUntil(orbId);
        // pledge set but expired
        if (pledgedUntil > 0 && pledgedUntil < block.timestamp) {
            revert PledgeInactive();
        }
    }

    function _expirationDuration(uint256 orbId) internal virtual returns (uint256) {
        return os.invocations().invocationPeriod(orbId) * 3;
    }

    function _platformFee() internal virtual override returns (uint256) {
        return os.platformFee();
    }

    function _feeDenominator() internal virtual override returns (uint256) {
        return os.feeDenominator();
    }

    function _earningsWithdrawalAddress(address user) internal virtual override returns (address) {
        return os.earningsWithdrawalAddress(user);
    }
}
