// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {EricOrbHarness} from "./harness/EricOrbHarness.sol";
import {EricOrb} from "src/EricOrb.sol";
import {console} from "forge-std/console.sol";

/* solhint-disable func-name-mixedcase */
contract EricOrbTestBase is Test {
    EricOrbHarness internal orb;

    address internal user;
    address internal user2;
    address internal owner;

    uint256 internal startingBalance;

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

    function makeHolderAndWarp(address newHolder, uint256 bid) public {
        orb.startAuction();
        prankAndBid(newHolder, bid);
        vm.warp(orb.endTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);
    }
}

contract InitialStateTest is EricOrbTestBase {
    // Test that the initial state is correct
    function test_initialState() public {
        assertEq(address(orb), orb.ownerOf(orb.workaround_orbId()));
        assertFalse(orb.auctionRunning());
        assertEq(orb.owner(), address(this));

        assertEq(orb.price(), 0);
        assertEq(orb.lastTriggerTime(), 0);
        assertEq(orb.triggersCount(), 0);

        assertEq(orb.flaggedResponsesCount(), 0);

        assertEq(orb.startTime(), 0);
        assertEq(orb.endTime(), 0);
        assertEq(orb.winningBidder(), address(0));
        assertEq(orb.winningBid(), 0);

        assertEq(orb.lastSettlementTime(), 0);
        assertEq(orb.holderReceiveTime(), 0);
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

contract TransfersRevertTest is EricOrbTestBase {
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

contract MinimumBidTest is EricOrbTestBase {
    function test_minimumBidReturnsCorrectValues() public {
        uint256 bidAmount = 0.6 ether;
        orb.startAuction();
        assertEq(orb.minimumBid(), orb.STARTING_PRICE());
        prankAndBid(user, bidAmount);
        assertEq(orb.minimumBid(), bidAmount + orb.MINIMUM_BID_STEP());
    }
}

contract FundsRequiredToBidTest is EricOrbTestBase {
    function test_fundsRequiredToBidReturnsCorrectValues(uint256 amount) public {
        amount = bound(amount, 0, type(uint224).max);
        assertEq(orb.fundsRequiredToBid(amount), amount + ((amount * 1_000) / 10_000));
    }
}

contract StartAuctionTest is EricOrbTestBase {
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

contract BidTest is EricOrbTestBase {
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

    mapping(address => uint256) internal fundsOfUser;

    event AuctionFinalized(address indexed winner, uint256 price);

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
        emit AuctionFinalized(orb.winningBidder(), orb.winningBid());
        vm.warp(orb.endTime() + 1);
        orb.finalizeAuction();
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

contract FinalizeAuctionTest is EricOrbTestBase {
    event AuctionFinalized(address indexed winner, uint256 price);

    function test_finalizeAuctionRevertsDuringAuction() public {
        orb.startAuction();
        vm.expectRevert(EricOrb.AuctionRunning.selector);
        orb.finalizeAuction();

        vm.warp(orb.endTime() + 1);
        vm.expectEmit(true, false, false, true);
        emit AuctionFinalized(address(0), 0);
        orb.finalizeAuction();
    }

    function test_finalizeAuctionRevertsIfAuctionNotStarted() public {
        vm.expectRevert(EricOrb.AuctionNotStarted.selector);
        orb.finalizeAuction();
        orb.startAuction();
        // endTime != 0
        assertEq(orb.endTime(), block.timestamp + orb.MINIMUM_AUCTION_DURATION());
        vm.expectRevert(EricOrb.AuctionRunning.selector);
        orb.finalizeAuction();
    }

    function test_finalizeAuctionWithoutWinner() public {
        orb.startAuction();
        vm.warp(orb.endTime() + 1);
        vm.expectEmit(true, false, false, true);
        emit AuctionFinalized(address(0), 0);
        orb.finalizeAuction();
        assertEq(orb.endTime(), 0);
        assertEq(orb.startTime(), 0);
        assertEq(orb.winningBid(), 0);
        assertEq(orb.winningBidder(), address(0));
    }

    function test_finalizeAuctionWithWinner() public {
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
        emit AuctionFinalized(user, amount);

        orb.finalizeAuction();

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

contract EffectiveFundsOfTest is EricOrbTestBase {
    function test_effectiveFundsCorrectCalculation() public {
        uint256 amount1 = 1 ether;
        uint256 amount2 = 0.5 ether;
        uint256 funds1 = orb.fundsRequiredToBid(amount1);
        uint256 funds2 = orb.fundsRequiredToBid(amount2);
        orb.startAuction();
        prankAndBid(user2, amount2);
        prankAndBid(user, amount1);
        vm.warp(orb.endTime() + 1);
        orb.finalizeAuction();
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
        orb.finalizeAuction();
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

contract DepositTest is EricOrbTestBase {
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
        makeHolderAndWarp(user, bidAmount);
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

    function testFuzz_depositHolderSolvent(uint256 bidAmount, uint256 depositAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, 0.1 ether, orb.workaround_maxPrice());
        depositAmount = bound(depositAmount, 0.1 ether, orb.workaround_maxPrice());
        makeHolderAndWarp(user, bidAmount);
        // User bids 1 ether, but deposit enough funds
        // to cover the tax for a year, according to
        // fundsRequiredToBid(bidAmount)
        uint256 funds = orb.fundsOf(user);
        vm.expectEmit(true, false, false, true);
        // deposit 1 ether
        emit Deposit(user, depositAmount);
        vm.prank(user);
        vm.deal(user, depositAmount);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), funds + depositAmount);
    }

    function test_depositRevertsifHolderInsolvent() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        makeHolderAndWarp(user, bidAmount);

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

contract WithdrawTest is EricOrbTestBase {
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
        orb.finalizeAuction();

        vm.warp(block.timestamp + 30 days);

        // ownerEffective = ownerFunds + transferableToOwner
        // userEffective = userFunds - transferableToOwner
        uint256 ownerFunds = orb.fundsOf(owner);
        uint256 userEffective = orb.effectiveFundsOf(user);
        uint256 ownerEffective = orb.effectiveFundsOf(owner);
        uint256 transferableToOwner = ownerEffective - ownerFunds;
        uint256 initialBalance = user.balance;

        vm.expectEmit(true, true, false, true);
        emit Settlement(user, owner, transferableToOwner);

        vm.prank(user);
        orb.withdraw(withdrawAmount);

        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(owner), ownerEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + withdrawAmount);

        // move ahead 10 days;
        vm.warp(block.timestamp + 10 days);

        // not holder
        vm.prank(user2);
        initialBalance = user2.balance;
        orb.withdraw(withdrawAmount);
        assertEq(orb.fundsOf(user2), orb.fundsRequiredToBid(smallBidAmount) - withdrawAmount);
        assertEq(user2.balance, initialBalance + withdrawAmount);
    }

    function testFuzz_withdrawSettlesFirstIfHolder(uint256 bidAmount, uint256 withdrawAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, orb.STARTING_PRICE(), orb.workaround_maxPrice());
        makeHolderAndWarp(user, bidAmount);

        // ownerEffective = ownerFunds + transferableToOwner
        // userEffective = userFunds - transferableToOwner
        uint256 ownerFunds = orb.fundsOf(owner);
        uint256 userEffective = orb.effectiveFundsOf(user);
        uint256 ownerEffective = orb.effectiveFundsOf(owner);
        uint256 transferableToOwner = ownerEffective - ownerFunds;
        uint256 initialBalance = user.balance;

        vm.expectEmit(true, true, false, true);
        emit Settlement(user, owner, transferableToOwner);

        vm.prank(user);
        withdrawAmount = bound(withdrawAmount, 0, userEffective - 1);
        orb.withdraw(withdrawAmount);
        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(owner), ownerEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + withdrawAmount);

        vm.prank(user);
        orb.withdrawAll();
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), ownerEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + userEffective);
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

contract SettleTest is EricOrbTestBase {
    event Settlement(address indexed holder, address indexed owner, uint256 amount);

    function test_settleOnlyIfHolderHeld() public {
        vm.expectRevert(EricOrb.ContractHoldsOrb.selector);
        orb.settle();
        assertEq(orb.lastSettlementTime(), 0);
        makeHolderAndWarp(user, 1 ether);
        orb.settle();
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function testFuzz_settleCorrect(uint96 bid, uint96 time) public {
        uint256 amount = bound(bid, orb.STARTING_PRICE(), orb.workaround_maxPrice());
        // warp ahead a random amount of time
        // remain under 1 year in total, so solvent
        uint256 timeOffset = bound(time, 0, 300 days);
        vm.warp(block.timestamp + timeOffset);
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.lastSettlementTime(), 0);
        // it warps 30 days by default
        makeHolderAndWarp(user, amount);

        uint256 userEffective = orb.effectiveFundsOf(user);
        uint256 ownerEffective = orb.effectiveFundsOf(owner);
        uint256 initialBalance = user.balance;

        orb.settle();
        assertEq(orb.fundsOf(user), userEffective);
        assertEq(orb.fundsOf(owner), ownerEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance);

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
        assertEq(user.balance, initialBalance);
    }

    function test_settleReturnsIfOwner() public {
        orb.workaround_setOrbHolder(owner);
        orb.workaround_settle();
        assertEq(orb.lastSettlementTime(), 0);
    }
}

contract HolderSolventTest is EricOrbTestBase {
    function test_holderSolventCorrectIfNotOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.lastSettlementTime(), 0);
        // it warps 30 days by default
        makeHolderAndWarp(user, 1 ether);
        assert(orb.holderSolvent());
        vm.warp(block.timestamp + 700 days);
        assertFalse(orb.holderSolvent());
    }

    function test_holderSolventCorrectIfOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.lastSettlementTime(), 0);
        vm.warp(block.timestamp + 4885828483 days);
        assertFalse(orb.holderSolvent());
    }
}

contract OwedSinceLastSettlementTest is EricOrbTestBase {
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

contract SetPriceTest is EricOrbTestBase {
    function test_setPriceRevertsIfNotHolder() public {
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(user, winningBid);
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
        makeHolderAndWarp(user, winningBid);
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
        makeHolderAndWarp(user, winningBid);
        vm.prank(user);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event NewPrice(uint256 oldPrice, uint256 newPrice);

    function test_setPriceRevertsIfMaxPrice() public {
        uint256 maxPrice = orb.workaround_maxPrice();
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(user, winningBid);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(EricOrb.InvalidNewPrice.selector, maxPrice + 1));
        orb.setPrice(maxPrice + 1);

        vm.expectEmit(false, false, false, true);
        emit NewPrice(10 ether, maxPrice);
        orb.setPrice(maxPrice);
    }
}

contract PurchaseTest is EricOrbTestBase {
    function test_revertsIfHeldByContract() public {
        vm.prank(user);
        vm.expectRevert(EricOrb.ContractHoldsOrb.selector);
        orb.purchase(0, 100);
    }

    function test_revertsIfHolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user2);
        vm.expectRevert(EricOrb.HolderInsolvent.selector);
        orb.purchase(0, 100);
    }

    function test_purchaseSettlesFirst() public {
        makeHolderAndWarp(user, 1 ether);
        // after making `user` the current holder of the orb, `makeHolderAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user2);
        orb.purchase{value: 1.1 ether}(1 ether, 2 ether);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function test_revertsIfWrongCurrentPrice() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(EricOrb.CurrentPriceIncorrect.selector, 2 ether, 1 ether));
        orb.purchase{value: 1.1 ether}(2 ether, 3 ether);
    }

    function test_revertsIfIfAlreadyHolder() public {
        makeHolderAndWarp(user, 1 ether);
        vm.expectRevert(EricOrb.AlreadyHolder.selector);
        vm.prank(user);
        orb.purchase{value: 1.1 ether}(1 ether, 3 ether);
    }

    function test_revertsIfInsufficientFunds() public {
        makeHolderAndWarp(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(EricOrb.InsufficientFunds.selector, 1 ether - 1, 1 ether));
        vm.prank(user2);
        orb.purchase{value: 1 ether - 1}(1 ether, 3 ether);
    }

    event Purchase(address indexed from, address indexed to);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event NewPrice(uint256 from, uint256 to);
    event Settlement(address indexed from, address indexed to, uint256 amount);

    function test_succeedsCorrectly() public {
        uint256 bidAmount = 1 ether;
        uint256 newPrice = 3 ether;
        uint256 purchaseAmount = bidAmount / 2;
        uint256 depositAmount = bidAmount / 2;
        // bidAmount will be the `_price` of the Orb
        makeHolderAndWarp(user, bidAmount);
        orb.settle();
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 userBefore = orb.fundsOf(user);
        vm.startPrank(user2);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user2), depositAmount);
        vm.expectEmit(true, true, false, true);
        // we just settled above
        emit Settlement(user, owner, 0);
        vm.expectEmit(false, false, false, true);
        emit NewPrice(bidAmount, newPrice);
        vm.expectEmit(true, true, false, false);
        emit Purchase(user, user2);
        vm.expectEmit(true, true, true, false);
        emit Transfer(user, user2, orb.workaround_orbId());
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        orb.purchase{value: purchaseAmount + 1}(bidAmount, newPrice);
        uint256 ownerRoyalties = ((bidAmount * 1000) / 10000);
        assertEq(orb.fundsOf(owner), ownerBefore + ownerRoyalties);
        assertEq(orb.fundsOf(user), userBefore + (bidAmount - ownerRoyalties));
        // The price of the Orb was 1 ether and user2 transfered 1 ether + 1 to buy it
        assertEq(orb.fundsOf(user2), 1);
        assertEq(orb.price(), newPrice);
    }

    function testFuzz_succeedsCorrectly(uint256 bidAmount, uint256 newPrice, uint256 buyPrice, uint256 diff) public {
        bidAmount = bound(bidAmount, 0.1 ether, orb.workaround_maxPrice() - 1);
        newPrice = bound(newPrice, 1, orb.workaround_maxPrice());
        buyPrice = bound(buyPrice, bidAmount + 1, orb.workaround_maxPrice());
        diff = bound(diff, 1, buyPrice);
        vm.deal(user2, buyPrice);
        /// Break up the amount between depositing and purchasing to test more scenarios
        uint256 purchaseAmount = buyPrice - diff;
        uint256 depositAmount = diff;
        // bidAmount will be the `_price` of the Orb
        makeHolderAndWarp(user, bidAmount);
        orb.settle();
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 userBefore = orb.fundsOf(user);
        vm.startPrank(user2);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user2), depositAmount);
        vm.expectEmit(true, true, false, true);
        // we just settled above
        emit Settlement(user, owner, 0);
        vm.expectEmit(false, false, false, true);
        emit NewPrice(bidAmount, newPrice);
        vm.expectEmit(true, true, false, false);
        emit Purchase(user, user2);
        vm.expectEmit(true, true, true, false);
        emit Transfer(user, user2, orb.workaround_orbId());
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        // We bound the purchaseAmount to be higher than the current price (bidAmount)
        orb.purchase{value: purchaseAmount}(bidAmount, newPrice);
        uint256 ownerRoyalties = ((bidAmount * 1000) / 10000);
        assertEq(orb.fundsOf(owner), ownerBefore + ownerRoyalties);
        assertEq(orb.fundsOf(user), userBefore + (bidAmount - ownerRoyalties));
        // User2 transfered buyPrice to the contract
        // User2 payed bidAmount
        console.log("buyPrice", buyPrice);
        console.log("bidAmount", bidAmount);
        console.log("diff", buyPrice - bidAmount);
        assertEq(orb.fundsOf(user2), buyPrice - bidAmount);
        assertEq(orb.price(), newPrice);
    }
}

contract ExitTest is EricOrbTestBase {
    function test_revertsIfNotHolder() public {
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(user, winningBid);
        vm.expectRevert(EricOrb.NotHolder.selector);
        vm.prank(user2);
        orb.exit();

        vm.prank(user);
        orb.exit();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
    }

    function test_revertsIfHolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user);
        vm.expectRevert(EricOrb.HolderInsolvent.selector);
        orb.exit();
        vm.warp(block.timestamp - 1300 days);
        vm.prank(user);
        orb.exit();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
    }

    function test_settlesFirst() public {
        makeHolderAndWarp(user, 1 ether);
        // after making `user` the current holder of the orb, `makeHolderAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user);
        orb.exit();
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event Foreclosure(address indexed from);
    event Withdrawal(address indexed recipient, uint256 amount);

    function test_succeedsCorrectly() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(user);
        assertEq(orb.ownerOf(orb.workaround_orbId()), user);
        vm.expectEmit(true, false, false, false);
        emit Foreclosure(user);
        vm.expectEmit(true, false, false, true);
        uint256 effectiveFunds = orb.effectiveFundsOf(user);
        emit Withdrawal(user, effectiveFunds);
        vm.prank(user);
        orb.exit();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
        assertEq(orb.price(), 0);
    }
}

contract ForecloseTest is EricOrbTestBase {
    function test_revertsIfNotHolderHeld() public {
        vm.expectRevert(EricOrb.ContractHoldsOrb.selector);
        vm.prank(user2);
        orb.foreclose();

        uint256 winningBid = 10 ether;
        makeHolderAndWarp(user, winningBid);
        vm.warp(block.timestamp + 100000 days);
        vm.prank(user2);
        orb.foreclose();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
    }

    event Foreclosure(address indexed from);

    function test_revertsifHolderSolvent() public {
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(user, winningBid);
        vm.expectRevert(EricOrb.HolderSolvent.selector);
        orb.foreclose();
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, false, false, false);
        emit Foreclosure(user);
        orb.foreclose();
    }

    function test_succeeds() public {
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(user, winningBid);
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, false, false, false);
        emit Foreclosure(user);
        assertEq(orb.ownerOf(orb.workaround_orbId()), user);
        orb.foreclose();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
        // TODO: check price = 0
    }
}

contract ForeclosureTimeTest is EricOrbTestBase {
    function test_returnsInfinityIfOwner() public {
        assertEq(orb.foreclosureTime(), type(uint256).max);
    }

    function test_returnsInfinityIfPriceZero() public {
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(user, winningBid);
        orb.workaround_setPrice(0);
        assertEq(orb.foreclosureTime(), type(uint256).max);
    }

    function test_correctCalculation() public {
        // uint256 remainingSeconds = (_funds[holder] * HOLDER_TAX_PERIOD * FEE_DENOMINATOR)
        //                             / (_price * HOLDER_TAX_NUMERATOR);
        uint256 winningBid = 10 ether;
        makeHolderAndWarp(user, winningBid);
        uint256 remaining = (orb.fundsOf(user) * 365 days * 10_000) / (winningBid * 1_000);
        uint256 lastSettlementTime = block.timestamp - 30 days;
        assertEq(orb.foreclosureTime(), remaining + lastSettlementTime);
    }
}

contract TriggerWithCleartextTest is EricOrbTestBase {
    event Triggered(address indexed from, uint256 indexed triggerId, bytes32 contentHash, uint256 time);

    function test_revertsIfLongLength() public {
        uint256 max = orb.MAX_CLEARTEXT_LENGTH();
        string memory text =
            "asfsafsfsafsafasdfasfdsakfjdsakfjasdlkfajsdlfsdlfkasdfjdjasfhasdljhfdaslkfjsda;kfjasdklfjasdklfjasd;ladlkfjasdfad;flksadjf;lkasdjf;lsadsdlsdlkfjas;dlkfjas;dlkfjsad;lkfjsad;lda;lkfj;kasjf;klsadjf;lsadsdlkfjasd;lkfjsad;lfkajsd;flkasdjf;lsdkfjas;lfkasdflkasdf;laskfj;asldkfjsad;lfs;lf;flksajf;lk";
        uint256 length = bytes(text).length;
        vm.expectRevert(abi.encodeWithSelector(EricOrb.CleartextTooLong.selector, length, max));
        orb.triggerWithCleartext(text);
    }

    function test_callsTriggerHashCorrectly() public {
        string memory text = "fjasdklfjasdklfjasdasdffakfjsad;lfs;lf;flksajf;lk";
        makeHolderAndWarp(user, 1 ether);
        vm.expectEmit(true, false, false, true);
        emit Triggered(user, 0, keccak256(abi.encodePacked(text)), block.timestamp);
        vm.prank(user);
        orb.triggerWithCleartext(text);
    }
}

contract TriggerWthHashTest is EricOrbTestBase {
    event Triggered(address indexed from, uint256 indexed triggerId, bytes32 contentHash, uint256 time);

    function test_revertWhen_NotHolder() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.prank(user2);
        vm.expectRevert(EricOrb.NotHolder.selector);
        orb.triggerWithHash(hash);

        vm.expectEmit(true, false, false, true);
        emit Triggered(user, 0, hash, block.timestamp);
        vm.prank(user);
        orb.triggerWithHash(hash);
    }

    function test_revertWhen_HolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(EricOrb.HolderInsolvent.selector);
        orb.triggerWithHash(hash);
    }

    function test_revertWhen_CooldownIncomplete() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.startPrank(user);
        orb.triggerWithHash(hash);
        assertEq(orb.triggers(0), hash);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                EricOrb.CooldownIncomplete.selector, block.timestamp - 1 days + orb.COOLDOWN() - block.timestamp
            )
        );
        orb.triggerWithHash(hash);
        assertEq(orb.triggers(1), bytes32(0));
        vm.warp(block.timestamp + orb.COOLDOWN() - 1 days + 1);
        orb.triggerWithHash(hash);
        assertEq(orb.triggers(1), hash);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.startPrank(user);
        vm.expectEmit(true, true, false, true);
        emit Triggered(user, 0, hash, block.timestamp);
        orb.triggerWithHash(hash);
        assertEq(orb.triggers(0), hash);
        assertEq(orb.lastTriggerTime(), block.timestamp);
        assertEq(orb.triggersCount(), 1);
    }
}

contract RecordTriggerCleartext is EricOrbTestBase {
    function test_revertWhen_NotHolder() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        vm.prank(user2);
        vm.expectRevert(EricOrb.NotHolder.selector);
        orb.recordTriggerCleartext(0, cleartext);

        vm.startPrank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        orb.recordTriggerCleartext(0, cleartext);
    }

    function test_revertWhen_HolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(EricOrb.HolderInsolvent.selector);
        orb.recordTriggerCleartext(0, cleartext);

        vm.warp(block.timestamp - 13130000 days);
        vm.startPrank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        orb.recordTriggerCleartext(0, cleartext);
    }

    function test_revertWhen_incorrectLength() public {
        makeHolderAndWarp(user, 1 ether);
        vm.startPrank(user);
        uint256 max = orb.MAX_CLEARTEXT_LENGTH();
        string memory cleartext =
            "asfsafsfsafsafasdfasfdsakfjdsakfjasdlkfajsdlfsdlfkasdfjdjasfhasdljhfdaslkfjsda;kfjasdklfjasdklfjasd;ladlkfjasdfad;flksadjf;lkasdjf;lsadsdlsdlkfjas;dlkfjas;dlkfjsad;lkfjsad;lda;lkfj;kasjf;klsadjf;lsadsdlkfjasd;lkfjsad;lfkajsd;flkasdjf;lsdkfjas;lfkasdflkasdf;laskfj;asldkfjsad;lfs;lf;flksajf;lk";
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        uint256 length = bytes(cleartext).length;
        vm.expectRevert(abi.encodeWithSelector(EricOrb.CleartextTooLong.selector, length, max));
        orb.recordTriggerCleartext(0, cleartext);

        vm.warp(block.timestamp + orb.COOLDOWN() + 1);
        cleartext = "this is a cleartext";
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        orb.recordTriggerCleartext(1, cleartext);
    }

    function test_revertWhen_cleartextMismatch() public {
        makeHolderAndWarp(user, 1 ether);
        vm.startPrank(user);
        string memory cleartext = "this is a cleartext";
        string memory cleartext2 = "this is not the same cleartext";
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        vm.expectRevert(
            abi.encodeWithSelector(
                EricOrb.CleartextHashMismatch.selector, keccak256(bytes(cleartext2)), keccak256(bytes(cleartext))
            )
        );
        orb.recordTriggerCleartext(0, cleartext2);

        orb.recordTriggerCleartext(0, cleartext);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        vm.startPrank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        orb.recordTriggerCleartext(0, cleartext);
    }
}

contract RespondTest is EricOrbTestBase {
    event Responded(address indexed from, uint256 indexed triggerId, bytes32 contentHash, uint256 time);

    function test_revertWhen_notOwner() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        orb.recordTriggerCleartext(0, cleartext);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.respond(0, response);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Responded(owner, 0, response, block.timestamp);
        orb.respond(0, response);
    }

    function test_revertWhen_triggerIdIncorrect() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        orb.recordTriggerCleartext(0, cleartext);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EricOrb.TriggerNotFound.selector, 1));
        orb.respond(1, response);

        vm.prank(owner);
        orb.respond(0, response);
    }

    function test_revertWhen_responseAlreadyExists() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        orb.recordTriggerCleartext(0, cleartext);
        vm.stopPrank();

        vm.startPrank(owner);
        orb.respond(0, response);
        vm.expectRevert(abi.encodeWithSelector(EricOrb.ResponseExists.selector, 0));
        orb.respond(0, response);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        orb.recordTriggerCleartext(0, cleartext);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Responded(owner, 0, response, block.timestamp);
        orb.respond(0, response);
        (bytes32 hash, uint256 time) = orb.responses(0);
        assertEq(hash, response);
        assertEq(time, block.timestamp);
    }
}

contract FlagResponseTest is EricOrbTestBase {
    event ResponseFlagged(address indexed from, uint256 indexed responseId);

    function test_revertWhen_NotHolder() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);
        vm.prank(user2);
        vm.expectRevert(EricOrb.NotHolder.selector);
        orb.flagResponse(0);

        vm.prank(user);
        orb.flagResponse(0);
    }

    function test_revertWhen_HolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(EricOrb.HolderInsolvent.selector);
        orb.flagResponse(0);

        vm.warp(block.timestamp - 13130000 days);
        vm.prank(user);
        orb.flagResponse(0);
    }

    function test_revertWhen_ResponseNotExist() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(EricOrb.ResponseNotFound.selector, 188));
        orb.flagResponse(188);

        orb.flagResponse(0);
    }

    function test_revertWhen_outsideFlaggingPeriod() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);

        vm.warp(block.timestamp + 100 days);
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(EricOrb.FlaggingPeriodExpired.selector, 0, 100 days, orb.RESPONSE_FLAGGING_PERIOD())
        );
        orb.flagResponse(0);

        vm.warp(block.timestamp - (100 days - orb.RESPONSE_FLAGGING_PERIOD()));
        orb.flagResponse(0);
    }

    function test_revertWhen_responseToPreviousHolder() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);

        vm.startPrank(user2);
        orb.purchase{value: 3 ether}(1 ether, 2 ether);
        vm.expectRevert(
            abi.encodeWithSelector(EricOrb.FlaggingPeriodExpired.selector, 0, orb.holderReceiveTime(), block.timestamp)
        );
        orb.flagResponse(0);

        vm.warp(block.timestamp + orb.COOLDOWN());
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        vm.stopPrank();
        vm.prank(owner);
        orb.respond(1, response);
        vm.prank(user2);
        orb.flagResponse(1);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.triggerWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);
        vm.prank(user);
        assertEq(orb.responseFlagged(0), false);
        assertEq(orb.flaggedResponsesCount(), 0);
        vm.expectEmit(true, false, false, true);
        emit ResponseFlagged(user, 0);
        vm.prank(user);
        orb.flagResponse(0);
        assertEq(orb.responseFlagged(0), true);
        assertEq(orb.flaggedResponsesCount(), 1);
    }
}
