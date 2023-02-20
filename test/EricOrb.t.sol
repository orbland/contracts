// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {EricOrbHarness} from "./harness/EricOrbHarness.sol";
import {EricOrb} from "contracts/EricOrb.sol";

contract EricOrbTest is Test {
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
        assertEq(orb.workaround_maxPrice(), 2 ** 128);
        assertEq(orb.workaround_baseUrl(), "https://static.orb.land/eric/");
    }

    function test_transfers() public {
        address newOwner = address(0xBEEF);
        uint256 id = orb.workaround_orbId();
        vm.expectRevert(EricOrb.TransferringNotSupported.selector);
        orb.transferFrom(address(this), newOwner, id);
        vm.expectRevert(EricOrb.TransferringNotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, id);
        vm.expectRevert(EricOrb.TransferringNotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, id, bytes(""));
    }

    function test_minimumBid() public {
        uint256 bidAmount = 0.6 ether;
        orb.startAuction();
        assertEq(orb.minimumBid(), orb.STARTING_PRICE());
        prankAndBid(user, bidAmount);
        assertEq(orb.minimumBid(), bidAmount + orb.MINIMUM_BID_STEP());
    }

    function test_fundsRequiredToBid(uint256 amount) public {
        amount = bound(amount, 0, type(uint224).max);
        assertEq(orb.fundsRequiredToBid(amount), amount + (amount * 1_000 / 10_000));
    }

    function test_startAuctionOnlyOrbIssuer() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("Ownable: caller is not the owner");
        orb.startAuction();
        orb.startAuction();
        assertEq(orb.startTime(), block.timestamp);
    }

    event AuctionStarted(uint256 startTime, uint256 endTime);

    function test_startAuctionCorrectly() public {
        assertEq(orb.startTime(), 0);
        orb.workaround_setWinningBid(10);
        orb.workaround_setWinningBidder(address(0xBEEF));
        vm.expectEmit(true, true, false, false);
        emit AuctionStarted(block.timestamp, block.timestamp + orb.MINIMUM_AUCTION_DURATION());
        orb.startAuction();
        assertEq(orb.startTime(), block.timestamp);
        assertEq(orb.endTime(), block.timestamp + orb.MINIMUM_AUCTION_DURATION());
        assertEq(orb.winningBid(), 0);
        assertEq(orb.winningBidder(), address(0));
    }

    function test_startAuctionOnlyContractHeld() public {
        orb.workaround_setOrbHolder(address(0xBEEF));
        vm.expectRevert(EricOrb.ContractDoesNotHoldOrb.selector);
        orb.startAuction();
        orb.workaround_setOrbHolder(address(orb));
        vm.expectEmit(true, true, false, false);
        emit AuctionStarted(block.timestamp, block.timestamp + orb.MINIMUM_AUCTION_DURATION());
        orb.startAuction();
    }

    function test_startAuctionNotDuringAuction() public {
        vm.expectEmit(true, true, false, false);
        emit AuctionStarted(block.timestamp, block.timestamp + orb.MINIMUM_AUCTION_DURATION());
        orb.startAuction();
        vm.expectRevert(EricOrb.AuctionRunning.selector);
        orb.startAuction();
    }

    function test_bidOnlyDuringAuction() public {
        uint256 bidAmount = 0.6 ether;
        uint256 finalAmount = orb.fundsRequiredToBid(bidAmount);
        vm.deal(user, finalAmount);
        vm.expectRevert(EricOrb.AuctionNotRunning.selector);
        vm.prank(user);
        orb.bid{value: finalAmount}(bidAmount);
        orb.startAuction();
        assertEq(orb.winningBid(), 0 ether);
        prankAndBid(user, bidAmount);
        assertEq(orb.winningBid(), bidAmount);
    }

    function test_bidUsesTotalFunds() public {
        orb.deposit{value: 1 ether}();
        orb.startAuction();
        vm.prank(user);
        assertEq(orb.winningBid(), 0 ether);
        prankAndBid(user, 0.5 ether);
        assertEq(orb.winningBid(), 0.5 ether);
    }

    function test_bidRevertsIfLtMinimumBid() public {
        orb.startAuction();
        // minimum bid will be the STARTING_PRICE
        uint256 amount = orb.minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(EricOrb.InsufficientBid.selector, amount, orb.minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount);

        // Add back + 1 to amount
        amount++;
        // will not revert
        vm.prank(user);
        orb.bid{value: orb.fundsRequiredToBid(amount)}(amount);
        assertEq(orb.winningBid(), amount);

        // minimum bid will be the winning bid + MINIMUM_BID_STEP
        amount = orb.minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(EricOrb.InsufficientBid.selector, amount, orb.minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount);
    }

    function test_bidRevertsIfLtFundsRequired() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        uint256 funds = orb.fundsRequiredToBid(amount) - 1;
        vm.expectRevert(abi.encodeWithSelector(EricOrb.InsufficientFunds.selector, funds, funds + 1));
        vm.prank(user);
        orb.bid{value: funds}(amount);

        funds++;
        vm.prank(user);
        // will not revert
        orb.bid{value: funds}(amount);
        assertEq(orb.winningBid(), amount);
    }

    event NewBid(address indexed from, uint256 price);

    function test_bidSetsCorrectState() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        uint256 funds = orb.fundsRequiredToBid(amount);
        assertEq(orb.winningBid(), 0 ether);
        assertEq(orb.winningBidder(), address(0));
        assertEq(orb.fundsOf(user), 0);
        assertEq(address(orb).balance, 0);
        uint256 endTime = orb.endTime();

        vm.expectEmit(true, false, false, true);
        emit NewBid(user, amount);
        prankAndBid(user, amount);

        assertEq(orb.winningBid(), amount);
        assertEq(orb.winningBidder(), user);
        assertEq(orb.fundsOf(user), funds);
        assertEq(address(orb).balance, funds);
        assertEq(orb.endTime(), endTime);
    }

    mapping(address => uint256) fundsOfUser;

    function testFuzz_bidSetsCorrectState(address[16] memory users, uint128[16] memory amounts) public {
        orb.startAuction();
        uint256 contractBalance;
        for (uint256 i = 1; i < 16; i++) {
            uint256 amount = bound(amounts[i], orb.minimumBid(), orb.minimumBid() + 1_000_000_000);
            user = users[i];
            vm.assume(user != address(0));

            uint256 funds = orb.fundsRequiredToBid(amount);

            fundsOfUser[user] += funds;

            vm.expectEmit(true, false, false, true);
            emit NewBid(user, amount);
            prankAndBid(user, amount);
            contractBalance += funds;

            assertEq(orb.winningBid(), amount);
            assertEq(orb.winningBidder(), user);
            assertEq(orb.fundsOf(user), fundsOfUser[user]);
            assertEq(address(orb).balance, contractBalance);
        }
    }

    function test_bidExtendsAuction() public {
        assertEq(orb.endTime(), 0);
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        // endTime = block.timestamp + MINIMUM_AUCTION_DURATION
        uint256 endTime = orb.endTime();
        // set block.timestamp to endTime - BID_AUCTION_EXTENSION
        vm.warp(endTime - orb.BID_AUCTION_EXTENSION());
        prankAndBid(user, amount);
        // didn't change because block.timestamp + BID_AUCTION_EXTENSION  = endTime
        assertEq(orb.endTime(), endTime);

        vm.warp(endTime - orb.BID_AUCTION_EXTENSION() + 50);
        amount = orb.minimumBid();
        prankAndBid(user, amount);
        // change because block.timestamp + BID_AUCTION_EXTENSION + 50 >  endTime
        assertEq(orb.endTime(), endTime + 50);
    }
}
