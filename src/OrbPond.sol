// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {Orb} from "./Orb.sol";

/// @title   Orb Pond - the Orb Factory
/// @author  Jonas Lekevicius
/// @notice  Orbs come from a Pond. The Pond is used to efficiently create new Orbs, and track "official" Orbs, honered
///          by the Orb Land system. The Pond is also used to configure the Orbs and transfer ownership to the Orb
///          creator.
/// @dev     Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator.
contract OrbPond is Ownable {
    event OrbCreation(uint256 indexed orbId, address indexed orbAddress);

    /// The mapping of Orb ids to Orbs. Increases monotonically.
    mapping(uint256 => Orb) public orbs;
    /// The number of Orbs created so far, used to find the next Orb id.
    uint256 public orbCount;

    /// @notice  Creates a new Orb, and emits an event with the Orb's address.
    /// @param   name          Name of the Orb, used for display purposes. Suggestion: "NameOrb".
    /// @param   symbol        Symbol of the Orb, used for display purposes. Suggestion: "ORB".
    /// @param   tokenId       TokenId of the Orb. Only one ERC-721 token will be minted, with this id.
    /// @param   beneficiary   Address of the Orb's beneficiary. See `Orb` contract for more on beneficiary.
    /// @param   baseURI       Initial baseURI of the Orb, used as part of ERC-721 tokenURI.
    function createOrb(
        string memory name,
        string memory symbol,
        uint256 tokenId,
        address beneficiary,
        string memory baseURI
    ) external onlyOwner {
        orbs[orbCount] = new Orb();

        emit OrbCreation(orbCount, address(orbs[orbCount]));

        orbCount++;
    }

    /// @notice  Configures most Orb's parameters in one transaction. Used to initially set up the Orb.
    /// @param   orbId                         Id of the Orb to configure.
    /// @param   auctionStartingPrice          Starting price of the Orb's auction.
    /// @param   auctionMinimumBidStep         Minimum difference between bids in the Orb's auction.
    /// @param   auctionMinimumDuration        Minimum duration of the Orb's auction.
    /// @param   auctionKeeperMinimumDuration  Minimum duration of the Orb's auction.
    /// @param   auctionBidExtension           Auction duration extension for late bids during the Orb auction.
    /// @param   keeperTaxNumerator            Harberger tax numerator of the Orb, in basis points.
    /// @param   royaltyNumerator              Royalty numerator of the Orb, in basis points.
    /// @param   cooldown                      Cooldown of the Orb in seconds.
    /// @param   cleartextMaximumLength        Invocation cleartext maximum length for the Orb.
    function configureOrb(
        uint256 orbId,
        uint256 auctionStartingPrice,
        uint256 auctionMinimumBidStep,
        uint256 auctionMinimumDuration,
        uint256 auctionKeeperMinimumDuration,
        uint256 auctionBidExtension,
        uint256 keeperTaxNumerator,
        uint256 royaltyNumerator,
        uint256 cooldown,
        uint256 flaggingPeriod,
        uint256 cleartextMaximumLength
    ) external onlyOwner {
        orbs[orbId].setAuctionParameters(
            auctionStartingPrice,
            auctionMinimumBidStep,
            auctionMinimumDuration,
            auctionKeeperMinimumDuration,
            auctionBidExtension
        );
        orbs[orbId].setFees(keeperTaxNumerator, royaltyNumerator);
        orbs[orbId].setCooldown(cooldown, flaggingPeriod);
        orbs[orbId].setCleartextMaximumLength(cleartextMaximumLength);
    }

    /// @notice  Transfers the ownership of an Orb to its creator. This contract will no longer be able to configure
    ///          the Orb afterwards.
    /// @param   orbId           Id of the Orb to transfer.
    /// @param   creatorAddress  Address of the Orb's creator, they will have full control over the Orb.
    function transferOrbOwnership(uint256 orbId, address creatorAddress) external onlyOwner {
        orbs[orbId].transferOwnership(creatorAddress);
    }
}
