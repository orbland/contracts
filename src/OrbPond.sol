// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ClonesUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/ClonesUpgradeable.sol";

import {PaymentSplitter} from "./CustomPaymentSplitter.sol";
import {IOwnershipTransferrable} from "./IOwnershipTransferrable.sol";
import {Orb} from "./Orb.sol";

/// @title   Orb Pond - The Orb Factory
/// @author  Jonas Lekevicius
/// @notice  Orbs come from a Pond. The Orb Pond is used to efficiently create new Orbs, and track “official” Orbs,
///          supported by the Orb Land system. The Orb Pond is also used to register allowed Orb upgrade
///          implementations, and keeps a reference to an Orb Invocation Registry used by all Orbs created with this
///          Orb Pond.
/// @dev     Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator and for upgrades.
contract OrbPond is OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event OrbCreation(uint256 indexed orbId, address indexed orbAddress);
    event VersionRegistration(uint256 indexed versionNumber, address indexed implementation);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error InvalidVersion();

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Pond version. Value: 1.
    uint256 private constant _VERSION = 1;

    /// The mapping of Orb ids to Orbs. Increases monotonically.
    mapping(uint256 orbId => address orbAddress) public orbs;
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
    /// The address of the PaymentSplitter implementation contract, used to create new PaymentSplitters.
    address public paymentSplitterImplementation;

    /// Gap used to prevent storage collisions.
    uint256[100] private __gap;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice  Initializes the contract, setting the `owner` and `registry` variables.
    /// @param   registry_                        The address of the Orb Invocation Registry.
    /// @param   paymentSplitterImplementation_   The address of the PaymentSplitter implementation contract.
    function initialize(address registry_, address paymentSplitterImplementation_) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        registry = registry_;
        paymentSplitterImplementation = paymentSplitterImplementation_;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ORB CREATION
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Creates a new Orb together with a PaymentSplitter, and emits an event with the Orb's address.
    /// @param   payees_       Beneficiaries of the Orb's PaymentSplitter.
    /// @param   shares_       Shares of the Orb's PaymentSplitter.
    /// @param   name          Name of the Orb, used for display purposes. Suggestion: "NameOrb".
    /// @param   symbol        Symbol of the Orb, used for display purposes. Suggestion: "ORB".
    /// @param   tokenURI      Initial tokenURI of the Orb, used as part of ERC-721 tokenURI.
    function createOrb(
        address[] memory payees_,
        uint256[] memory shares_,
        string memory name,
        string memory symbol,
        string memory tokenURI
    ) external virtual onlyOwner {
        address beneficiary = ClonesUpgradeable.clone(paymentSplitterImplementation);
        PaymentSplitter(payable(beneficiary)).initialize(payees_, shares_);

        bytes memory initializeCalldata = abi.encodeCall(Orb.initialize, (beneficiary, name, symbol, tokenURI));
        ERC1967Proxy proxy = new ERC1967Proxy(versions[1], initializeCalldata);
        orbs[orbCount] = address(proxy);
        IOwnershipTransferrable(orbs[orbCount]).transferOwnership(msg.sender);

        emit OrbCreation(orbCount, address(proxy));

        orbCount++;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: UPGRADING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Registers a new version of the Orb implementation contract. The version number must be exactly one
    ///          higher than the previous version number, and the implementation address must be non-zero. Versions can
    ///          be un-registered by setting the implementation address to 0; only the latest version can be
    ///          un-registered.
    /// @param   version_          Version number of the new implementation contract.
    /// @param   implementation_   Address of the new implementation contract.
    /// @param   upgradeCalldata_  Initialization calldata to be used for upgrading to the new implementation contract.
    function registerVersion(uint256 version_, address implementation_, bytes calldata upgradeCalldata_)
        external
        virtual
        onlyOwner
    {
        if (version_ < latestVersion && implementation_ == address(0)) {
            revert InvalidVersion();
        }
        if (version_ > latestVersion + 1) {
            revert InvalidVersion();
        }
        versions[version_] = implementation_;
        upgradeCalldata[version_] = upgradeCalldata_;
        if (version_ > latestVersion) {
            latestVersion = version_;
        }
        if (version_ == latestVersion && implementation_ == address(0)) {
            latestVersion--;
        }
        emit VersionRegistration(version_, implementation_);
    }

    /// @notice  Returns the version of the Orb Pond. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbPondVersion  Version of the Orb Pond contract.
    function version() public view virtual returns (uint256 orbPondVersion) {
        return _VERSION;
    }

    /// @dev  Authorizes `owner()` to upgrade this OrbPond contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
