// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Earnable} from "./Earnable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {OrbSystem} from "./OrbSystem.sol";
import {OwnershipRegistry} from "./OwnershipRegistry.sol";
import {HarbergerTaxKeepership} from "./HarbergerTaxKeepership.sol";
import {InvocationRegistry} from "./InvocationRegistry.sol";

/// @title   Orb Invocation Access Vendor
/// @author  Jonas Lekevicius
/// @notice  This contract allows anyone to purchase private invocation reading access at a price set by the Keeper.
/// @custom:security-contact security@orb.land
contract InvocationAccessVendor is Earnable, OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Invocation Tip Jar version
    uint256 private constant _VERSION = 1;

    /// The sum of all tips for a given invocation
    mapping(uint256 orbId => mapping(uint256 invocationId => uint256)) public price;

    /// The sum of all tips for a given invocation
    mapping(uint256 orbId => mapping(uint256 invocationId => mapping(address purchaser => uint256 timestamp))) public
        accessPurchased;

    /// Addresses of all system contracts
    OrbSystem public orbSystem;
    OwnershipRegistry public ownership;
    HarbergerTaxKeepership public keepership;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event AccessPurchase(
        uint256 indexed orbId, uint256 indexed invocationId, address indexed purchaser, uint256 sentValue
    );
    event PriceUpdate(uint256 indexed orbId, uint256 indexed invocationId, uint256 indexed newPrice);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error InsufficientAmount(uint256 sentValue, uint256 invocationPrice);
    error AlreadyPurchased();
    error ResponseDoesNotExist();
    error PriceNotSet();
    error NotKeeper();
    error NotOwnedBySolventKeeper();

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

    function setSystemContracts() external {
        ownership = OwnershipRegistry(orbSystem.ownershipRegistryAddress());
        keepership = HarbergerTaxKeepership(orbSystem.harbergerTaxKeepershipAddress());
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Tips a specific invocation content hash on an Orb. Any Keeper can invoke the tipped invocation and
    ///          claim the tips.
    /// @param   orbId         The address of the orb
    /// @param   invocationId  The invocation id
    function purchase(uint256 orbId, uint256 invocationId) external payable virtual {
        uint256 _price = price[orbId][invocationId];
        if (_price == 0) {
            revert PriceNotSet();
        }
        if (msg.value < _price) {
            revert InsufficientAmount(msg.value, _price);
        }
        if (accessPurchased[orbId][invocationId][_msgSender()] > 0) {
            revert AlreadyPurchased();
        }
        (, uint256 responseTimestamp) =
            InvocationRegistry(orbSystem.invocationRegistryAddress()).responses(orbId, invocationId);
        if (responseTimestamp == 0) {
            revert ResponseDoesNotExist();
        }
        if (ownership.keeper(orbId) == orbSystem.ownershipRegistryAddress()) {
            revert NotOwnedBySolventKeeper();
        }
        if (!keepership.keeperSolvent(orbId)) {
            revert NotOwnedBySolventKeeper();
        }

        _addEarnings(ownership.keeper(orbId), msg.value);
        accessPurchased[orbId][invocationId][_msgSender()] = block.timestamp;

        emit AccessPurchase(orbId, invocationId, _msgSender(), msg.value);
    }

    /// @notice  Sets the minimum tip value for a given Orb.
    /// @param   orbId         The address of the Orb
    /// @param   invocationId  The invocation id
    /// @param   price_        New price for the invocation
    function setPrice(uint256 orbId, uint256 invocationId, uint256 price_) external virtual {
        if (_msgSender() != ownership.keeper(orbId) || !keepership.keeperSolvent(orbId)) {
            revert NotKeeper();
        }
        price[orbId][invocationId] = price_;
        emit PriceUpdate(orbId, invocationId, price_);
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
