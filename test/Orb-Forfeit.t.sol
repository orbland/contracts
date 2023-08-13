// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";

import {OrbTestBase} from "./Orb.t.sol";
import {IOrb} from "../src/IOrb.sol";

/* solhint-disable func-name-mixedcase */
contract RelinquishmentTest is OrbTestBase {
    function test_revertsIfNotKeeper() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.NotKeeper.selector);
        vm.prank(user2);
        orb.relinquish(false);

        vm.prank(user);
        orb.relinquish(false);
        assertEq(orb.keeper(), address(orb));
    }

    function test_revertsIfKeeperInsolvent() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user);
        vm.expectRevert(IOrb.KeeperInsolvent.selector);
        orb.relinquish(false);
        vm.warp(block.timestamp - 1300 days);
        vm.prank(user);
        orb.relinquish(false);
        assertEq(orb.keeper(), address(orb));
    }

    function test_settlesFirst() public {
        makeKeeperAndWarp(user, 1 ether);
        // after making `user` the current keeper of the Orb, `makeKeeperAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user);
        orb.relinquish(false);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event Relinquishment(address indexed formerKeeper);
    event Withdrawal(address indexed recipient, uint256 indexed amount);

    function test_succeedsCorrectly() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        assertEq(orb.keeper(), user);
        vm.expectEmit(true, true, true, true);
        emit Relinquishment(user);
        vm.expectEmit(true, true, true, true);
        uint256 effectiveFunds = effectiveFundsOf(user);
        emit Withdrawal(user, effectiveFunds);
        vm.prank(user);
        orb.relinquish(false);
        assertEq(orb.keeper(), address(orb));
        assertEq(orb.price(), 0);
    }
}

contract RelinquishmentWithAuctionTest is OrbTestBase {
    function test_revertsIfNotKeeper() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.NotKeeper.selector);
        vm.prank(user2);
        orb.relinquish(true);

        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.keeper(), address(orb));
    }

    function test_revertsIfKeeperInsolvent() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user);
        vm.expectRevert(IOrb.KeeperInsolvent.selector);
        orb.relinquish(true);
        vm.warp(block.timestamp - 1300 days);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.keeper(), address(orb));
    }

    function test_revertsIfCreator() public {
        orb.listWithPrice(1 ether);
        vm.expectRevert(IOrb.NotPermitted.selector);
        orb.relinquish(true);
    }

    function test_noAuctionIfKeeperDurationZero() public {
        orb.setAuctionParameters(0, 1, 1 days, 0, 5 minutes);
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.auctionEndTime(), 0);
    }

    function test_settlesFirst() public {
        makeKeeperAndWarp(user, 1 ether);
        // after making `user` the current keeper of the Orb, `makeKeeperAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event Relinquishment(address indexed formerKeeper);
    event AuctionStart(
        uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
    );
    event Withdrawal(address indexed recipient, uint256 indexed amount);

    function test_succeedsCorrectly() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        assertEq(orb.keeper(), user);
        assertEq(orb.price(), 1 ether);
        assertEq(orb.auctionBeneficiary(), beneficiary);
        assertEq(orb.auctionEndTime(), 0);
        uint256 effectiveFunds = effectiveFundsOf(user);
        vm.expectEmit(true, true, true, true);
        emit Relinquishment(user);
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionKeeperMinimumDuration(), user);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(user, effectiveFunds);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.keeper(), address(orb));
        assertEq(orb.price(), 0);
        assertEq(orb.auctionBeneficiary(), user);
        assertEq(orb.auctionEndTime(), block.timestamp + orb.auctionKeeperMinimumDuration());
    }
}

contract ForecloseTest is OrbTestBase {
    function test_revertsIfNotKeeperHeld() public {
        vm.expectRevert(IOrb.ContractHoldsOrb.selector);
        vm.prank(user2);
        orb.foreclose();

        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 100000 days);
        vm.prank(user2);
        orb.foreclose();
        assertEq(orb.keeper(), address(orb));
    }

    event Foreclosure(address indexed formerKeeper);
    event AuctionStart(
        uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
    );

    function test_revertsifKeeperSolvent() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.KeeperSolvent.selector);
        orb.foreclose();
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, true, true, true);
        emit Foreclosure(user);
        orb.foreclose();
    }

    function test_noAuctionIfKeeperDurationZero() public {
        orb.setAuctionParameters(0, 1, 1 days, 0, 5 minutes);
        makeKeeperAndWarp(user, 10 ether);
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, true, true, true);
        emit Foreclosure(user);
        assertEq(orb.keeper(), user);
        orb.foreclose();
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.keeper(), address(orb));
        assertEq(orb.price(), 0);
    }

    function test_succeeds() public {
        makeKeeperAndWarp(user, 10 ether);
        vm.warp(block.timestamp + 10000 days);
        uint256 exepectedEndTime = block.timestamp + orb.auctionKeeperMinimumDuration();
        vm.expectEmit(true, true, true, true);
        emit Foreclosure(user);
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, exepectedEndTime, user);
        assertEq(orb.keeper(), user);
        orb.foreclose();
        assertEq(orb.auctionBeneficiary(), user);
        assertEq(orb.auctionEndTime(), exepectedEndTime);
        assertEq(orb.keeper(), address(orb));
        assertEq(orb.price(), 0);
    }
}
