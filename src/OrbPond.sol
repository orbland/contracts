// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Orb} from "./Orb.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title   Orb Pond - the Orb Factory
/// @author  Jonas Lekevicius
/// @notice  Orbs come from a pond.
/// @dev     Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the owner.
contract OrbPond is Ownable {
    event OrbCreation(
        uint256 indexed orbId, address indexed orbAddress, bytes32 indexed oathHash, uint256 honoredUntil
    );

    mapping(uint256 => Orb) public orbs;
    uint256 public orbCount;

    function createOrb(
        string memory name,
        string memory symbol,
        uint256 tokenId,
        address beneficiary,
        bytes32 oathHash,
        uint256 honoredUntil,
        string memory baseURI
    ) external onlyOwner {
        orbs[orbCount] = new Orb(
            name,
            symbol,
            tokenId,
            beneficiary,
            oathHash,
            honoredUntil,
            baseURI
        );

        emit OrbCreation(orbCount, address(orbs[orbCount]), oathHash, honoredUntil);

        orbCount++;
    }

    function configureOrb(
        uint256 orbId,
        uint256 auctionStartingPrice,
        uint256 auctionMinimumBidStep,
        uint256 auctionMinimumDuration,
        uint256 auctionBidExtension,
        uint256 holderTaxNumerator,
        uint256 royaltyNumerator,
        uint256 cooldown,
        uint256 cleartextMaximumLength
    ) external onlyOwner {
        orbs[orbId].setAuctionParameters(
            auctionStartingPrice, auctionMinimumBidStep, auctionMinimumDuration, auctionBidExtension
        );
        orbs[orbId].setFees(holderTaxNumerator, royaltyNumerator);
        orbs[orbId].setCooldown(cooldown);
        orbs[orbId].setCleartextMaximumLength(cleartextMaximumLength);
    }

    function transferOrbOwnership(uint256 orbId, address creatorAddress) external onlyOwner {
        orbs[orbId].transferOwnership(creatorAddress);
    }
}
