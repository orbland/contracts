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

contract InitialState is EricOrbTestBase {
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
}

contract TransfersRevert is EricOrbTestBase {
    function test_transfersRevert() public {
        address newOwner = address(0xBEEF);
        uint256 id = orb.workaround_orbId();
        vm.expectRevert(EricOrb.TransferringNotSupported.selector);
        orb.transferFrom(address(this), newOwner, id);
        vm.expectRevert(EricOrb.TransferringNotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, id);
        vm.expectRevert(EricOrb.TransferringNotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, id, bytes(""));
    }
}

contract MinimumBid is EricOrbTestBase {
    function test_minimumBidReturnsCorrectValues() public {
        uint256 bidAmount = 0.6 ether;
        orb.startAuction();
        assertEq(orb.minimumBid(), orb.STARTING_PRICE());
        prankAndBid(user, bidAmount);
        assertEq(orb.minimumBid(), bidAmount + orb.MINIMUM_BID_STEP());
    }
}

contract FundsRequiredToBid is EricOrbTestBase {
    function test_fundsRequiredToBidReturnsCorrectValues(uint256 amount) public {
        amount = bound(amount, 0, type(uint224).max);
        assertEq(orb.fundsRequiredToBid(amount), amount + (amount * 1_000 / 10_000));
    }
}

contract StartAuction is EricOrbTestBase {
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
}

contract Bid is EricOrbTestBase {
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

    event AuctionClosed(address indexed winner, uint256 price);


    //TODO: This test failed once, so it's flakey. Will need to revisit and see why it failed
    // output: https://gist.github.com/odyslam/6a98e75297485db2cdd1734c96b89be1
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
        vm.expectEmit(true, false, false, true);
        emit AuctionClosed(orb.winningBidder(), orb.winningBid());
        vm.warp(orb.endTime() + 1);
        orb.closeAuction();
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

contract CloseAuction is EricOrbTestBase {
    event AuctionClosed(address indexed winner, uint256 price);

    function test_closeAuctionRevertsDuringAuction() public {
        orb.startAuction();
        vm.expectRevert(EricOrb.AuctionRunning.selector);
        orb.closeAuction();

        vm.warp(orb.endTime() + 1);
        vm.expectEmit(true, false, false, true);
        emit AuctionClosed(address(0), 0);
        orb.closeAuction();
    }

    function test_closeAuctionRevertsIfAuctionNotStarted() public {
        vm.expectRevert(EricOrb.AuctionNotStarted.selector);
        orb.closeAuction();
        orb.startAuction();
        // endTime != 0
        assertEq(orb.endTime(), block.timestamp + orb.MINIMUM_AUCTION_DURATION());
        vm.expectRevert(EricOrb.AuctionRunning.selector);
        orb.closeAuction();
    }

    function test_closeAuctionWithoutWinner() public {
        orb.startAuction();
        vm.warp(orb.endTime() + 1);
        vm.expectEmit(true, false, false, true);
        emit AuctionClosed(address(0), 0);
        orb.closeAuction();
        assertEq(orb.endTime(), 0);
        assertEq(orb.startTime(), 0);
        assertEq(orb.winningBid(), 0);
        assertEq(orb.winningBidder(), address(0));
    }

    function test_closeAuctionWithWinner() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        uint256 funds = orb.fundsRequiredToBid(amount);
        // Bid `amount` and transfer `funds` to the contract
        prankAndBid(user, amount);
        vm.warp(orb.endTime() + 1);

        // Assert storage before
        assertEq(orb.winningBidder(), user);
        assertEq(orb.winningBid(), amount);
        assertEq(orb.fundsOf(user), funds);
        assertEq(orb.fundsOf(address(orb)), 0);

        vm.expectEmit(true, false, false, true);
        emit AuctionClosed(user, amount);

        orb.closeAuction();

        // Assert storage after
        // storage that is reset
        assertEq(orb.endTime(), 0);
        assertEq(orb.startTime(), 0);
        assertEq(orb.winningBid(), 0);
        assertEq(orb.winningBidder(), address(0));

        // storage that persists
        assertEq(address(orb).balance, funds);
        assertEq(orb.fundsOf(address(this)), amount);
        assertEq(orb.ownerOf(orb.workaround_orbId()), user);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.lastTriggerTime(), block.timestamp - orb.COOLDOWN());
        assertEq(orb.fundsOf(user), funds - amount);
        assertEq(orb.price(), amount);
    }
}

contract EffectiveFundsOf is EricOrbTestBase {
    function test_effectiveFundsCorrectCalculation() public {
        uint256 amount1 = 1 ether;
        uint256 amount2 = 0.5 ether;
        uint256 funds1 = orb.fundsRequiredToBid(amount1);
        uint256 funds2 = orb.fundsRequiredToBid(amount2);
        orb.startAuction();
        prankAndBid(user2, amount2);
        prankAndBid(user, amount1);
        vm.warp(orb.endTime() + 1);
        orb.closeAuction();
        vm.warp(block.timestamp + 1 days);

        // One day has passed since the orb holder got the orb
        // for bid = 1 ether. That means that the price of the
        // orb is now 1 ether. Thus the Orb issuer is owed the tax
        // for 1 day.

        // The user actually transfered `funds1` and `funds2` respectively
        // ether to the contract
        uint256 owed = orb.workaround_owedSinceLastSettlement();
        assertEq(orb.effectiveFundsOf(owner), owed + amount1);
        // The user that won the auction and is holding the orb
        // has the funds they deposited, minus the tax and minus the bid
        // amount
        assertEq(orb.effectiveFundsOf(user), funds1 - owed - amount1);
        // The user that didn't won the auction, has the funds they
        // deposited
        assertEq(orb.effectiveFundsOf(user2), funds2);
    }

    function testFuzz_effectiveFundsCorrectCalculation(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1 ether, orb.workaround_maxPrice());
        amount2 = bound(amount2, orb.STARTING_PRICE(), amount1 - orb.MINIMUM_BID_STEP());
        uint256 funds1 = orb.fundsRequiredToBid(amount1);
        uint256 funds2 = orb.fundsRequiredToBid(amount2);
        orb.startAuction();
        prankAndBid(user2, amount2);
        prankAndBid(user, amount1);
        vm.warp(orb.endTime() + 1);
        orb.closeAuction();
        vm.warp(block.timestamp + 1 days);

        // One day has passed since the orb holder got the orb
        // for bid = 1 ether. That means that the price of the
        // orb is now 1 ether. Thus the Orb issuer is owed the tax
        // for 1 day.

        // The user actually transfered `funds1` and `funds2` respectively
        // ether to the contract
        uint256 owed = orb.workaround_owedSinceLastSettlement();
        assertEq(orb.effectiveFundsOf(owner), owed + amount1);
        // The user that won the auction and is holding the orb
        // has the funds they deposited, minus the tax and minus the bid
        // amount
        assertEq(orb.effectiveFundsOf(user), funds1 - owed - amount1);
        // The user that didn't won the auction, has the funds they
        // deposited
        assertEq(orb.effectiveFundsOf(user2), funds2);
    }
}

contract Deposit is EricOrbTestBase {
    event Deposit(address indexed user, uint256 amount);

    function test_depositRandomUser() public {
        assertEq(orb.fundsOf(user), 0);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user, 1 ether);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user), 1 ether);
    }

    function testFuzz_depositRandomUser(uint256 amount) public {
        assertEq(orb.fundsOf(user), 0);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user, amount);
        vm.deal(user, amount);
        vm.prank(user);
        orb.deposit{value: amount}();
        assertEq(orb.fundsOf(user), amount);
    }

    function test_depositHolderSolvent() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        uint256 depositAmount = 2 ether;
        makeHolderAndWarp(bidAmount);
        // User bids 1 ether, but deposit enough funds
        // to cover the tax for a year, according to
        // fundsRequiredToBid(bidAmount)
        uint256 funds = orb.fundsOf(user);
        vm.expectEmit(true, false, false, true);
        // deposit 1 ether
        emit Deposit(user, depositAmount);
        vm.prank(user);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), funds + depositAmount);
    }

    function test_depositRevertsifHolderInsolvent() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        makeHolderAndWarp(bidAmount);

        // let's make the user insolvent
        // fundsRequiredToBid(bidAmount) ensures enough
        // ether for 1 year, not two
        vm.warp(block.timestamp + 731 days);

        // if a random user deposits, it should work fine
        vm.prank(user2);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user2), 1 ether);

        // if the insolvent holder deposits, it should not work
        vm.expectRevert(EricOrb.HolderInsolvent.selector);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
    }
}

contract Withdraw is EricOrbTestBase {

    event Withdrawal(address indexed recipient, uint256 amount);

    function test_withdrawRevertsIfWinningBidder() public {
        uint256 bidAmount = 1 ether;
        orb.startAuction();
        prankAndBid(user, bidAmount);
        vm.expectRevert(EricOrb.NotPermittedForWinningBidder.selector);
        vm.prank(user);
        orb.withdraw(1);

        vm.expectRevert(EricOrb.NotPermittedForWinningBidder.selector);
        vm.prank(user);
        orb.withdrawAll();

        // user is no longer the winningBidder
        prankAndBid(user2, 2 ether);

        // user can withdraw
        uint256 fundsBefore = orb.fundsOf(user);
        vm.startPrank(user);
        assertEq(user.balance, startingBalance);
        orb.withdraw(100);
        assertEq(user.balance, startingBalance + 100);
        assertEq(orb.fundsOf(user), fundsBefore - 100);
        orb.withdrawAll();
        assertEq(orb.fundsOf(user), 0);
        assertEq(user.balance, startingBalance + fundsBefore);
    }

    event Settlement(address indexed holder, address indexed owner, uint256 amount);

    function test_withdrawSettlesFirstIfHolder() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 10 ether;
        uint256 smallBidAmount = 0.5 ether;
        uint256 withdrawAmount = 0.1 ether;

        orb.startAuction();
        // user2 bids
        prankAndBid(user2, smallBidAmount);
        // user1 bids and becomes the winning bidder
        prankAndBid(user, bidAmount);
        vm.warp(orb.endTime() + 1);
        orb.closeAuction();

        vm.warp(block.timestamp + 30 days);

        // ownerEffective = ownerFunds + transferableToOwner
        // userEffective = userFunds - transferableToOwner
        uint256 userFunds = orb.fundsOf(user);
        uint256 ownerFunds = orb.fundsOf(owner);
        uint256 userEffective = orb.effectiveFundsOf(user);
        uint256 ownerEffective = orb.effectiveFundsOf(owner);
        uint256 transferableToOwner = ownerEffective - ownerFunds;
        uint256 startingBalance = user.balance;

        vm.expectEmit(true, true, false, true);
        emit Settlement(user, owner, transferableToOwner);

        vm.prank(user);
        orb.withdraw(withdrawAmount);

        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(owner), ownerEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, startingBalance + withdrawAmount);

        // move ahead 10 days;
        vm.warp(block.timestamp + 10 days);

        // not holder
        vm.prank(user2);
        startingBalance = user2.balance;
        orb.withdraw(withdrawAmount);
        assertEq(orb.fundsOf(user2), orb.fundsRequiredToBid(smallBidAmount) - withdrawAmount);
        assertEq(user2.balance, startingBalance + withdrawAmount);
    }

    function testFuzz_withdrawSettlesFirstIfHolder(uint256 bidAmount, uint256 withdrawAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, orb.STARTING_PRICE(), orb.workaround_maxPrice());
        makeHolderAndWarp(bidAmount);

        // ownerEffective = ownerFunds + transferableToOwner
        // userEffective = userFunds - transferableToOwner
        uint256 userFunds = orb.fundsOf(user);
        uint256 ownerFunds = orb.fundsOf(owner);
        uint256 userEffective = orb.effectiveFundsOf(user);
        uint256 ownerEffective = orb.effectiveFundsOf(owner);
        uint256 transferableToOwner = ownerEffective - ownerFunds;
        uint256 startingBalance = user.balance;

        vm.expectEmit(true, true, false, true);
        emit Settlement(user, owner, transferableToOwner);

        vm.prank(user);
        withdrawAmount = bound(withdrawAmount, 0, userEffective - 1);
        orb.withdraw(withdrawAmount);
        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(owner), ownerEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, startingBalance + withdrawAmount);

        vm.prank(user);
        orb.withdrawAll();
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), ownerEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, startingBalance + userEffective);
    }

    function test_withdrawRevertsIfInsufficientFunds() public {
        vm.startPrank(user);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(EricOrb.InsufficientFunds.selector, 1 ether, 1 ether + 1));
        orb.withdraw(1 ether + 1);
        assertEq(orb.fundsOf(user), 1 ether);
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(user, 1 ether);
        orb.withdraw(1 ether);
        assertEq(orb.fundsOf(user), 0);
    }
}

contract Settle is EricOrbTestBase {

    event Settlement(address indexed holder, address indexed owner, uint256 amount);

    function test_settleOnlyIfHolderHeld() public {
        vm.expectRevert(EricOrb.ContractHoldsOrb.selector);
        orb.settle();
        assertEq(orb.workaround_lastSettlementTime(), 0);
        makeHolderAndWarp(1 ether);
        orb.settle();
        assertEq(orb.workaround_lastSettlementTime(), block.timestamp);
    }

    function testFuzz_settleCorrect(uint96 bid, uint96 time) public {
        uint256 amount = bound(bid, orb.STARTING_PRICE(), orb.workaround_maxPrice());
        // warp ahead a random amount of time
        // remain under 1 year in total, so solvent
        uint256 timeOffset = bound(time, 0, 300 days);
        vm.warp(block.timestamp + timeOffset);
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.workaround_lastSettlementTime(), 0);
        // it warps 30 days by default
        makeHolderAndWarp(amount);

        uint256 userEffective = orb.effectiveFundsOf(user);
        uint256 ownerEffective = orb.effectiveFundsOf(owner);
        uint256 startingBalance = user.balance;

        orb.settle();
        assertEq(orb.fundsOf(user), userEffective);
        assertEq(orb.fundsOf(owner), ownerEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, startingBalance);

        timeOffset = bound(time, block.timestamp + 340 days, type(uint96).max);
        vm.warp(timeOffset);

        // user is no longer solvent
        // the user can't pay the full owed feeds, so they
        // pay what they can
        uint256 transferable = orb.fundsOf(user);
        orb.settle();
        assertEq(orb.fundsOf(user), 0);
        // ownerEffective is from the last time it settled
        assertEq(orb.fundsOf(owner), transferable + ownerEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, startingBalance);
    }

    function test_settleReturnsIfOwner() public {
        orb.workaround_setOrbHolder(owner);
        orb.workaround_settle();
        assertEq(orb.workaround_lastSettlementTime(), 0);
    }

}


contract HolderSolvent is EricOrbTestBase {
    function test_holderSolventCorrectIfNotOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.workaround_lastSettlementTime(), 0);
        // it warps 30 days by default
        makeHolderAndWarp(1 ether);
        assert(orb.holderSolvent());
        vm.warp(block.timestamp + 700 days);
        assertFalse(orb.holderSolvent());
    }

    function test_holderSolventCorrectIfOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.workaround_lastSettlementTime(), 0);
        vm.warp(block.timestamp + 4885828483 days);
        assertFalse(orb.workaround_holderSolvent());
    }
}

contract OwedSinceLastSettlement is EricOrbTestBase {
    function test_owedSinceLastSettlementCorrectMath() public {
        // _lastSettlementTime = 0
        // secondsSinceLastSettlement = block.timestamp - _lastSettlementTime
        // HOLDER_TAX_NUMERATOR = 1_000
        // FEE_DENOMINATOR = 10_000
        // HOLDER_TAX_PERIOD  = 365 days = 31_536_000 seconds
        // owed = _price * HOLDER_TAX_NUMERATOR * secondsSinceLastSettlement)
        // / (HOLDER_TAX_PERIOD * FEE_DENOMINATOR);
        // Scenario:
        // _price = 17 ether = 17_000_000_000_000_000_000 wei
        // block.timestamp = 167710711
        // owed = 90.407.219.961.314.053.779,8072044647
        orb.workaround_setPrice(17 ether);
        vm.warp(167710711);
        // calculation done off-solidity to verify precision with another environment
        assertEq(orb.workaround_owedSinceLastSettlement(), 9_040_721_990_740_740_740);
    }
}

contract SetPrice is EricOrbTestBase {


    function test_setPriceRevertsIfNotHolder() public {
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(winningBid);
        vm.expectRevert(EricOrb.NotHolder.selector);
        vm.prank(user2);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 10 ether);

        vm.prank(user);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 1 ether);
    }

    function test_setPriceRevertsIfHolderInsolvent() public {
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(winningBid);
        vm.warp(block.timestamp + 600 days);
        vm.startPrank(user);
        vm.expectRevert(EricOrb.HolderInsolvent.selector);
        orb.setPrice(1 ether);

        // As the user can't deposit funds to become solvent again
        // we modify a variable to trick the contract
        orb.workaround_setLastSettlementTime(block.timestamp);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
    }

    function test_setPriceSettlesBefore() public {
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(winningBid);
        vm.prank(user);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event NewPrice(uint256 oldPrice, uint256 newPrice);

    function test_setPriceRevertsIfMaxPrice() public {
        uint256 maxPrice = orb.workaround_maxPrice();
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(winningBid);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(EricOrb.InvalidNewPrice.selector, maxPrice + 1));
        orb.setPrice(maxPrice + 1 );

        vm.expectEmit(false, false, false, true);
        emit NewPrice(10 ether, maxPrice);
        orb.setPrice(maxPrice);
    }

}



