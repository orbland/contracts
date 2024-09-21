// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Orb} from "../Orb.sol";
import {OrbInvocationTipJar} from "../OrbInvocationTipJar.sol";

/// @title   Orb Invocation Tip Jar Test Upgrade - A contract for suggesting Orb invocations and tipping Orb keepers
/// @author  Jonas Lekevicius
/// @notice  This contract allows anyone to suggest an invocation to an Orb and optionally tip the Orb keeper
///          Test Upgrade requires all tips to be multiples of fixed amount of ETH.
contract OrbInvocationTipJarTestUpgrade is OrbInvocationTipJar {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Invocation Tip Jar version.
    uint256 private constant _VERSION = 100;

    /// An amount of ETH that is used as a tip modulo. All tips must be multiples of this amount.
    uint256 public tipModulo;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event TipModuloUpdate(uint256 previousTipModulo, uint256 indexed newTipModulo);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error TipNotAModuloMultiple(uint256 tip, uint256 tipModulo);
    error InvalidTipModulo();

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice  Re-initializes the contract after upgrade
    /// @param   tipModulo_  An amount of ETH that is used as a tip modulo.
    function initializeTestUpgrade(uint256 tipModulo_) public reinitializer(100) {
        setTipModulo(tipModulo_);
    }

    /// @notice  Tips an orb keeper to invoke their orb with a specific content hash
    /// @param   orb             The address of the orb
    /// @param   invocationHash  The invocation content hash
    function tipInvocation(address orb, bytes32 invocationHash) public payable virtual override {
        uint256 _minimumTip = minimumTips[orb];
        if (msg.value < _minimumTip) {
            revert InsufficientTip(msg.value, _minimumTip);
        }
        uint256 _tipModulo = tipModulo;
        if (msg.value % _tipModulo != 0) {
            revert TipNotAModuloMultiple(msg.value, _tipModulo);
        }
        if (claimedInvocations[orb][invocationHash] > 0) {
            revert InvocationAlreadyClaimed();
        }

        totalTips[orb][invocationHash] += msg.value;
        tipperTips[msg.sender][orb][invocationHash] += msg.value;

        emit TipDeposit(orb, invocationHash, msg.sender, msg.value);
    }

    function setTipModulo(uint256 tipModulo_) public virtual onlyOwner {
        if (tipModulo_ == 0) {
            revert InvalidTipModulo();
        }
        uint256 _previousTipModulo = tipModulo;
        tipModulo = tipModulo_;
        emit TipModuloUpdate(_previousTipModulo, tipModulo_);
    }

    /// @notice  Returns the version of the Orb Invocation TipJar. Internal constant `_VERSION` will be increased with
    ///          each upgrade.
    /// @return  orbInvocationTipJarVersion  Version of the Orb Invocation TipJar contract.
    function version() public view virtual override returns (uint256 orbInvocationTipJarVersion) {
        return _VERSION;
    }
}
