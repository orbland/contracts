// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OrbV2} from "../../src/OrbV2.sol";

/* solhint-disable func-name-mixedcase */
contract OrbHarness is OrbV2 {
    function workaround_cooldownMaximumDuration() public pure returns (uint256) {
        return _COOLDOWN_MAXIMUM_DURATION;
    }

    function workaround_maximumPrice() public pure returns (uint256) {
        return _MAXIMUM_PRICE;
    }

    function workaround_tokenURI() public view returns (string memory) {
        return _tokenURI;
    }

    function workaround_auctionRunning() public view returns (bool) {
        return _auctionRunning();
    }

    function workaround_minimumBid() public view returns (uint256) {
        return _minimumBid();
    }

    function workaround_setPrice(uint256 _price) public {
        price = _price;
    }

    function workaround_setLastSettlementTime(uint256 time) public {
        lastSettlementTime = time;
    }

    function workaround_setOrbKeeper(address keeper_) public {
        _transferOrb(keeper, keeper_);
    }

    function workaround_owedSinceLastSettlement() public view returns (uint256) {
        return _owedSinceLastSettlement();
    }

    function workaround_settle() public {
        _settle();
    }
}
