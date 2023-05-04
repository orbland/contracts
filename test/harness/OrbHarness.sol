// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Orb} from "src/Orb.sol";

/* solhint-disable func-name-mixedcase */
contract OrbHarness is
    Orb(
        7 days, // cooldown
        7 days, // responseFlaggingPeriod
        1 days, // minimumAuctionDuration
        30 minutes, // bidAuctionExtension
        address(0xC0FFEE), // beneficiary
        1000, // holderTaxNumerator
        1000, // saleRoyaltiesNumerator
        0.1 ether, // startingPrice
        0.1 ether // minimumBidStep
    )
{
    function workaround_orbId() public pure returns (uint256) {
        return TOKEN_ID;
    }

    function workaround_infinity() public pure returns (uint256) {
        return type(uint256).max;
    }

    function workaround_maxPrice() public pure returns (uint256) {
        return MAX_PRICE;
    }

    function workaround_baseUrl() public pure returns (string memory) {
        return BASE_URL;
    }

    function workaround_setWinningBidder(address bidder) public {
        winningBidder = bidder;
    }

    function workaround_setWinningBid(uint256 bid) public {
        winningBid = bid;
    }

    function workaround_setPrice(uint256 _price) public {
        price = _price;
    }

    function workaround_setLastSettlementTime(uint256 time) public {
        lastSettlementTime = time;
    }

    function workaround_setOrbHolder(address holder) public {
        _transferOrb(ownerOf(TOKEN_ID), holder);
    }

    function workaround_owedSinceLastSettlement() public view returns (uint256) {
        return _owedSinceLastSettlement();
    }

    function workaround_settle() public {
        _settle();
    }
}
