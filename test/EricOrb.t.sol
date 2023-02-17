// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {EricOrbHarness} from "./harness/EricOrbHarness.sol";

contract EricOrbTest is Test{

    EricOrbHarness orb;

    function setUp() public {
        orb = new EricOrbHarness();
    }

    // Test that the initial state is correct
    function test_initialState() public {
        assertEq(address(orb), orb.ownerOf(orb.workaround_orbId()));
        assertFalse(orb.auctionRunning());
        assertEq(orb.owner(), address(this));

        // This will be callable after audit mitigations
        // assertEq(orb.price(), 0);
        assertEq(orb.lastTriggerTime(), 0);
        assertEq(orb.triggersCount(), 0);

        assertEq(orb.flaggedResponsesCount(), 0);

        assertEq(orb.startTime(), 0);
        assertEq(orb.endTime(), 0);
        assertEq(orb.winningBidder(), address(0));
        assertEq(orb.winningBid(), 0);

        // This will be callable after audit mitigations
        // assertEq(orb.lastSettlementTime(), 0);
        // assertEq(orb.userReceiveTime(), 0);
    }

    function test_constants() public {
        assertEq(orb.COOLDOWN(), 7 days);
        assertEq(orb.RESPONSE_FLAGGING_PERIOD(), 7 days);
        assertEq(orb.MAX_CLEARTEXT_LENGTH(), 280);

        assertEq(orb.FEE_DENOMINATOR(), 10000);
        assertEq(orb.HOLDER_TAX_NUMERATOR(), 1000);
        assertEq(orb.HOLDER_TAX_PERIOD(), 365 days);
        assertEq(orb.SALE_ROYALTIES_NUMERATOR(), 1000);

        assertEq(orb.STARTING_PRICE(), 0.1 ether);
        assertEq(orb.MINIMUM_BID_STEP(), 0.01 ether);
        assertEq(orb.MINIMUM_AUCTION_DURATION(), 1 days);
        assertEq(orb.BID_AUCTION_EXTENSION(), 30 minutes);

        assertEq(orb.workaround_orbId(), 69);
        assertEq(orb.workaround_infinity(), type(uint256).max);
        assertEq(orb.workaround_maxPrice(), 2 ** 128 );
        assertEq(orb.workaround_baseUrl(), "https://static.orb.land/eric/");
    }

}
