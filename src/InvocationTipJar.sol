// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Earnable} from "./Earnable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {OrbSystem} from "./OrbSystem.sol";
import {OwnershipRegistry} from "./OwnershipRegistry.sol";
import {InvocationRegistry} from "./InvocationRegistry.sol";

/// @title   Orb Invocation Tip Jar - A contract for suggesting Orb invocations and tipping Orb keepers
/// @author  Jonas Lekevicius
/// @author  Oren Yomtov
/// @notice  This contract allows anyone to suggest an invocation to an Orb and optionally tip the Orb keeper.
/// @custom:security-contact security@orb.land
contract InvocationTipJar is Earnable, OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Invocation Tip Jar version
    uint256 private constant _VERSION = 1;

    /// The sum of all tips for a given invocation
    mapping(uint256 orbId => mapping(bytes32 invocationHash => uint256)) public totalTips;

    /// The sum of all tips for a given invocation by a given tipper
    mapping(uint256 orbId => mapping(bytes32 invocationHash => mapping(address tipper => uint256))) public tipperTips;

    /// Whether a certain invocation's tips have been claimed: invocationId starts from 1
    mapping(uint256 orbId => mapping(bytes32 invocationHash => uint256 invocationId)) public claimedInvocations;

    /// The minimum tip value for a given Orb
    mapping(uint256 orbId => uint256) public minimumTip;

    /// Addresses of all system contracts
    OrbSystem public orbSystem;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event Tip(uint256 indexed orbId, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);
    event Withdrawal(uint256 indexed orbId, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);
    event Claim(uint256 indexed orbId, bytes32 indexed invocationHash, address indexed invoker, uint256 tipsValue);
    event MinimumTipUpdate(uint256 indexed orbId, uint256 indexed newMinimumTip);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error InsufficientTip(uint256 tipValue, uint256 minimumTip);
    error InvocationNotInvoked();
    error InvocationAlreadyClaimed();
    error InsufficientTips(uint256 totalClaimableTips, uint256 minimumTipTotal);
    error TipNotFound();
    error UnevenLengths();
    error NoFundsAvailable();
    error NotKeeper();

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev  Initializes the contract.
    function initialize(address os_) public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();

        orbSystem = OrbSystem(os_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOCATION SUBMISSION & TIPPING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Tips a specific invocation content hash on an Orb. Any Keeper can invoke the tipped invocation and
    ///          claim the tips.
    /// @param   orbId             The address of the orb
    /// @param   invocationHash  The invocation content hash
    function tip(uint256 orbId, bytes32 invocationHash) external payable virtual {
        uint256 _minimumTip = minimumTip[orbId];
        if (msg.value < _minimumTip) {
            revert InsufficientTip(msg.value, _minimumTip);
        }
        if (claimedInvocations[orbId][invocationHash] > 0) {
            revert InvocationAlreadyClaimed();
        }

        tipperTips[orbId][invocationHash][_msgSender()] += msg.value;
        totalTips[orbId][invocationHash] += msg.value;

        emit Tip(orbId, invocationHash, _msgSender(), msg.value);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: CLAIMING & WITHDRAWING TIPS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Claims all tips for a given suggested invocation. Meant to be called together with the invocation
    ///          itself, using `invokeWithHashAndCall` functions on InvocationRegistry.
    /// @param   orbId            The address of the Orb
    /// @param   invocationId     The invocation id to check
    /// @param   minimumTipTotal  The minimum tip value to claim (reverts if the total tips are less than this value)
    function claim(uint256 orbId, uint256 invocationId, uint256 minimumTipTotal) external virtual {
        (address invoker, bytes32 contentHash,) =
            InvocationRegistry(orbSystem.invocationRegistryAddress()).invocations(orbId, invocationId);

        if (contentHash == bytes32(0)) {
            revert InvocationNotInvoked();
        }
        if (claimedInvocations[orbId][contentHash] > 0) {
            revert InvocationAlreadyClaimed();
        }
        uint256 totalClaimableTips = totalTips[orbId][contentHash];
        if (totalClaimableTips < minimumTipTotal) {
            revert InsufficientTips(totalClaimableTips, minimumTipTotal);
        }

        claimedInvocations[orbId][contentHash] = invocationId;
        _addEarnings(invoker, totalClaimableTips);

        emit Claim(orbId, contentHash, invoker, totalClaimableTips);
    }

    /// @notice  Withdraws a tip from a given invocation. Not possible if invocation has been claimed.
    /// @param   orbId             The address of the orb
    /// @param   invocationHash  The invocation content hash
    function withdrawAll(uint256 orbId, bytes32 invocationHash) external virtual {
        _withdrawAll(_msgSender(), orbId, invocationHash);
    }

    /// @notice  Withdraws all tips from a given list of Orbs and invocations. Will revert if any given invocation has
    ///          been claimed.
    /// @param   orbIds              Array of orb addresse
    /// @param   invocationHashes  Array of invocation content hashes
    function withdrawAllFor(uint256[] memory orbIds, bytes32[] memory invocationHashes) external virtual {
        if (orbIds.length != invocationHashes.length) {
            revert UnevenLengths();
        }
        for (uint256 index = 0; index < orbIds.length; index++) {
            _withdrawAll(_msgSender(), orbIds[index], invocationHashes[index]);
        }
    }

    function _withdrawAll(address user, uint256 orbId, bytes32 invocationHash) public virtual {
        uint256 tipValue = tipperTips[orbId][invocationHash][user];
        if (tipValue == 0) {
            revert TipNotFound();
        }
        if (claimedInvocations[orbId][invocationHash] > 0) {
            revert InvocationAlreadyClaimed();
        }

        totalTips[orbId][invocationHash] -= tipValue;
        tipperTips[orbId][invocationHash][user] = 0;
        Address.sendValue(payable(user), tipValue);

        emit Withdrawal(orbId, invocationHash, user, tipValue);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: SETTINGS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Sets the minimum tip value for a given Orb.
    /// @param   orbId              The address of the Orb
    /// @param   minimumTip_  The minimum tip value
    function setMinimumTip(uint256 orbId, uint256 minimumTip_) external virtual {
        if (_msgSender() != OwnershipRegistry(orbSystem.ownershipRegistryAddress()).keeper(orbId)) {
            revert NotKeeper();
        }
        minimumTip[orbId] = minimumTip_;
        emit MinimumTipUpdate(orbId, minimumTip_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: UPGRADING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Returns the version of the Orb Invocation Tip Jar. Internal constant `_VERSION` will be increased with
    ///          each upgrade.
    /// @return  orbInvocationTipJarVersion  Version of the Orb Invocation Tip Jar contract.
    function version() public view virtual returns (uint256 orbInvocationTipJarVersion) {
        return _VERSION;
    }

    /// @dev  Authorizes owner address to upgrade the contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function _earningsWithdrawalAddress(address user) internal virtual override returns (address) {
        return orbSystem.earningsWithdrawalAddress(user);
    }
}
