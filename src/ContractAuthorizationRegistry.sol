// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

contract ContractAuthorizationRegistry is OwnableUpgradeable, UUPSUpgradeable {
    /// Orb Invocation Registry version. Value: 1.
    uint256 private constant _VERSION = 1;

    // AllocationContractAuthorization - checked by Orbs
    event AllocationContractAuthorization(address indexed contractAddress, bool indexed authorized);
    // InvocationCallableContractAuthorization - checked by Invocation Registry
    event InvocationCallableContractAuthorization(address indexed contractAddress, bool indexed authorized);
    // DelegationContractAuthorization - checked by Invocation Registry
    event DelegationContractAuthorization(address indexed contractAddress, bool indexed authorized);

    address public orbsContract;
    address public invocationRegistryContract;
    address public pledgeLockerContract;
    address public invocationTipJarContract;

    /// Addresses authorized for external calls in invokeWithXAndCall()
    mapping(address contractAddress => bool) public invocationCallableContracts;
    mapping(address contractAddress => bool) public allocationContracts;
    mapping(address contractAddress => bool) public delegationContracts;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev  Initializes the contract.
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    /// @notice  Allows the owner address to authorize externally callable contracts.
    /// @param   addressToAuthorize  Address of the contract to authorize.
    /// @param   authorizationValue  Boolean value to set the authorization to.
    function authorizeInvocationCallableContract(address addressToAuthorize, bool authorizationValue)
        external
        virtual
        onlyOwner
    {
        invocationCallableContracts[addressToAuthorize] = authorizationValue;
        emit InvocationCallableContractAuthorization(addressToAuthorize, authorizationValue);
    }

    /// @notice  Allows the owner address to authorize allocation contracts.
    /// @param   addressToAuthorize  Address of the contract to authorize.
    /// @param   authorizationValue  Boolean value to set the authorization to.
    function authorizeAllocationContract(address addressToAuthorize, bool authorizationValue)
        external
        virtual
        onlyOwner
    {
        allocationContracts[addressToAuthorize] = authorizationValue;
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
        delegationContracts[addressToAuthorize] = authorizationValue;
        emit DelegationContractAuthorization(addressToAuthorize, authorizationValue);
    }

    /// @notice  Allows the owner address to set the contract addresses.
    /// @param   orbsContractAddress  Address of the Orbs contract.
    /// @param   invocationRegistryContractAddress  Address of the Invocation Registry contract.
    /// @param   pledgeLockerContractAddress  Address of the Pledge Locker contract.
    /// @param   invocationTipJarContractAddress  Address of the Invocation Tip Jar contract.
    function setContractAddresses(
        address orbsContractAddress,
        address invocationRegistryContractAddress,
        address pledgeLockerContractAddress,
        address invocationTipJarContractAddress
    ) external onlyOwner {
        orbsContract = orbsContractAddress;
        invocationRegistryContract = invocationRegistryContractAddress;
        pledgeLockerContract = pledgeLockerContractAddress;
        invocationTipJarContract = invocationTipJarContractAddress;
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
