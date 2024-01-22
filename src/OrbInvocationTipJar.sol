// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

import {Orb} from "./Orb.sol";
import {OrbInvocationRegistry} from "./OrbInvocationRegistry.sol";
import {OrbPond} from "./OrbPond.sol";

/// @title   Orb Invocation Tip Jar - A contract for suggesting Orb invocations and tipping Orb keepers
/// @author  Jonas Lekevicius
/// @author  Oren Yomtov
/// @notice  This contract allows anyone to suggest an invocation to an Orb and optionally tip the Orb keeper.
/// @custom:security-contact security@orb.land
contract OrbInvocationTipJar is OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Invocation Tip Jar version
    uint256 private constant _VERSION = 1;
    /// Fee Nominator: basis points (100.00%). Platform fee is in relation to this.
    uint256 internal constant _FEE_DENOMINATOR = 100_00;

    /// The sum of all tips for a given invocation
    mapping(address orb => mapping(bytes32 invocationHash => uint256 tippedAmount)) public totalTips;

    /// The sum of all tips for a given invocation by a given tipper
    mapping(address orb => mapping(address tipper => mapping(bytes32 invocationHash => uint256 tippedAmount))) public
        tipperTips;

    /// Whether a certain invocation's tips have been claimed: invocationId starts from 1
    mapping(address orb => mapping(bytes32 invocationHash => uint256 invocationId)) public claimedInvocations;

    /// The minimum tip value for a given Orb
    mapping(address orb => uint256 minimumTip) public minimumTips;

    /// Orb Land revenue address. Set during contract initialization to Orb Land Revenue multisig. While there is no
    /// function to change this address, it can be changed by upgrading the contract.
    address public platformAddress;

    /// Orb Land revenue fee numerator. Set during contract initialization. While there is no function to change this
    /// value, it can be changed by upgrading the contract. The fee is in relation to `_FEE_DENOMINATOR`.
    /// Note: contract upgradability poses risks! Orb Land may upgrade this contract and set the fee to _FEE_DENOMINATOR
    /// (100.00%), taking away all future tips. This is a risk that Orb keepers must be aware of, until upgradability
    /// is removed or modified.
    uint256 public platformFee;

    /// Funds allocated for the Orb Land platform, withdrawable to `platformAddress`
    uint256 public platformFunds;

    /// Gap used to prevent storage collisions
    uint256[100] private __gap;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event TipDeposit(address indexed orb, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);
    event TipWithdrawal(address indexed orb, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);
    event TipsClaim(address indexed orb, bytes32 indexed invocationHash, address indexed invoker, uint256 tipsValue);
    event MinimumTipUpdate(address indexed orb, uint256 previousMinimumTip, uint256 indexed newMinimumTip);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error PlatformAddressInvalid();
    error PlatformFeeInvalid();
    error InsufficientTip(uint256 tipValue, uint256 minimumTip);
    error InvocationNotInvoked();
    error InvocationAlreadyClaimed();
    error InsufficientTips(uint256 minimumTipTotal, uint256 totalClaimableTips);
    error TipNotFound();
    error UnevenArrayLengths();
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
    function initialize(address platformAddress_, uint256 platformFee_) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        if (platformAddress_ == address(0)) {
            revert PlatformAddressInvalid();
        }
        if (platformFee_ > _FEE_DENOMINATOR) {
            revert PlatformFeeInvalid();
        }

        platformAddress = platformAddress_;
        platformFee = platformFee_;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOCATION SUBMISSION & TIPPING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Tips a specific invocation content hash on an Orb. Any Keeper can invoke the tipped invocation and
    ///          claim the tips.
    /// @param   orb             The address of the orb
    /// @param   invocationHash  The invocation content hash
    function tipInvocation(address orb, bytes32 invocationHash) external payable virtual {
        uint256 _minimumTip = minimumTips[orb];
        if (msg.value < _minimumTip) {
            revert InsufficientTip(msg.value, _minimumTip);
        }
        if (claimedInvocations[orb][invocationHash] > 0) {
            revert InvocationAlreadyClaimed();
        }

        totalTips[orb][invocationHash] += msg.value;
        tipperTips[msg.sender][orb][invocationHash] += msg.value;

        emit TipDeposit(orb, invocationHash, msg.sender, msg.value);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: CLAIMING & WITHDRAWING TIPS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Claims all tips for a given suggested invocation. Meant to be called together with the invocation
    ///          itself, using `invokeWith*AndCall` functions on OrbInvocationRegistry.
    /// @param   orb              The address of the Orb
    /// @param   invocationIndex  The invocation id to check
    /// @param   minimumTipTotal  The minimum tip value to claim (reverts if the total tips are less than this value)
    function claimTipsForInvocation(address orb, uint256 invocationIndex, uint256 minimumTipTotal) external virtual {
        address pondAddress = Orb(orb).pond();
        address invocationRegistryAddress = OrbPond(pondAddress).registry();
        (address invoker, bytes32 contentHash,) =
            OrbInvocationRegistry(invocationRegistryAddress).invocations(orb, invocationIndex);

        if (contentHash == bytes32(0)) {
            revert InvocationNotInvoked();
        }
        if (claimedInvocations[orb][contentHash] > 0) {
            revert InvocationAlreadyClaimed();
        }
        uint256 totalClaimableTips = totalTips[orb][contentHash];
        if (totalClaimableTips < minimumTipTotal) {
            revert InsufficientTips(minimumTipTotal, totalClaimableTips);
        }

        uint256 platformPortion = (totalClaimableTips * platformFee) / _FEE_DENOMINATOR;
        uint256 invokerPortion = totalClaimableTips - platformPortion;

        claimedInvocations[orb][contentHash] = invocationIndex;
        platformFunds += platformPortion;
        Address.sendValue(payable(invoker), invokerPortion);

        emit TipsClaim(orb, contentHash, invoker, invokerPortion);
    }

    /// @notice  Withdraws a tip from a given invocation. Not possible if invocation has been claimed.
    /// @param   orb             The address of the orb
    /// @param   invocationHash  The invocation content hash
    function withdrawTip(address orb, bytes32 invocationHash) public virtual {
        uint256 tipValue = tipperTips[msg.sender][orb][invocationHash];
        if (tipValue == 0) {
            revert TipNotFound();
        }
        if (claimedInvocations[orb][invocationHash] > 0) {
            revert InvocationAlreadyClaimed();
        }

        totalTips[orb][invocationHash] -= tipValue;
        tipperTips[msg.sender][orb][invocationHash] = 0;
        Address.sendValue(payable(msg.sender), tipValue);

        emit TipWithdrawal(orb, invocationHash, msg.sender, tipValue);
    }

    /// @notice  Withdraws all tips from a given list of Orbs and invocations. Will revert if any given invocation has
    ///          been claimed.
    /// @param   orbs              Array of orb addresse
    /// @param   invocationHashes  Array of invocation content hashes
    function withdrawTips(address[] memory orbs, bytes32[] memory invocationHashes) external virtual {
        if (orbs.length != invocationHashes.length) {
            revert UnevenArrayLengths();
        }
        for (uint256 index = 0; index < orbs.length; index++) {
            withdrawTip(orbs[index], invocationHashes[index]);
        }
    }

    /// @notice  Withdraws all funds set aside as the platform fee. Can be called by anyone.
    function withdrawPlatformFunds() external virtual {
        uint256 _platformFunds = platformFunds;
        address _platformAddress = platformAddress;
        if (_platformFunds == 0) {
            revert NoFundsAvailable();
        }
        Address.sendValue(payable(_platformAddress), _platformFunds);
        platformFunds = 0;
        emit TipsClaim(address(0), bytes32(0), _platformAddress, _platformFunds);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: SETTINGS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Sets the minimum tip value for a given Orb.
    /// @param   orb              The address of the Orb
    /// @param   minimumTipValue  The minimum tip value
    function setMinimumTip(address orb, uint256 minimumTipValue) external virtual {
        if (msg.sender != Orb(orb).keeper()) {
            revert NotKeeper();
        }
        uint256 previousMinimumTip = minimumTips[orb];
        minimumTips[orb] = minimumTipValue;
        emit MinimumTipUpdate(orb, previousMinimumTip, minimumTipValue);
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
}
