// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {EricOrbHarness} from "./harness/EricOrbHarness.sol";
import {EricOrb} from "contracts/EricOrb.sol";

contract EricOrbTestBase is Test {
    EricOrbHarness orb;

    address user;

    function setUp() public {
        orb = new EricOrbHarness();
        user = address(0xBEEF);
        vm.deal(user, 100 ether);
    }

    function prankAndBid(address bidder, uint256 bidAmount) internal {
        uint256 finalAmount = orb.fundsRequiredToBid(bidAmount);
        vm.deal(bidder, finalAmount);
        vm.prank(bidder);
        orb.bid{value: finalAmount}(bidAmount);
    }
}
