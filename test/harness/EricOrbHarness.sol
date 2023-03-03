// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {EricOrb} from "contracts/EricOrb.sol";

contract EricOrbHarness is EricOrb{

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

    function workaround_setWinningBidder(address bidder) public  {
        winningBidder = bidder;
    }

    function workaround_setWinningBid(uint256 bid) public {
        winningBid = bid;
    }

    function workaround_setOrbHolder(address holder) public {
        _transfer(ownerOf(ERIC_ORB_ID), holder, ERIC_ORB_ID);
    }
}
