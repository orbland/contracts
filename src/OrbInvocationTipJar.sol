// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AddressUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol";

import {IOrb} from "./IOrb.sol";
import {IOrbInvocationRegistry} from "./IOrbInvocationRegistry.sol";
import {OrbPond} from "./OrbPond.sol";

/// @title   Orb Invocation Tip Jar - A contract for suggesting Orb invocations and tipping Orb keepers
/// @author  Jonas Lekevicius
/// @author  Oren Yomtov
/// @notice  This contract allows anyone to suggest an invocation to an Orb and optionally tip the Orb keeper.
contract OrbInvocationTipJar is OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Invocation Tip Jar version
    uint256 private constant _VERSION = 1;
    /// Fee Nominator: basis points (100.00%). Platform fee is in relation to this.
    uint256 internal constant _FEE_DENOMINATOR = 100_00;

    /// The invocation cleartext string for a given invocation hash
    mapping(bytes32 invocationHash => string invocationCleartext) public suggestedInvocations;

    /// The sum of all tips for a given invocation
    mapping(address orb => mapping(bytes32 invocationHash => uint256 tippedAmount)) public totalTips;

    /// The sum of all tips for a given invocation by a given tipper
    mapping(address orb => mapping(address tipper => mapping(bytes32 invocationHash => uint256 tippedAmount))) public
        tipperTips;

    /// Whether a certain invocation's tips have been claimed
    mapping(address orb => mapping(bytes32 invocationHash => bool isClaimed)) public claimedInvocations;

    /// The minimum tip value for a given Orb
    mapping(address orb => uint256 minimumTip) public minimumTips;

    /// Orb Land revenue address
    address public platformAddress;

    /// Orb Land revenue fee numerator
    uint256 public platformFee;

    /// Funds allocated for the Orb Land platform, withdrawable to `platformAddress`
    uint256 public platformFunds;

    /// Gap used to prevent storage collisions
    uint256[100] private __gap;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event InvocationSuggestion(
        address indexed orb, bytes32 indexed invocationHash, address indexed suggester, string invocationCleartext
    );
    event TipDeposit(address indexed orb, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);
    event TipWithdrawal(address indexed orb, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);
    event TipsClaim(address indexed orb, bytes32 indexed invocationHash, address indexed invoker, uint256 tipsValue);
    event MinimumTipUpdate(address indexed orb, uint256 previousMinimumTip, uint256 indexed newMinimumTip);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error InvocationAlreadySuggested();
    error CleartextTooLong(uint256 cleartextLength, uint256 cleartextMaximumLength);
    error InsufficientTip(uint256 tipValue, uint256 minimumTip);
    error InvocationNotFound();
    error InvocationNotInvoked();
    error InvocationAlreadyClaimed();
    error InsufficientTips(uint256 minimumTipTotal, uint256 totalClaimableTips);
    error TipNotFound();
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
        __Ownable_init();
        __UUPSUpgradeable_init();

        platformAddress = platformAddress_;
        platformFee = platformFee_;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOCATION SUBMISSION & TIPPING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Records invocation cleartext for a given invocation hash, allowing it to be tipped. If any value is
    ///          given, it is recorded as initial tip.
    /// @param   orb                  The address of the Orb for which the invocation is being suggested
    /// @param   invocationCleartext  The invocation's cleartext
    function suggestInvocation(address orb, string memory invocationCleartext) external payable virtual {
        bytes32 invocationHash = keccak256(abi.encodePacked(invocationCleartext));

        if (bytes(suggestedInvocations[invocationHash]).length != 0) {
            revert InvocationAlreadySuggested();
        }
        if (bytes(invocationCleartext).length > IOrb(orb).cleartextMaximumLength()) {
            revert CleartextTooLong(bytes(invocationCleartext).length, IOrb(orb).cleartextMaximumLength());
        }

        suggestedInvocations[invocationHash] = invocationCleartext;

        emit InvocationSuggestion(orb, invocationHash, msg.sender, invocationCleartext);

        if (msg.value > 0) {
            tipInvocation(orb, invocationHash);
        }
    }

    /// @notice  Tips a specific invocation content hash on an Orb. Any Keeper can invoke the tipped invocation and
    ///          claim the tips.
    /// @param   orb             The address of the orb
    /// @param   invocationHash  The invocation content hash
    function tipInvocation(address orb, bytes32 invocationHash) public payable virtual {
        uint256 _minimumTip = minimumTips[orb];
        if (msg.value < _minimumTip) {
            revert InsufficientTip(msg.value, _minimumTip);
        }
        if (bytes(suggestedInvocations[invocationHash]).length == 0) {
            revert InvocationNotFound();
        }
        if (claimedInvocations[orb][invocationHash]) {
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
        address pondAddress = IOrb(orb).pond();
        address invocationRegistryAddress = OrbPond(pondAddress).registry();
        (address invoker, bytes32 contentHash,) =
            IOrbInvocationRegistry(invocationRegistryAddress).invocations(orb, invocationIndex);

        if (contentHash == bytes32(0)) {
            revert InvocationNotInvoked();
        }
        if (claimedInvocations[orb][contentHash]) {
            revert InvocationAlreadyClaimed();
        }
        uint256 totalClaimableTips = totalTips[orb][contentHash];
        if (totalClaimableTips < minimumTipTotal) {
            revert InsufficientTips(minimumTipTotal, totalClaimableTips);
        }

        uint256 platformPortion = (totalClaimableTips * platformFee) / _FEE_DENOMINATOR;
        uint256 invokerPortion = totalClaimableTips - platformPortion;

        claimedInvocations[orb][contentHash] = true;
        platformFunds += platformPortion;
        AddressUpgradeable.sendValue(payable(invoker), invokerPortion);

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
        if (claimedInvocations[orb][invocationHash]) {
            revert InvocationAlreadyClaimed();
        }

        totalTips[orb][invocationHash] -= tipValue;
        tipperTips[msg.sender][orb][invocationHash] = 0;
        AddressUpgradeable.sendValue(payable(msg.sender), tipValue);

        emit TipWithdrawal(orb, invocationHash, msg.sender, tipValue);
    }

    /// @notice  Withdraws all tips from a given list of Orbs and invocations. Will revert if any given invocation has
    ///          been claimed.
    /// @param   orbs              Array of orb addresse
    /// @param   invocationHashes  Array of invocation content hashes
    function withdrawTips(address[] memory orbs, bytes32[] memory invocationHashes) external virtual {
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
        AddressUpgradeable.sendValue(payable(_platformAddress), _platformFunds);
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
        if (msg.sender != IOrb(orb).keeper()) {
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
