// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {EricOrbTestBase} from "./EricOrbTestBase.sol";
import {EricOrb} from "contracts/EricOrb.sol";

contract FundsHandling is EricOrbTestBase {

    function test_effectiveFundsCorrectCalculation() public {
        uint256 amount1 = 1 ether;
        uint256 amount2 =  0.5 ether;
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

    event Deposit(address indexed user, uint256 amount);

    function test_depositRandomUser() public {
        assertEq(orb.fundsOf(user),0);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user, 1 ether);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user), 1 ether);
    }

    function testFuzz_depositRandomUser(uint256 amount) public {
        assertEq(orb.fundsOf(user),0);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user, amount);
        vm.deal(user, amount);
        vm.prank(user);
        orb.deposit{value: amount}();
        assertEq(orb.fundsOf(user), amount);
    }

    function test_depositHolderSolvent() public {
        assertEq(orb.fundsOf(user),0);
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
        emit Deposit(user,  depositAmount);
        vm.prank(user);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), funds + depositAmount);
    }

    function test_depositRevertsifHolderInsolvent() public {
        assertEq(orb.fundsOf(user),0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        makeHolderAndWarp(bidAmount);

        // let's make the user insolvent
        // fundsRequiredToBid(bidAmount) ensures enough
        // ether for 1 year, not two
        vm.warp(block.timestamp +  731 days);

        // if a random user deposits, it should work fine
        vm.prank(user2);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user2), 1 ether);

        // if the insolvent holder deposits, it should not work
        vm.expectRevert(EricOrb.HolderInsolvent.selector);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
    }

    event Withdrawl(address indexed user, uint256 amount);

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

    event Settlement(address indexed holder,address indexed owner, uint256 amount);

    function test_withdrawSettlesFirstIfHolder() public {
        assertEq(orb.fundsOf(user),0);
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
        assertEq(orb.fundsOf(user),0);
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


}

