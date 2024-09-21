// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {InvocationTipJar} from "../InvocationTipJar.sol";

/// @title  Invocation Tip Jar Test Upgrade
/// @dev    Test Upgrade requires all tips to be multiples of fixed amount of ETH.
contract InvocationTipJarTestUpgrade is InvocationTipJar {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Invocation Tip Jar version.
    uint256 private constant _VERSION = 100;

    /// An amount of ETH that is used as a tip modulo. All tips must be multiples of this amount.
    uint256 public tipModulo;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event TipModuloUpdate(uint256 indexed newTipModulo);

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
    /// @param   orbId           Orb ID
    /// @param   invocationHash  The invocation content hash
    function tip(uint256 orbId, bytes32 invocationHash) public payable virtual override {
        uint256 _minimumTip = minimumTip[orbId];
        if (msg.value < _minimumTip) {
            revert InsufficientTip(msg.value, _minimumTip);
        }
        uint256 _tipModulo = tipModulo;
        if (msg.value % _tipModulo != 0) {
            revert TipNotAModuloMultiple(msg.value, _tipModulo);
        }
        if (claimedInvocations[orbId][invocationHash] > 0) {
            revert InvocationAlreadyClaimed();
        }

        totalTips[orbId][invocationHash] += msg.value;
        tipperTips[orbId][invocationHash][_msgSender()] += msg.value;

        emit Tip(orbId, invocationHash, msg.sender, msg.value);
    }

    function setTipModulo(uint256 tipModulo_) public virtual onlyOwner {
        if (tipModulo_ == 0) {
            revert InvalidTipModulo();
        }
        tipModulo = tipModulo_;
        emit TipModuloUpdate(tipModulo_);
    }

    /// @notice  Returns the version of the Orb Invocation TipJar. Internal constant `_VERSION` will be increased with
    ///          each upgrade.
    /// @return  versionNumber  Version of the Orb Invocation TipJar contract.
    function version() public pure virtual override returns (uint256 versionNumber) {
        return _VERSION;
    }
}
