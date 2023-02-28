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

    function workaround_setPrice(uint256 price) public {
        _price = price;
    }

    function workaround_setLastSettlementTime(uint256 time) public {
        _lastSettlementTime = time;
    }

    function workaround_setOrbHolder(address holder) public {
        _transfer(ownerOf(ERIC_ORB_ID), holder, ERIC_ORB_ID);
    }

    function workaround_owedSinceLastSettlement() public view returns (uint256) {
        return _owedSinceLastSettlement();
    }

    // assume that _lastSettlement is internal
    function workaround_lastSettlementTime() public view returns (uint256) {
        return _lastSettlementTime;
    }

    function workaround_holderSolvent() public view returns (bool) {
        return _holderSolvent();
    }

    function workaround_settle() public {
        _settle();
    }

    function workaround_foreclosureTime() public returns (uint256){
        return _foreclosureTime();
    }

}
