// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {EricOrbHarness} from "./harness/EricOrbHarness.sol";
import {EricOrb} from "contracts/EricOrb.sol";

contract EricOrbTestBase is Test {
    EricOrbHarness orb;

    address user;
    address user2;
    address owner;

    uint256 startingBalance;

    function setUp() public {
        orb = new EricOrbHarness();
        user = address(0xBEEF);
        user2 = address(0xFEEEEEB);
        startingBalance = 10000 ether;
        vm.deal(user, startingBalance);
        vm.deal(user2, startingBalance);
        owner = orb.owner();
    }

    function prankAndBid(address bidder, uint256 bidAmount) internal {
        uint256 finalAmount = orb.fundsRequiredToBid(bidAmount);
        vm.deal(bidder, startingBalance + finalAmount);
        vm.prank(bidder);
        orb.bid{value: finalAmount}(bidAmount);
    }

    function makeHolderAndWarp(uint256 bid) public {
        orb.startAuction();
        prankAndBid(user, bid);
        vm.warp(orb.endTime() + 1);
        orb.closeAuction();
        vm.warp(block.timestamp + 30 days);
    }
}
