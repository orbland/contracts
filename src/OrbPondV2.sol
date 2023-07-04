// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PaymentSplitter} from "../lib/openzeppelin-contracts/contracts/finance/PaymentSplitter.sol";

import {IOwnershipTransferrable} from "./IOwnershipTransferrable.sol";
import {IOrb} from "./IOrb.sol";
import {OrbPond} from "./OrbPond.sol";

/// @title   Orb Pond - The Orb Factory
/// @author  Jonas Lekevicius
/// @notice  Orbs come from a Pond. The Orb Pond is used to efficiently create new Orbs, and track “official” Orbs,
///          supported by the Orb Land system. The Orb Pond is also used to register allowed Orb upgrade
///          implementations, and keeps a reference to an Orb Invocation Registry used by all Orbs created with this
///          Orb Pond.
/// @dev     Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator and for upgrades.
///          V2 allows anyone to create orbs, not just the owner, automatically splitting proceeds between the creator
///          and the Orb Land wallet.
contract OrbPondV2 is OrbPond {
    /// Orb Pond version. Value: 2.
    uint256 private constant _VERSION = 2;

    address public orbLandWallet;

    // @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice  Re-initializes the contract after upgrade
    /// @param   orbLandWallet_   The address of the Orb Land wallet.
    function initializeV2(address orbLandWallet_) public reinitializer(2) {
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

        PaymentSplitter orbBeneficiary = new PaymentSplitter(beneficiaryAddresses, beneficiaryShares);
        address splitterAddress = address(orbBeneficiary);

        bytes memory initializeCalldata =
            abi.encodeWithSelector(IOrb.initialize.selector, splitterAddress, name, symbol, tokenURI);
        ERC1967Proxy proxy = new ERC1967Proxy(versions[1], initializeCalldata);
        orbs[orbCount] = address(proxy);
        IOwnershipTransferrable(orbs[orbCount]).transferOwnership(msg.sender);

        emit OrbCreation(orbCount, address(proxy));

        orbCount++;
    }

    /// @notice  Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbPondVersion  Version of the Orb Pond contract.
    function version() public view virtual override returns (uint256 orbPondVersion) {
        return _VERSION;
    }
}
