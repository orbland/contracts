// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {EricOrb} from "src/EricOrb.sol";

/* solhint-disable func-name-mixedcase */
contract EricOrbHarness is
    EricOrb(
        7 days, // cooldown
        7 days // responseFlaggingPeriod
    )
{
    function workaround_orbId() public pure returns (uint256) {
        return ERIC_ORB_ID;
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
        _transferOrb(ownerOf(ERIC_ORB_ID), holder);
    }

    function workaround_owedSinceLastSettlement() public view returns (uint256) {
        return _owedSinceLastSettlement();
    }

    function workaround_settle() public {
        _settle();
    }
}
