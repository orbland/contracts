// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC1967Proxy} from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ClonesUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/ClonesUpgradeable.sol";

import {PaymentSplitter} from "../CustomPaymentSplitter.sol";
import {IOwnershipTransferrable} from "../IOwnershipTransferrable.sol";
import {Orb} from "../Orb.sol";
import {OrbPond} from "../OrbPond.sol";

/// @title   Orb Pond - The Orb Factory
/// @author  Jonas Lekevicius
/// @notice  Orbs come from a Pond. The Orb Pond is used to efficiently create new Orbs, and track “official” Orbs,
///          supported by the Orb Land system. The Orb Pond is also used to register allowed Orb upgrade
///          implementations, and keeps a reference to an Orb Invocation Registry used by all Orbs created with this
///          Orb Pond.
/// @dev     Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator and for upgrades.
///          Test Upgrade allows anyone to create orbs, not just the owner, automatically splitting proceeds between the
///          creator and the Orb Land wallet.
contract OrbPondTestUpgrade is OrbPond {
    /// Orb Pond version.
    uint256 private constant _VERSION = 100;

    address public orbLandWallet;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice  Re-initializes the contract after upgrade
    /// @param   orbLandWallet_   The address of the Orb Land wallet.
    function initializeTestUpgrade(address orbLandWallet_) public reinitializer(100) {
        orbLandWallet = orbLandWallet_;
    }

    /// @notice  Creates a new Orb, and emits an event with the Orb's address.
    /// @param   name      Name of the Orb, used for display purposes. Suggestion: "NameOrb".
    /// @param   symbol    Symbol of the Orb, used for display purposes. Suggestion: "ORB".
    /// @param   tokenURI  Initial tokenURI of the Orb, used as part of ERC-721 tokenURI.
    function createOrb(string memory name, string memory symbol, string memory tokenURI) external virtual {
        address[] memory beneficiaryAddresses = new address[](2);
        beneficiaryAddresses[0] = msg.sender;
        beneficiaryAddresses[1] = orbLandWallet;
        uint256[] memory beneficiaryShares = new uint256[](2);
        beneficiaryShares[0] = 95;
        beneficiaryShares[1] = 5;

        address beneficiary = ClonesUpgradeable.clone(paymentSplitterImplementation);
        PaymentSplitter(payable(beneficiary)).initialize(beneficiaryAddresses, beneficiaryShares);

        bytes memory initializeCalldata =
            abi.encodeWithSelector(Orb.initialize.selector, beneficiary, name, symbol, tokenURI);
        ERC1967Proxy proxy = new ERC1967Proxy(versions[1], initializeCalldata);
        orbs[orbCount] = address(proxy);
        IOwnershipTransferrable(orbs[orbCount]).transferOwnership(msg.sender);

        emit OrbCreation(orbCount, address(proxy));

        orbCount++;
    }

    /// @notice  Returns the version of the Orb Pond. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbPondVersion  Version of the Orb Pond contract.
    function version() public view virtual override returns (uint256 orbPondVersion) {
        return _VERSION;
    }
}
