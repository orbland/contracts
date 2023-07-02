// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IOwnershipTransferrable} from "./IOwnershipTransferrable.sol";
import {IOrb} from "./IOrb.sol";

/// @title   Orb Pond - The Orb Factory
/// @author  Jonas Lekevicius
/// @notice  Orbs come from a Pond. The Orb Pond is used to efficiently create new Orbs, and track “official” Orbs,
///          supported by the Orb Land system. The Orb Pond is also used to register allowed Orb upgrade
///          implementations, and keeps a reference to an Orb Invocation Registry used by all Orbs created with this
///          Orb Pond.
/// @dev     Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator and for upgrades.
contract OrbPond is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event OrbCreation(uint256 indexed orbId, address indexed orbAddress);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Pond version. Value: 1.
    uint256 private constant _VERSION = 1;

    /// The mapping of Orb ids to Orbs. Increases monotonically.
    mapping(uint256 => address) public orbs;
    /// The number of Orbs created so far, used to find the next Orb id.
    uint256 public orbCount;

    /// The mapping of version numbers to implementation contract addresses. Looked up by Orbs to find implementation
    /// contracts for upgrades.
    mapping(uint256 versionNumber => address implementation) public versions;
    /// The mapping of version numbers to upgrade calldata. Looked up by Orbs to find initialization calldata for
    /// upgrades.
    mapping(uint256 versionNumber => bytes upgradeCalldata) public upgradeCalldata;
    /// The highest version number so far. Could be used for new Orb creation.
    uint256 public latestVersion;

    /// The address of the Orb Invocation Registry, used to register Orb invocations and responses.
    address public registry;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice  Initializes the contract, setting the `owner` and `registry` variables.
    /// @param   registry_   The address of the Orb Invocation Registry.
    function initialize(address registry_) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        registry = registry_;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ORB CREATION
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Creates a new Orb, and emits an event with the Orb's address.
    /// @param   beneficiary   Address of the Orb's beneficiary. See `Orb` contract for more on beneficiary.
    /// @param   name          Name of the Orb, used for display purposes. Suggestion: "NameOrb".
    /// @param   symbol        Symbol of the Orb, used for display purposes. Suggestion: "ORB".
    /// @param   tokenURI      Initial tokenURI of the Orb, used as part of ERC-721 tokenURI.
    function createOrb(address beneficiary, string memory name, string memory symbol, string memory tokenURI)
        external
        virtual
        onlyOwner
    {
        bytes memory initializeCalldata =
            abi.encodeWithSelector(IOrb.initialize.selector, beneficiary, name, symbol, tokenURI);
        ERC1967Proxy proxy = new ERC1967Proxy(versions[1], initializeCalldata);
        orbs[orbCount] = address(proxy);
        IOwnershipTransferrable(orbs[orbCount]).transferOwnership(msg.sender);

        emit OrbCreation(orbCount, address(proxy));

        orbCount++;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: UPGRADING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Registers a new version of the Orb implementation contract.
    /// @param   version_          Version number of the new implementation contract.
    /// @param   implementation_   Address of the new implementation contract.
    /// @param   upgradeCalldata_  Initialization calldata to be used for upgrading to the new implementation contract.
    function registerVersion(uint256 version_, address implementation_, bytes calldata upgradeCalldata_)
        external
        virtual
        onlyOwner
    {
        versions[version_] = implementation_;
        upgradeCalldata[version_] = upgradeCalldata_;
        if (version_ > latestVersion) {
            latestVersion = version_;
        }
    }

    /// @notice  Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbPondVersion  Version of the Orb Pond contract.
    function version() public virtual returns (uint256 orbPondVersion) {
        return _VERSION;
    }

    /// @dev  Authorizes `owner()` to upgrade this OrbPond contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
