// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnershipRegistry} from "./OwnershipRegistry.sol";
import {InvocationRegistry} from "./InvocationRegistry.sol";
import {PledgeLocker} from "./PledgeLocker.sol";
import {InvocationTipJar} from "./InvocationTipJar.sol";
import {InvocationAccessVendor} from "./InvocationAccessVendor.sol";

import {IAllocationMethod} from "./allocation/IAllocationMethod.sol";

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract OrbSystem is OwnableUpgradeable, UUPSUpgradeable {
    event AllocationContractAuthorization(address indexed contractAddress, bool indexed authorized);
    event DelegationContractAuthorization(address indexed contractAddress, bool indexed authorized);
    event EarningsWithdrawalAddressUpdate(address indexed userAddress, address indexed withdrawalAddress);

    /// Orb Invocation Registry version. Value: 1.
    uint256 private constant _VERSION = 1;

    /// Fee Nominator: basis points (100.00%). All fees are in relation to this.
    uint256 internal constant _FEE_DENOMINATOR = 100_00;
    /// Platform fee in bips
    uint256 internal constant _PLATFORM_FEE = 5_00;

    /// Address of Ownership Registry contract
    address public ownershipRegistryAddress;
    /// Address of Invocation Registry contract
    address public invocationRegistryAddress;
    /// Address of Pledge Locker contract
    address public pledgeLockerAddress;
    /// Address of Invocation Tip Jar contract
    address public invocationTipJarAddress;
    /// Address of Invocation Access Vendor contract
    address public invocationAccessVendorAddress;

    /// Address of platform signing authority for authorized actions
    address public platformSignerAddress;

    /// Addresses authorized to be set as allocation contracts on Ownership Registry contract
    mapping(address contractAddress => bool) public allocationContractAuthorized;
    /// Addresses authorized to be set as delegation contracts on Invocation Registry contract
    mapping(address contractAddress => bool) public delegationContractAuthorized;

    /// Earnings withdrawal redirect, used by all contracts in the system
    mapping(address userAddress => address withdrawalAddress) public earningsWithdrawalAddress;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev  Initializes the contract.
    function initialize() public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
    }

    /// @notice  Allows the owner address to set the contract addresses.
    /// @param   ownershipRegistryAddress_  Address of the Ownership Registry contract.
    /// @param   invocationRegistryAddress_  Address of the Invocation Registry contract.
    /// @param   pledgeLockerAddress_  Address of the Pledge Locker contract.
    /// @param   invocationTipJarAddress_  Address of the Invocation Tip Jar contract.
    /// @param   invocationAccessVendorAddress_  Address of the Invocation Access Vendor contract.
    function setAddresses(
        address ownershipRegistryAddress_,
        address invocationRegistryAddress_,
        address pledgeLockerAddress_,
        address invocationTipJarAddress_,
        address invocationAccessVendorAddress_
    ) external onlyOwner {
        ownershipRegistryAddress = ownershipRegistryAddress_;
        invocationRegistryAddress = invocationRegistryAddress_;
        pledgeLockerAddress = pledgeLockerAddress_;
        invocationTipJarAddress = invocationTipJarAddress_;
        invocationAccessVendorAddress = invocationAccessVendorAddress_;
    }

    function ownership() public view returns (OwnershipRegistry) {
        return OwnershipRegistry(ownershipRegistryAddress);
    }

    function invocations() public view returns (InvocationRegistry) {
        return InvocationRegistry(invocationRegistryAddress);
    }

    function pledges() public view returns (PledgeLocker) {
        return PledgeLocker(pledgeLockerAddress);
    }

    function tips() public view returns (InvocationTipJar) {
        return InvocationTipJar(invocationTipJarAddress);
    }

    function accessVendor() public view returns (InvocationAccessVendor) {
        return InvocationAccessVendor(invocationAccessVendorAddress);
    }

    function feeDenominator() public pure returns (uint256) {
        return _FEE_DENOMINATOR;
    }

    function platformFee() public pure returns (uint256) {
        return _PLATFORM_FEE;
    }

    function setEarningsWithdrawalAddress(address withdrawalAddress_) external {
        earningsWithdrawalAddress[_msgSender()] = withdrawalAddress_;
        emit EarningsWithdrawalAddressUpdate(_msgSender(), withdrawalAddress_);
    }

    function setPlatformProperties(address platformSignerAddress_, address platformRevenueWalletAddress_)
        external
        onlyOwner
    {
        platformSignerAddress = platformSignerAddress_;
        earningsWithdrawalAddress[address(0)] = platformRevenueWalletAddress_;
    }

    /// @notice  Allows the owner address to authorize allocation contracts.
    /// @param   addressToAuthorize  Address of the contract to authorize.
    /// @param   authorizationValue  Boolean value to set the authorization to.
    function authorizeAllocationContract(address addressToAuthorize, bool authorizationValue)
        external
        virtual
        onlyOwner
    {
        allocationContractAuthorized[addressToAuthorize] = authorizationValue;
        emit AllocationContractAuthorization(addressToAuthorize, authorizationValue);
    }

    /// @notice  Allows the owner address to authorize delegation contracts.
    /// @param   addressToAuthorize  Address of the contract to authorize.
    /// @param   authorizationValue  Boolean value to set the authorization to.
    function authorizeDelegationContract(address addressToAuthorize, bool authorizationValue)
        external
        virtual
        onlyOwner
    {
        delegationContractAuthorized[addressToAuthorize] = authorizationValue;
        emit DelegationContractAuthorization(addressToAuthorize, authorizationValue);
    }

    /// @dev  Ensures that the Orb belongs to the contract itself or the creator, and the auction hasn't been started.
    ///       Most setting-adjusting functions should use this modifier. It means that the Orb properties cannot be
    ///       modified while it is held by the keeper or users can bid on the Orb.
    ///       V2 changes to allow setting parameters even during Keeper control, if Oath has expired.
    function isCreatorControlled(uint256 orbId) public view virtual returns (bool) {
        address _pledgeLockerAddress = pledgeLockerAddress;
        PledgeLocker _pledges = PledgeLocker(_pledgeLockerAddress);

        // NO, if pledge is claimable
        if (_pledges.hasClaimablePledge(orbId)) {
            return false;
        }

        address _ownershipRegistryAddress = ownershipRegistryAddress;
        OwnershipRegistry _ownership = OwnershipRegistry(_ownershipRegistryAddress);
        address reallocationContract = _ownership.reallocationContract(orbId);

        // NO, if allocation is active
        if (
            IAllocationMethod(_ownership.allocationContract(orbId)).isActive(orbId)
                || (reallocationContract != address(0) && IAllocationMethod(reallocationContract).isActive(orbId))
        ) {
            return false;
        }

        // YES, if Orb belongs to Ownership Registry contract or Creator
        if (
            _ownershipRegistryAddress == _ownership.keeper(orbId)
                || _ownership.creator(orbId) == _ownership.keeper(orbId)
        ) {
            return true;
        }

        // Below: Orb belongs to a Keeper:

        uint256 _pledgedUntil = _pledges.pledgedUntil(orbId);

        // YES, if “pledged until” was set and has expired
        if (_pledgedUntil > 0 && _pledgedUntil < block.timestamp) {
            return true;
        }

        address _invocationRegistryAddress = invocationRegistryAddress;
        InvocationRegistry _invocations = InvocationRegistry(_invocationRegistryAddress);

        // YES, if there’s a late response
        if (_invocations.hasLateResponse(orbId)) {
            return true;
        }

        // NO otherwise
        return false;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: UPGRADING AND MANAGEMENT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Returns the version of the Orb Invocation Registry. Internal constant `_VERSION` will be increased with
    ///          each upgrade.
    /// @return  orbInvocationRegistryVersion  Version of the Orb Invocation Registry contract.
    function version() public view virtual returns (uint256 orbInvocationRegistryVersion) {
        return _VERSION;
    }

    /// @dev  Authorizes owner address to upgrade the contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
