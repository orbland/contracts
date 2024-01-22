// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase,one-contract-per-file
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {OrbTestBase} from "./OrbV2.t.sol";
import {Orb} from "../../src/Orb.sol";
import {OrbV2} from "../../src/OrbV2.sol";

contract RelinquishmentTest is OrbTestBase {
    function test_revertsIfNotKeeper() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.expectRevert(Orb.NotKeeper.selector);
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
        vm.expectRevert(Orb.KeeperInsolvent.selector);
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
        vm.expectRevert(Orb.NotKeeper.selector);
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
        vm.expectRevert(Orb.KeeperInsolvent.selector);
        orb.relinquish(true);
        vm.warp(block.timestamp - 1300 days);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.keeper(), address(orb));
    }

    function test_revertsIfCreator() public {
        orb.listWithPrice(1 ether);
        vm.expectRevert(Orb.NotPermitted.selector);
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
        vm.expectRevert(Orb.ContractHoldsOrb.selector);
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
        vm.expectRevert(Orb.KeeperSolvent.selector);
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

contract RecallTest is OrbTestBase {
    event Recall(address indexed formerKeeper);

    function test_revertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        vm.prank(user);
        orb.recall();
    }

    function test_revertsIfNotKeeperHeld() public {
        vm.expectRevert(OrbV2.KeeperDoesNotHoldOrb.selector);
        orb.recall();

        orb.listWithPrice(1 ether);
        vm.expectRevert(OrbV2.KeeperDoesNotHoldOrb.selector);
        orb.recall();
    }

    function test_revertsIfOathHonored() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.expectRevert(OrbV2.OathStillHonored.selector);
        orb.recall();

        vm.warp(20_000_000);
        vm.expectRevert(OrbV2.OathStillHonored.selector);
        orb.recall();

        vm.warp(20_000_001);
        vm.expectEmit(true, true, true, true);
        emit Recall(user);
        orb.recall();
    }

    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function test_succeeds() public {
        makeKeeperAndWarp(user, 10 ether);
        vm.warp(20_000_001);

        assertEq(orb.lastSettlementTime(), 10_086_401); // 10M + 1 day + 1
        assertEq(orb.keeper(), user);
        assertEq(orb.price(), 10 ether);

        uint256 owed = orb.workaround_owedSinceLastSettlement();

        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, owed);
        vm.expectEmit(true, true, true, true);
        emit Recall(user);
        vm.expectEmit(true, true, true, true);
        emit Transfer(user, address(orb), 1);

        orb.recall();

        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.keeper(), address(orb));
        assertEq(orb.price(), 0);
    }
}
