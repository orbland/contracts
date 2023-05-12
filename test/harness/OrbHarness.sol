// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Orb} from "src/Orb.sol";

/* solhint-disable func-name-mixedcase */
contract OrbHarness is
    Orb(
        "Orb", // name
        "ORB", // symbol
        69, // tokenId
        address(0xC0FFEE), // beneficiary
        keccak256(abi.encodePacked("test oath")), // oathHash
        100 // 1_700_000_000 // honoredUntil
    )
{
    function workaround_tokenId() public view returns (uint256) {
        return tokenId;
    }

    function workaround_infinity() public pure returns (uint256) {
        return type(uint256).max;
    }

    function workaround_maxPrice() public pure returns (uint256) {
        return MAX_PRICE;
    }

    function workaround_baseURI() public view returns (string memory) {
        return baseURI;
    }

    function workaround_setLeadingBidder(address bidder) public {
        leadingBidder = bidder;
    }

    function workaround_setLeadingBid(uint256 bid) public {
        leadingBid = bid;
    }

    function workaround_setPrice(uint256 _price) public {
        price = _price;
    }

    function workaround_setLastSettlementTime(uint256 time) public {
        lastSettlementTime = time;
    }

    function workaround_setOrbHolder(address holder) public {
        _transferOrb(ownerOf(tokenId), holder);
    }

    function workaround_owedSinceLastSettlement() public view returns (uint256) {
        return _owedSinceLastSettlement();
    }

    function workaround_settle() public {
        _settle();
    }
}
