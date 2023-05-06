// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {OrbHarness} from "./harness/OrbHarness.sol";
import {Orb} from "src/Orb.sol";

/* solhint-disable func-name-mixedcase */
contract OrbTestBase is Test {
    OrbHarness internal orb;

    address internal user;
    address internal user2;
    address internal beneficiary;
    address internal owner;

    uint256 internal startingBalance;

    function setUp() public {
        orb = new OrbHarness();
        user = address(0xBEEF);
        user2 = address(0xFEEEEEB);
        beneficiary = address(0xC0FFEE);
        startingBalance = 10000 ether;
        vm.deal(user, startingBalance);
        vm.deal(user2, startingBalance);
        owner = orb.owner();
    }

    function prankAndBid(address bidder, uint256 bidAmount) internal {
        uint256 finalAmount = fundsRequiredToBidOneYear(bidAmount);
        vm.deal(bidder, startingBalance + finalAmount);
        vm.prank(bidder);
        orb.bid{value: finalAmount}(bidAmount, bidAmount);
    }

    function makeHolderAndWarp(address newHolder, uint256 bid) public {
        orb.startAuction();
        prankAndBid(newHolder, bid);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);
    }

    function fundsRequiredToBidOneYear(uint256 amount) public view returns (uint256) {
        return amount + (amount * orb.holderTaxNumerator()) / orb.FEE_DENOMINATOR();
    }

    function effectiveFundsOf(address user_) public view returns (uint256) {
        uint256 unadjustedFunds = orb.fundsOf(user_);
        address holder = orb.ownerOf(orb.workaround_orbId());

        if (user_ == orb.owner()) {
            return unadjustedFunds;
        }

        if (user_ == beneficiary || user_ == holder) {
            uint256 owedFunds = orb.workaround_owedSinceLastSettlement();
            uint256 holderFunds = orb.fundsOf(holder);
            uint256 transferableToBeneficiary = holderFunds <= owedFunds ? holderFunds : owedFunds;

            if (user_ == beneficiary) {
                return unadjustedFunds + transferableToBeneficiary;
            }
            if (user_ == holder) {
                return unadjustedFunds - transferableToBeneficiary;
            }
        }

        return unadjustedFunds;
    }
}

contract InitialStateTest is OrbTestBase {
    // Test that the initial state is correct
    function test_initialState() public {
        assertEq(address(orb), orb.ownerOf(orb.workaround_orbId()));
        assertFalse(orb.auctionRunning());
        assertEq(orb.owner(), address(this));
        assertEq(orb.beneficiary(), address(0xC0FFEE));

        assertEq(orb.price(), 0);
        assertEq(orb.lastInvocationTime(), 0);
        assertEq(orb.invocationCount(), 0);

        assertEq(orb.flaggedResponsesCount(), 0);

        assertEq(orb.auctionStartTime(), 0);
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.leadingBid(), 0);

        assertEq(orb.lastSettlementTime(), 0);
        assertEq(orb.holderReceiveTime(), 0);
    }

    function test_constants() public {
        assertEq(orb.CLEARTEXT_MAXIMUM_LENGTH(), 280);

        assertEq(orb.FEE_DENOMINATOR(), 10000);
        assertEq(orb.HOLDER_TAX_PERIOD(), 365 days);

        assertEq(orb.workaround_orbId(), 69);
        assertEq(orb.workaround_infinity(), type(uint256).max);
        assertEq(orb.workaround_maxPrice(), 2 ** 128);
        assertEq(orb.workaround_baseUrl(), "https://static.orb.land/orb/");
    }
}

contract TransfersRevertTest is OrbTestBase {
    function test_transfersRevert() public {
        address newOwner = address(0xBEEF);
        uint256 id = orb.workaround_orbId();
        vm.expectRevert(Orb.TransferringNotSupported.selector);
        orb.transferFrom(address(this), newOwner, id);
        vm.expectRevert(Orb.TransferringNotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, id);
        vm.expectRevert(Orb.TransferringNotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, id, bytes(""));
    }
}

contract MinimumBidTest is OrbTestBase {
    function test_minimumBidReturnsCorrectValues() public {
        uint256 bidAmount = 0.6 ether;
        orb.startAuction();
        assertEq(orb.minimumBid(), orb.auctionStartingPrice());
        prankAndBid(user, bidAmount);
        assertEq(orb.minimumBid(), bidAmount + orb.auctionMinimumBidStep());
    }
}

contract StartAuctionTest is OrbTestBase {
    function test_startAuctionOnlyOrbCreator() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("Ownable: caller is not the owner");
        orb.startAuction();
        orb.startAuction();
        assertEq(orb.auctionStartTime(), block.timestamp);
    }

    event AuctionStart(uint256 auctionStartTime, uint256 auctionEndTime);

    function test_startAuctionCorrectly() public {
        assertEq(orb.auctionStartTime(), 0);
        orb.workaround_setLeadingBid(10);
        orb.workaround_setLeadingBidder(address(0xBEEF));
        vm.expectEmit(true, true, false, false);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration());
        orb.startAuction();
        assertEq(orb.auctionStartTime(), block.timestamp);
        assertEq(orb.auctionEndTime(), block.timestamp + orb.auctionMinimumDuration());
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
    }

    function test_startAuctionOnlyContractHeld() public {
        orb.workaround_setOrbHolder(address(0xBEEF));
        vm.expectRevert(Orb.ContractDoesNotHoldOrb.selector);
        orb.startAuction();
        orb.workaround_setOrbHolder(address(orb));
        vm.expectEmit(true, true, false, false);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration());
        orb.startAuction();
    }

    function test_startAuctionNotDuringAuction() public {
        vm.expectEmit(true, true, false, false);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration());
        orb.startAuction();
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.startAuction();
    }
}

contract BidTest is OrbTestBase {
    function test_bidOnlyDuringAuction() public {
        uint256 bidAmount = 0.6 ether;
        vm.deal(user, bidAmount);
        vm.expectRevert(Orb.AuctionNotRunning.selector);
        vm.prank(user);
        orb.bid{value: bidAmount}(bidAmount, bidAmount);
        orb.startAuction();
        assertEq(orb.leadingBid(), 0 ether);
        prankAndBid(user, bidAmount);
        assertEq(orb.leadingBid(), bidAmount);
    }

    function test_bidUsesTotalFunds() public {
        orb.deposit{value: 1 ether}();
        orb.startAuction();
        vm.prank(user);
        assertEq(orb.leadingBid(), 0 ether);
        prankAndBid(user, 0.5 ether);
        assertEq(orb.leadingBid(), 0.5 ether);
    }

    function test_bidRevertsIfBeneficiary() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        vm.deal(beneficiary, amount);
        vm.expectRevert(abi.encodeWithSelector(Orb.BeneficiaryDisallowed.selector));
        vm.prank(beneficiary);
        orb.bid{value: amount}(amount, amount);

        // will not revert
        prankAndBid(user, amount);
        assertEq(orb.leadingBid(), amount);
    }

    function test_bidRevertsIfLtMinimumBid() public {
        orb.startAuction();
        // minimum bid will be the STARTING_PRICE
        uint256 amount = orb.minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(Orb.InsufficientBid.selector, amount, orb.minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);

        // Add back + 1 to amount
        amount++;
        // will not revert
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);
        assertEq(orb.leadingBid(), amount);

        // minimum bid will be the winning bid + MINIMUM_BID_STEP
        amount = orb.minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(Orb.InsufficientBid.selector, amount, orb.minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);
    }

    function test_bidRevertsIfLtFundsRequired() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        uint256 funds = amount - 1;
        vm.expectRevert(abi.encodeWithSelector(Orb.InsufficientFunds.selector, funds, funds + 1));
        vm.prank(user);
        orb.bid{value: funds}(amount, amount);

        funds++;
        vm.prank(user);
        // will not revert
        orb.bid{value: funds}(amount, amount);
        assertEq(orb.leadingBid(), amount);
    }

    function test_bidRevertsIfPriceTooHigh() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        uint256 price = orb.workaround_maxPrice() + 1;
        vm.expectRevert(abi.encodeWithSelector(Orb.InvalidNewPrice.selector, price));
        vm.prank(user);
        orb.bid{value: amount}(amount, price);

        // Bring price back to acceptable amount
        price--;
        // will not revert
        vm.prank(user);
        orb.bid{value: amount}(amount, price);
        assertEq(orb.leadingBid(), amount);
        assertEq(orb.price(), orb.workaround_maxPrice());
    }

    event AuctionBid(address indexed bidder, uint256 bid);

    function test_bidSetsCorrectState() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        uint256 funds = fundsRequiredToBidOneYear(amount);
        assertEq(orb.leadingBid(), 0 ether);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.fundsOf(user), 0);
        assertEq(address(orb).balance, 0);
        uint256 auctionEndTime = orb.auctionEndTime();

        vm.expectEmit(true, false, false, true);
        emit AuctionBid(user, amount);
        prankAndBid(user, amount);

        assertEq(orb.leadingBid(), amount);
        assertEq(orb.leadingBidder(), user);
        assertEq(orb.price(), amount);
        assertEq(orb.fundsOf(user), funds);
        assertEq(address(orb).balance, funds);
        assertEq(orb.auctionEndTime(), auctionEndTime);
    }

    mapping(address => uint256) internal fundsOfUser;

    event AuctionFinalization(address indexed winner, uint256 winningBid);

    function testFuzz_bidSetsCorrectState(address[16] memory bidders, uint128[16] memory amounts) public {
        orb.startAuction();
        uint256 contractBalance;
        for (uint256 i = 1; i < 16; i++) {
            uint256 amount = bound(amounts[i], orb.minimumBid(), orb.minimumBid() + 1_000_000_000);
            address bidder = bidders[i];
            vm.assume(bidder != address(0) && bidder != address(orb) && bidder != beneficiary);

            uint256 funds = fundsRequiredToBidOneYear(amount);

            fundsOfUser[bidder] += funds;

            vm.expectEmit(true, false, false, true);
            emit AuctionBid(bidder, amount);
            prankAndBid(bidder, amount);
            contractBalance += funds;

            assertEq(orb.leadingBid(), amount);
            assertEq(orb.leadingBidder(), bidder);
            assertEq(orb.price(), amount);
            assertEq(orb.fundsOf(bidder), fundsOfUser[bidder]);
            assertEq(address(orb).balance, contractBalance);
        }
        vm.expectEmit(true, false, false, true);
        emit AuctionFinalization(orb.leadingBidder(), orb.leadingBid());
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
    }

    function test_bidExtendsAuction() public {
        assertEq(orb.auctionEndTime(), 0);
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        // auctionEndTime = block.timestamp + auctionMinimumDuration
        uint256 auctionEndTime = orb.auctionEndTime();
        // set block.timestamp to auctionEndTime - auctionBidExtension
        vm.warp(auctionEndTime - orb.auctionBidExtension());
        prankAndBid(user, amount);
        // didn't change because block.timestamp + auctionBidExtension = auctionEndTime
        assertEq(orb.auctionEndTime(), auctionEndTime);

        vm.warp(auctionEndTime - orb.auctionBidExtension() + 50);
        amount = orb.minimumBid();
        prankAndBid(user, amount);
        // change because block.timestamp + auctionBidExtension + 50 >  auctionEndTime
        assertEq(orb.auctionEndTime(), auctionEndTime + 50);
    }
}

contract FinalizeAuctionTest is OrbTestBase {
    event AuctionFinalization(address indexed winner, uint256 winningBid);

    function test_finalizeAuctionRevertsDuringAuction() public {
        orb.startAuction();
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.finalizeAuction();

        vm.warp(orb.auctionEndTime() + 1);
        vm.expectEmit(true, false, false, true);
        emit AuctionFinalization(address(0), 0);
        orb.finalizeAuction();
    }

    function test_finalizeAuctionRevertsIfAuctionNotStarted() public {
        vm.expectRevert(Orb.AuctionNotStarted.selector);
        orb.finalizeAuction();
        orb.startAuction();
        // auctionEndTime != 0
        assertEq(orb.auctionEndTime(), block.timestamp + orb.auctionMinimumDuration());
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.finalizeAuction();
    }

    function test_finalizeAuctionWithoutWinner() public {
        orb.startAuction();
        vm.warp(orb.auctionEndTime() + 1);
        vm.expectEmit(true, false, false, true);
        emit AuctionFinalization(address(0), 0);
        orb.finalizeAuction();
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.auctionStartTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), 0);
    }

    event PriceUpdate(uint256 previousPrice, uint256 newPrice);

    function test_finalizeAuctionWithWinner() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        uint256 funds = fundsRequiredToBidOneYear(amount);
        // Bid `amount` and transfer `funds` to the contract
        prankAndBid(user, amount);
        vm.warp(orb.auctionEndTime() + 1);

        // Assert storage before
        assertEq(orb.leadingBidder(), user);
        assertEq(orb.leadingBid(), amount);
        assertEq(orb.price(), amount);
        assertEq(orb.fundsOf(user), funds);
        assertEq(orb.fundsOf(address(orb)), 0);

        vm.expectEmit(true, false, false, true);
        emit AuctionFinalization(user, amount);
        vm.expectEmit(false, false, false, true);
        emit PriceUpdate(0, amount);

        orb.finalizeAuction();

        // Assert storage after
        // storage that is reset
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.auctionStartTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), amount);

        // storage that persists
        assertEq(address(orb).balance, funds);
        assertEq(orb.fundsOf(beneficiary), amount);
        assertEq(orb.ownerOf(orb.workaround_orbId()), user);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.lastInvocationTime(), block.timestamp - orb.cooldown());
        assertEq(orb.fundsOf(user), funds - amount);
        assertEq(orb.price(), amount);
    }
}

contract EffectiveFundsOfTest is OrbTestBase {
    function test_effectiveFundsCorrectCalculation() public {
        uint256 amount1 = 1 ether;
        uint256 amount2 = 0.5 ether;
        uint256 funds1 = fundsRequiredToBidOneYear(amount1);
        uint256 funds2 = fundsRequiredToBidOneYear(amount2);
        orb.startAuction();
        prankAndBid(user2, amount2);
        prankAndBid(user, amount1);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 1 days);

        // One day has passed since the orb holder got the orb
        // for bid = 1 ether. That means that the price of the
        // orb is now 1 ether. Thus the Orb beneficiary is owed the tax
        // for 1 day.

        // The user actually transfered `funds1` and `funds2` respectively
        // ether to the contract
        uint256 owed = orb.workaround_owedSinceLastSettlement();
        assertEq(effectiveFundsOf(beneficiary), owed + amount1);
        // The user that won the auction and is holding the orb
        // has the funds they deposited, minus the tax and minus the bid
        // amount
        assertEq(effectiveFundsOf(user), funds1 - owed - amount1);
        // The user that didn't won the auction, has the funds they
        // deposited
        assertEq(effectiveFundsOf(user2), funds2);
    }

    function testFuzz_effectiveFundsCorrectCalculation(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1 ether, orb.workaround_maxPrice());
        amount2 = bound(amount2, orb.auctionStartingPrice(), amount1 - orb.auctionMinimumBidStep());
        uint256 funds1 = fundsRequiredToBidOneYear(amount1);
        uint256 funds2 = fundsRequiredToBidOneYear(amount2);
        orb.startAuction();
        prankAndBid(user2, amount2);
        prankAndBid(user, amount1);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 1 days);

        // One day has passed since the orb holder got the orb
        // for bid = 1 ether. That means that the price of the
        // orb is now 1 ether. Thus the Orb beneficiary is owed the tax
        // for 1 day.

        // The user actually transfered `funds1` and `funds2` respectively
        // ether to the contract
        uint256 owed = orb.workaround_owedSinceLastSettlement();
        assertEq(effectiveFundsOf(beneficiary), owed + amount1);
        // The user that won the auction and is holding the orb
        // has the funds they deposited, minus the tax and minus the bid
        // amount
        assertEq(effectiveFundsOf(user), funds1 - owed - amount1);
        // The user that didn't won the auction, has the funds they
        // deposited
        assertEq(effectiveFundsOf(user2), funds2);
    }
}

contract DepositTest is OrbTestBase {
    event Deposit(address indexed depositor, uint256 amount);

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
        // fundsRequiredToBidOneYear(bidAmount)
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
        // fundsRequiredToBidOneYear(bidAmount)
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
        // fundsRequiredToBidOneYear(bidAmount) ensures enough
        // ether for 1 year, not two
        vm.warp(block.timestamp + 731 days);

        // if a random user deposits, it should work fine
        vm.prank(user2);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user2), 1 ether);

        // if the insolvent holder deposits, it should not work
        vm.expectRevert(Orb.HolderInsolvent.selector);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
    }
}

contract WithdrawTest is OrbTestBase {
    event Withdrawal(address indexed recipient, uint256 amount);

    function test_withdrawRevertsIfLeadingBidder() public {
        uint256 bidAmount = 1 ether;
        orb.startAuction();
        prankAndBid(user, bidAmount);
        vm.expectRevert(Orb.NotPermittedForLeadingBidder.selector);
        vm.prank(user);
        orb.withdraw(1);

        vm.expectRevert(Orb.NotPermittedForLeadingBidder.selector);
        vm.prank(user);
        orb.withdrawAll();

        // user is no longer the leadingBidder
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

    event Settlement(address indexed holder, address indexed beneficiary, uint256 amount);

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
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();

        vm.warp(block.timestamp + 30 days);

        // beneficiaryEffective = beneficiaryFunds + transferableToBeneficiary
        // userEffective = userFunds - transferableToBeneficiary
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 transferableToBeneficiary = beneficiaryEffective - beneficiaryFunds;
        uint256 initialBalance = user.balance;

        vm.expectEmit(true, true, false, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);

        vm.prank(user);
        orb.withdraw(withdrawAmount);

        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + withdrawAmount);

        // move ahead 10 days;
        vm.warp(block.timestamp + 10 days);

        // not holder
        vm.prank(user2);
        initialBalance = user2.balance;
        orb.withdraw(withdrawAmount);
        assertEq(orb.fundsOf(user2), fundsRequiredToBidOneYear(smallBidAmount) - withdrawAmount);
        assertEq(user2.balance, initialBalance + withdrawAmount);
    }

    function test_withdrawAllForBeneficiarySettlesAndWithdraws() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 10 ether;
        uint256 smallBidAmount = 0.5 ether;

        orb.startAuction();
        // user2 bids
        prankAndBid(user2, smallBidAmount);
        // user1 bids and becomes the winning bidder
        prankAndBid(user, bidAmount);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();

        vm.warp(block.timestamp + 30 days);

        // beneficiaryEffective = beneficiaryFunds + transferableToBeneficiary
        // userEffective = userFunds - transferableToBeneficiary
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 transferableToBeneficiary = beneficiaryEffective - beneficiaryFunds;
        uint256 initialBalance = beneficiary.balance;

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);
        orb.settle();

        assertEq(orb.fundsOf(beneficiary), beneficiaryFunds + transferableToBeneficiary);

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(beneficiary, beneficiaryFunds + transferableToBeneficiary);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(user), userEffective);
        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(beneficiary.balance, initialBalance + beneficiaryEffective);
    }

    function testFuzz_withdrawSettlesFirstIfHolder(uint256 bidAmount, uint256 withdrawAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, orb.auctionStartingPrice(), orb.workaround_maxPrice());
        makeHolderAndWarp(user, bidAmount);

        // beneficiaryEffective = beneficiaryFunds + transferableToBeneficiary
        // userEffective = userFunds - transferableToBeneficiary
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 transferableToBeneficiary = beneficiaryEffective - beneficiaryFunds;
        uint256 initialBalance = user.balance;

        vm.expectEmit(true, true, false, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);

        vm.prank(user);
        withdrawAmount = bound(withdrawAmount, 0, userEffective - 1);
        orb.withdraw(withdrawAmount);
        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + withdrawAmount);

        vm.prank(user);
        orb.withdrawAll();
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + userEffective);
    }

    function test_withdrawRevertsIfInsufficientFunds() public {
        vm.startPrank(user);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(Orb.InsufficientFunds.selector, 1 ether, 1 ether + 1));
        orb.withdraw(1 ether + 1);
        assertEq(orb.fundsOf(user), 1 ether);
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(user, 1 ether);
        orb.withdraw(1 ether);
        assertEq(orb.fundsOf(user), 0);
    }
}

contract SettleTest is OrbTestBase {
    event Settlement(address indexed holder, address indexed beneficiary, uint256 amount);

    function test_settleOnlyIfHolderHeld() public {
        vm.expectRevert(Orb.ContractHoldsOrb.selector);
        orb.settle();
        assertEq(orb.lastSettlementTime(), 0);
        makeHolderAndWarp(user, 1 ether);
        orb.settle();
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function testFuzz_settleCorrect(uint96 bid, uint96 time) public {
        uint256 amount = bound(bid, orb.auctionStartingPrice(), orb.workaround_maxPrice());
        // warp ahead a random amount of time
        // remain under 1 year in total, so solvent
        uint256 timeOffset = bound(time, 0, 300 days);
        vm.warp(block.timestamp + timeOffset);
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), 0);
        // it warps 30 days by default
        makeHolderAndWarp(user, amount);

        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 initialBalance = user.balance;

        orb.settle();
        assertEq(orb.fundsOf(user), userEffective);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
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
        // beneficiaryEffective is from the last time it settled
        assertEq(orb.fundsOf(beneficiary), transferable + beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance);
    }

    function test_settleReturnsIfOwner() public {
        orb.workaround_setOrbHolder(owner);
        orb.workaround_settle();
        assertEq(orb.lastSettlementTime(), 0);
    }
}

contract HolderSolventTest is OrbTestBase {
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

contract OwedSinceLastSettlementTest is OrbTestBase {
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

contract SetPriceTest is OrbTestBase {
    function test_setPriceRevertsIfNotHolder() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.expectRevert(Orb.NotHolder.selector);
        vm.prank(user2);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 10 ether);

        vm.prank(user);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 1 ether);
    }

    function test_setPriceRevertsIfHolderInsolvent() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 600 days);
        vm.startPrank(user);
        vm.expectRevert(Orb.HolderInsolvent.selector);
        orb.setPrice(1 ether);

        // As the user can't deposit funds to become solvent again
        // we modify a variable to trick the contract
        orb.workaround_setLastSettlementTime(block.timestamp);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
    }

    function test_setPriceSettlesBefore() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.prank(user);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event PriceUpdate(uint256 previousPrice, uint256 newPrice);

    function test_setPriceRevertsIfMaxPrice() public {
        uint256 maxPrice = orb.workaround_maxPrice();
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Orb.InvalidNewPrice.selector, maxPrice + 1));
        orb.setPrice(maxPrice + 1);

        vm.expectEmit(false, false, false, true);
        emit PriceUpdate(10 ether, maxPrice);
        orb.setPrice(maxPrice);
    }
}

contract PurchaseTest is OrbTestBase {
    function test_revertsIfHeldByContract() public {
        vm.prank(user);
        vm.expectRevert(Orb.ContractHoldsOrb.selector);
        orb.purchase(0, 100);
    }

    function test_revertsIfHolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user2);
        vm.expectRevert(Orb.HolderInsolvent.selector);
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

    function test_revertsIfBeneficiary() public {
        makeHolderAndWarp(user, 1 ether);
        vm.deal(beneficiary, 1.1 ether);
        vm.prank(beneficiary);
        vm.expectRevert(abi.encodeWithSelector(Orb.BeneficiaryDisallowed.selector));
        orb.purchase{value: 1.1 ether}(1 ether, 3 ether);

        // does not revert
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user2);
        orb.purchase{value: 1.1 ether}(1 ether, 3 ether);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function test_revertsIfWrongCurrentPrice() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Orb.CurrentPriceIncorrect.selector, 2 ether, 1 ether));
        orb.purchase{value: 1.1 ether}(2 ether, 3 ether);
    }

    function test_revertsIfIfAlreadyHolder() public {
        makeHolderAndWarp(user, 1 ether);
        vm.expectRevert(Orb.AlreadyHolder.selector);
        vm.prank(user);
        orb.purchase{value: 1.1 ether}(1 ether, 3 ether);
    }

    function test_revertsIfInsufficientFunds() public {
        makeHolderAndWarp(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(Orb.InsufficientFunds.selector, 1 ether - 1, 1 ether));
        vm.prank(user2);
        orb.purchase{value: 1 ether - 1}(1 ether, 3 ether);
    }

    event Purchase(address indexed seller, address indexed buyer, uint256 price);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event PriceUpdate(uint256 previousPrice, uint256 newPrice);
    event Settlement(address indexed holder, address indexed beneficiary, uint256 amount);

    function test_beneficiaryAllProceedsIfOwnerSells() public {
        uint256 bidAmount = 1 ether;
        uint256 newPrice = 3 ether;
        uint256 purchaseAmount = bidAmount / 2;
        uint256 depositAmount = bidAmount / 2;
        // bidAmount will be the `_price` of the Orb
        makeHolderAndWarp(owner, bidAmount);
        orb.settle();
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        vm.startPrank(user);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), userBefore + depositAmount);
        vm.expectEmit(true, true, false, false);
        emit Purchase(owner, user, bidAmount);
        vm.expectEmit(true, true, true, false);
        emit Transfer(owner, user, orb.workaround_orbId());
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        orb.purchase{value: purchaseAmount + 1}(bidAmount, newPrice);
        uint256 beneficiaryRoyalty = bidAmount;
        assertEq(orb.fundsOf(beneficiary), beneficiaryBefore + beneficiaryRoyalty);
        assertEq(orb.fundsOf(owner), ownerBefore);
        // The price of the Orb was 1 ether and user2 transfered 1 ether + 1 to buy it
        assertEq(orb.fundsOf(user), 1);
        assertEq(orb.price(), newPrice);
    }

    function test_succeedsCorrectly() public {
        uint256 bidAmount = 1 ether;
        uint256 newPrice = 3 ether;
        uint256 purchaseAmount = bidAmount / 2;
        uint256 depositAmount = bidAmount / 2;
        // bidAmount will be the `_price` of the Orb
        makeHolderAndWarp(user, bidAmount);
        orb.settle();
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        vm.startPrank(user2);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user2), depositAmount);
        vm.expectEmit(true, true, false, true);
        // we just settled above
        emit Settlement(user, beneficiary, 0);
        vm.expectEmit(false, false, false, true);
        emit PriceUpdate(bidAmount, newPrice);
        vm.expectEmit(true, true, false, true);
        emit Purchase(user, user2, bidAmount);
        vm.expectEmit(true, true, true, false);
        emit Transfer(user, user2, orb.workaround_orbId());
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        orb.purchase{value: purchaseAmount + 1}(bidAmount, newPrice);
        uint256 beneficiaryRoyalty = ((bidAmount * 1000) / 10000);
        assertEq(orb.fundsOf(beneficiary), beneficiaryBefore + beneficiaryRoyalty);
        assertEq(orb.fundsOf(user), userBefore + (bidAmount - beneficiaryRoyalty));
        assertEq(orb.fundsOf(owner), ownerBefore);
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
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        vm.startPrank(user2);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user2), depositAmount);
        vm.expectEmit(true, true, false, true);
        // we just settled above
        emit Settlement(user, beneficiary, 0);
        vm.expectEmit(false, false, false, true);
        emit PriceUpdate(bidAmount, newPrice);
        vm.expectEmit(true, true, false, true);
        emit Purchase(user, user2, bidAmount);
        vm.expectEmit(true, true, true, false);
        emit Transfer(user, user2, orb.workaround_orbId());
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        // We bound the purchaseAmount to be higher than the current price (bidAmount)
        orb.purchase{value: purchaseAmount}(bidAmount, newPrice);
        uint256 beneficiaryRoyalty = ((bidAmount * 1000) / 10000);
        assertEq(orb.fundsOf(beneficiary), beneficiaryBefore + beneficiaryRoyalty);
        assertEq(orb.fundsOf(user), userBefore + (bidAmount - beneficiaryRoyalty));
        assertEq(orb.fundsOf(owner), ownerBefore);
        // User2 transfered buyPrice to the contract
        // User2 paid bidAmount
        assertEq(orb.fundsOf(user2), buyPrice - bidAmount);
        assertEq(orb.price(), newPrice);
    }
}

contract RelinquishmentTest is OrbTestBase {
    function test_revertsIfNotHolder() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.expectRevert(Orb.NotHolder.selector);
        vm.prank(user2);
        orb.relinquish();

        vm.prank(user);
        orb.relinquish();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
    }

    function test_revertsIfHolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user);
        vm.expectRevert(Orb.HolderInsolvent.selector);
        orb.relinquish();
        vm.warp(block.timestamp - 1300 days);
        vm.prank(user);
        orb.relinquish();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
    }

    function test_settlesFirst() public {
        makeHolderAndWarp(user, 1 ether);
        // after making `user` the current holder of the orb, `makeHolderAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user);
        orb.relinquish();
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event Foreclosure(address indexed formerHolder, bool indexed voluntary);
    event Withdrawal(address indexed recipient, uint256 amount);

    function test_succeedsCorrectly() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(user);
        assertEq(orb.ownerOf(orb.workaround_orbId()), user);
        vm.expectEmit(true, true, false, false);
        emit Foreclosure(user, true);
        vm.expectEmit(true, false, false, true);
        uint256 effectiveFunds = effectiveFundsOf(user);
        emit Withdrawal(user, effectiveFunds);
        vm.prank(user);
        orb.relinquish();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
        assertEq(orb.price(), 0);
    }
}

contract ForecloseTest is OrbTestBase {
    function test_revertsIfNotHolderHeld() public {
        vm.expectRevert(Orb.ContractHoldsOrb.selector);
        vm.prank(user2);
        orb.foreclose();

        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 100000 days);
        vm.prank(user2);
        orb.foreclose();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
    }

    event Foreclosure(address indexed formerHolder, bool indexed voluntary);

    function test_revertsifHolderSolvent() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.expectRevert(Orb.HolderSolvent.selector);
        orb.foreclose();
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, true, false, false);
        emit Foreclosure(user, false);
        orb.foreclose();
    }

    function test_succeeds() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, true, false, false);
        emit Foreclosure(user, false);
        assertEq(orb.ownerOf(orb.workaround_orbId()), user);
        orb.foreclose();
        assertEq(orb.ownerOf(orb.workaround_orbId()), address(orb));
        assertEq(orb.price(), 0);
    }
}

contract ForeclosureTimeTest is OrbTestBase {
    function test_returnsInfinityIfOwner() public {
        assertEq(orb.foreclosureTime(), type(uint256).max);
    }

    function test_returnsInfinityIfPriceZero() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        orb.workaround_setPrice(0);
        assertEq(orb.foreclosureTime(), type(uint256).max);
    }

    function test_correctCalculation() public {
        // uint256 remainingSeconds = (_funds[holder] * HOLDER_TAX_PERIOD * FEE_DENOMINATOR)
        //                             / (_price * HOLDER_TAX_NUMERATOR);
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        uint256 remaining = (orb.fundsOf(user) * 365 days * 10_000) / (leadingBid * 1_000);
        uint256 lastSettlementTime = block.timestamp - 30 days;
        assertEq(orb.foreclosureTime(), remaining + lastSettlementTime);
    }
}

contract InvokeWithCleartextTest is OrbTestBase {
    event Invocation(address indexed invoker, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);
    event CleartextRecording(uint256 indexed invocationId, string cleartext);

    function test_revertsIfLongLength() public {
        uint256 max = orb.CLEARTEXT_MAXIMUM_LENGTH();
        string memory text =
            "asfsafsfsafsafasdfasfdsakfjdsakfjasdlkfajsdlfsdlfkasdfjdjasfhasdljhfdaslkfjsda;kfjasdklfjasdklfjasd;ladlkfjasdfad;flksadjf;lkasdjf;lsadsdlsdlkfjas;dlkfjas;dlkfjsad;lkfjsad;lda;lkfj;kasjf;klsadjf;lsadsdlkfjasd;lkfjsad;lfkajsd;flkasdjf;lsdkfjas;lfkasdflkasdf;laskfj;asldkfjsad;lfs;lf;flksajf;lk"; // solhint-disable-line
        uint256 length = bytes(text).length;
        vm.expectRevert(abi.encodeWithSelector(Orb.CleartextTooLong.selector, length, max));
        orb.invokeWithCleartext(text);
    }

    function test_callsInvokeWithHashCorrectly() public {
        string memory text = "fjasdklfjasdklfjasdasdffakfjsad;lfs;lf;flksajf;lk";
        makeHolderAndWarp(user, 1 ether);
        vm.expectEmit(true, false, false, true);
        emit CleartextRecording(0, text);
        vm.expectEmit(true, true, false, true);
        emit Invocation(user, 0, keccak256(abi.encodePacked(text)), block.timestamp);
        vm.prank(user);
        orb.invokeWithCleartext(text);
    }
}

contract InvokeWthHashTest is OrbTestBase {
    event Invocation(address indexed invoker, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);

    function test_revertWhen_NotHolder() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.prank(user2);
        vm.expectRevert(Orb.NotHolder.selector);
        orb.invokeWithHash(hash);

        vm.expectEmit(true, false, false, true);
        emit Invocation(user, 0, hash, block.timestamp);
        vm.prank(user);
        orb.invokeWithHash(hash);
    }

    function test_revertWhen_HolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(Orb.HolderInsolvent.selector);
        orb.invokeWithHash(hash);
    }

    function test_revertWhen_CooldownIncomplete() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.startPrank(user);
        orb.invokeWithHash(hash);
        assertEq(orb.invocations(0), hash);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                Orb.CooldownIncomplete.selector, block.timestamp - 1 days + orb.cooldown() - block.timestamp
            )
        );
        orb.invokeWithHash(hash);
        assertEq(orb.invocations(1), bytes32(0));
        vm.warp(block.timestamp + orb.cooldown() - 1 days + 1);
        orb.invokeWithHash(hash);
        assertEq(orb.invocations(1), hash);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.startPrank(user);
        vm.expectEmit(true, true, false, true);
        emit Invocation(user, 0, hash, block.timestamp);
        orb.invokeWithHash(hash);
        assertEq(orb.invocations(0), hash);
        assertEq(orb.lastInvocationTime(), block.timestamp);
        assertEq(orb.invocationCount(), 1);
    }
}

contract RecordInvocationCleartext is OrbTestBase {
    event CleartextRecording(uint256 indexed invocationId, string cleartext);

    function test_revertWhen_NotHolder() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        vm.prank(user2);
        vm.expectRevert(Orb.NotHolder.selector);
        orb.recordInvocationCleartext(0, cleartext);

        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        orb.recordInvocationCleartext(0, cleartext);
    }

    function test_revertWhen_HolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(Orb.HolderInsolvent.selector);
        orb.recordInvocationCleartext(0, cleartext);

        vm.warp(block.timestamp - 13130000 days);
        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        orb.recordInvocationCleartext(0, cleartext);
    }

    function test_revertWhen_incorrectLength() public {
        makeHolderAndWarp(user, 1 ether);
        vm.startPrank(user);
        uint256 max = orb.CLEARTEXT_MAXIMUM_LENGTH();
        string memory cleartext =
            "asfsafsfsafsafasdfasfdsakfjdsakfjasdlkfajsdlfsdlfkasdfjdjasfhasdljhfdaslkfjsda;kfjasdklfjasdklfjasd;ladlkfjasdfad;flksadjf;lkasdjf;lsadsdlsdlkfjas;dlkfjas;dlkfjsad;lkfjsad;lda;lkfj;kasjf;klsadjf;lsadsdlkfjasd;lkfjsad;lfkajsd;flkasdjf;lsdkfjas;lfkasdflkasdf;laskfj;asldkfjsad;lfs;lf;flksajf;lk"; // solhint-disable-line
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        uint256 length = bytes(cleartext).length;
        vm.expectRevert(abi.encodeWithSelector(Orb.CleartextTooLong.selector, length, max));
        orb.recordInvocationCleartext(0, cleartext);

        vm.warp(block.timestamp + orb.cooldown() + 1);
        cleartext = "this is a cleartext";
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        orb.recordInvocationCleartext(1, cleartext);
    }

    function test_revertWhen_cleartextMismatch() public {
        makeHolderAndWarp(user, 1 ether);
        vm.startPrank(user);
        string memory cleartext = "this is a cleartext";
        string memory cleartext2 = "this is not the same cleartext";
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.expectRevert(
            abi.encodeWithSelector(
                Orb.CleartextHashMismatch.selector, keccak256(bytes(cleartext2)), keccak256(bytes(cleartext))
            )
        );
        orb.recordInvocationCleartext(0, cleartext2);

        orb.recordInvocationCleartext(0, cleartext);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        vm.startPrank(user);
        vm.expectEmit(true, false, false, true);
        emit CleartextRecording(0, cleartext);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        orb.recordInvocationCleartext(0, cleartext);
    }
}

contract RespondTest is OrbTestBase {
    event Response(address indexed responder, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);

    function test_revertWhen_notOwner() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        orb.recordInvocationCleartext(0, cleartext);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.respond(0, response);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Response(owner, 0, response, block.timestamp);
        orb.respond(0, response);
    }

    function test_revertWhen_invocationIdIncorrect() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        orb.recordInvocationCleartext(0, cleartext);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Orb.InvocationNotFound.selector, 1));
        orb.respond(1, response);

        vm.prank(owner);
        orb.respond(0, response);
    }

    function test_revertWhen_responseAlreadyExists() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        orb.recordInvocationCleartext(0, cleartext);
        vm.stopPrank();

        vm.startPrank(owner);
        orb.respond(0, response);
        vm.expectRevert(abi.encodeWithSelector(Orb.ResponseExists.selector, 0));
        orb.respond(0, response);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        orb.recordInvocationCleartext(0, cleartext);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Response(owner, 0, response, block.timestamp);
        orb.respond(0, response);
        (bytes32 hash, uint256 time) = orb.responses(0);
        assertEq(hash, response);
        assertEq(time, block.timestamp);
    }
}

contract FlagResponseTest is OrbTestBase {
    event ResponseFlagging(address indexed flagger, uint256 indexed invocationId);

    function test_revertWhen_NotHolder() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);
        vm.prank(user2);
        vm.expectRevert(Orb.NotHolder.selector);
        orb.flagResponse(0);

        vm.prank(user);
        orb.flagResponse(0);
    }

    function test_revertWhen_HolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(Orb.HolderInsolvent.selector);
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
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Orb.ResponseNotFound.selector, 188));
        orb.flagResponse(188);

        orb.flagResponse(0);
    }

    function test_revertWhen_outsideFlaggingPeriod() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);

        vm.warp(block.timestamp + 100 days);
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(Orb.FlaggingPeriodExpired.selector, 0, 100 days, orb.responseFlaggingPeriod())
        );
        orb.flagResponse(0);

        vm.warp(block.timestamp - (100 days - orb.responseFlaggingPeriod()));
        orb.flagResponse(0);
    }

    function test_revertWhen_responseToPreviousHolder() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);

        vm.startPrank(user2);
        orb.purchase{value: 3 ether}(1 ether, 2 ether);
        vm.expectRevert(
            abi.encodeWithSelector(Orb.FlaggingPeriodExpired.selector, 0, orb.holderReceiveTime(), block.timestamp)
        );
        orb.flagResponse(0);

        vm.warp(block.timestamp + orb.cooldown());
        orb.invokeWithHash(keccak256(bytes(cleartext)));
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
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(0, response);
        vm.prank(user);
        assertEq(orb.responseFlagged(0), false);
        assertEq(orb.flaggedResponsesCount(), 0);
        vm.expectEmit(true, false, false, true);
        emit ResponseFlagging(user, 0);
        vm.prank(user);
        orb.flagResponse(0);
        assertEq(orb.responseFlagged(0), true);
        assertEq(orb.flaggedResponsesCount(), 1);
    }
}
