// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";

import {OrbTestBase} from "./Orb.t.sol";
import {IOrb} from "../src/IOrb.sol";

/* solhint-disable func-name-mixedcase,private-vars-leading-underscore */
contract MinimumBidTest is OrbTestBase {
    function test_minimumBidReturnsCorrectValues() public {
        uint256 bidAmount = 0.6 ether;
        orb.startAuction();
        assertEq(orb.workaround_minimumBid(), orb.auctionStartingPrice());
        prankAndBid(user, bidAmount);
        assertEq(orb.workaround_minimumBid(), bidAmount + orb.auctionMinimumBidStep());
    }
}

contract StartAuctionTest is OrbTestBase {
    function test_startAuctionOnlyOrbCreator() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("Ownable: caller is not the owner");
        orb.startAuction();
        orb.startAuction();
    }

    event AuctionStart(
        uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
    );

    function test_startAuctionCorrectly() public {
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration(), beneficiary);
        orb.startAuction();
        assertEq(orb.auctionEndTime(), block.timestamp + orb.auctionMinimumDuration());
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
    }

    function test_startAuctionOnlyContractHeld() public {
        orb.workaround_setOrbKeeper(address(0xBEEF));
        vm.expectRevert(IOrb.ContractDoesNotHoldOrb.selector);
        orb.startAuction();
        orb.workaround_setOrbKeeper(address(orb));
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration(), beneficiary);
        orb.startAuction();
    }

    function test_startAuctionNotDuringAuction() public {
        assertEq(orb.auctionEndTime(), 0);
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration(), beneficiary);
        orb.startAuction();
        assertGt(orb.auctionEndTime(), 0);
        vm.warp(orb.auctionEndTime());

        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.startAuction();
    }
}

contract BidTest is OrbTestBase {
    function test_bidOnlyDuringAuction() public {
        uint256 bidAmount = 0.6 ether;
        vm.deal(user, bidAmount);
        vm.expectRevert(IOrb.AuctionNotRunning.selector);
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
        uint256 amount = orb.workaround_minimumBid();
        vm.deal(beneficiary, amount);
        vm.expectRevert(abi.encodeWithSelector(IOrb.NotPermitted.selector));
        vm.prank(beneficiary);
        orb.bid{value: amount}(amount, amount);

        // will not revert
        prankAndBid(user, amount);
        assertEq(orb.leadingBid(), amount);
    }

    function test_bidRevertsIfLtMinimumBid() public {
        orb.startAuction();
        // minimum bid will be the STARTING_PRICE
        uint256 amount = orb.workaround_minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientBid.selector, amount, orb.workaround_minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);

        // Add back + 1 to amount
        amount++;
        // will not revert
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);
        assertEq(orb.leadingBid(), amount);

        // minimum bid will be the leading bid + MINIMUM_BID_STEP
        amount = orb.workaround_minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientBid.selector, amount, orb.workaround_minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);
    }

    function test_bidRevertsIfLtFundsRequired() public {
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
        uint256 funds = amount - 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientFunds.selector, funds, funds + 1));
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
        uint256 amount = orb.workaround_minimumBid();
        uint256 price = orb.workaround_maximumPrice() + 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InvalidNewPrice.selector, price));
        vm.prank(user);
        orb.bid{value: amount}(amount, price);

        // Bring price back to acceptable amount
        price--;
        // will not revert
        vm.prank(user);
        orb.bid{value: amount}(amount, price);
        assertEq(orb.leadingBid(), amount);
        assertEq(orb.price(), orb.workaround_maximumPrice());
    }

    event AuctionBid(address indexed bidder, uint256 indexed bid);

    function test_bidSetsCorrectState() public {
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
        uint256 funds = fundsRequiredToBidOneYear(amount);
        assertEq(orb.leadingBid(), 0 ether);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.fundsOf(user), 0);
        assertEq(address(orb).balance, 0);
        uint256 auctionEndTime = orb.auctionEndTime();

        vm.expectEmit(true, true, true, true);
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

    event AuctionFinalization(address indexed winner, uint256 indexed winningBid);

    function testFuzz_bidSetsCorrectState(address[16] memory bidders, uint128[16] memory amounts) public {
        orb.startAuction();
        uint256 contractBalance;
        for (uint256 i = 1; i < 16; i++) {
            uint256 upperBound = orb.workaround_minimumBid() + 1_000_000_000;
            uint256 amount = bound(amounts[i], orb.workaround_minimumBid(), upperBound);
            address bidder = bidders[i];
            vm.assume(bidder != address(0) && bidder != address(orb) && bidder != beneficiary);

            uint256 funds = fundsRequiredToBidOneYear(amount);

            fundsOfUser[bidder] += funds;

            vm.expectEmit(true, true, true, true);
            emit AuctionBid(bidder, amount);
            prankAndBid(bidder, amount);
            contractBalance += funds;

            assertEq(orb.leadingBid(), amount);
            assertEq(orb.leadingBidder(), bidder);
            assertEq(orb.price(), amount);
            assertEq(orb.fundsOf(bidder), fundsOfUser[bidder]);
            assertEq(address(orb).balance, contractBalance);
        }
        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(orb.leadingBidder(), orb.leadingBid());
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
    }

    event AuctionExtension(uint256 indexed newAuctionEndTime);

    function test_bidExtendsAuction() public {
        assertEq(orb.auctionEndTime(), 0);
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
        // auctionEndTime = block.timestamp + auctionMinimumDuration
        uint256 auctionEndTime = orb.auctionEndTime();
        // set block.timestamp to auctionEndTime - auctionBidExtension
        vm.warp(auctionEndTime - orb.auctionBidExtension());
        prankAndBid(user, amount);
        // didn't change because block.timestamp + auctionBidExtension = auctionEndTime
        assertEq(orb.auctionEndTime(), auctionEndTime);

        vm.warp(auctionEndTime - orb.auctionBidExtension() + 50);
        amount = orb.workaround_minimumBid();
        vm.expectEmit(true, true, true, true);
        emit AuctionExtension(auctionEndTime + 50);
        prankAndBid(user, amount);
        // change because block.timestamp + auctionBidExtension + 50 >  auctionEndTime
        assertEq(orb.auctionEndTime(), auctionEndTime + 50);
    }
}

contract FinalizeAuctionTest is OrbTestBase {
    event AuctionFinalization(address indexed winner, uint256 indexed winningBid);

    function test_finalizeAuctionRevertsDuringAuction() public {
        orb.startAuction();
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.finalizeAuction();

        vm.warp(orb.auctionEndTime() + 1);
        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(address(0), 0);
        orb.finalizeAuction();
    }

    function test_finalizeAuctionRevertsIfAuctionNotStarted() public {
        vm.expectRevert(IOrb.AuctionNotStarted.selector);
        orb.finalizeAuction();
        orb.startAuction();
        // auctionEndTime != 0
        assertEq(orb.auctionEndTime(), block.timestamp + orb.auctionMinimumDuration());
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.finalizeAuction();
    }

    function test_finalizeAuctionWithoutWinner() public {
        orb.startAuction();
        vm.warp(orb.auctionEndTime() + 1);
        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(address(0), 0);
        orb.finalizeAuction();
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), 0);
    }

    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);

    function test_finalizeAuctionWithWinner() public {
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
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

        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(user, amount);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(0, amount);

        orb.finalizeAuction();

        // Assert storage after
        // storage that is reset
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), amount);

        // storage that persists
        assertEq(address(orb).balance, funds);
        assertEq(orb.fundsOf(beneficiary), amount);
        assertEq(orb.keeper(), user);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.lastInvocationTime(), block.timestamp - orb.cooldown());
        assertEq(orb.fundsOf(user), funds - amount);
        assertEq(orb.price(), amount);
    }

    function test_finalizeAuctionWithBeneficiary() public {
        makeKeeperAndWarp(user, 1 ether);
        assertEq(orb.auctionBeneficiary(), beneficiary);
        vm.prank(user);
        orb.relinquish(true);
        uint256 contractBalance = address(orb).balance;
        assertEq(orb.auctionBeneficiary(), user);

        uint256 amount = orb.workaround_minimumBid();
        uint256 funds = fundsRequiredToBidOneYear(amount);
        // Bid `amount` and transfer `funds` to the contract
        prankAndBid(user2, amount);
        vm.warp(orb.auctionEndTime() + 1);

        // Assert storage before
        assertEq(orb.leadingBidder(), user2);
        assertEq(orb.leadingBid(), amount);
        assertEq(orb.price(), amount);
        assertEq(orb.fundsOf(user2), funds);
        assertEq(orb.fundsOf(address(orb)), 0);

        uint256 beneficiaryRoyalty = (amount * orb.royaltyNumerator()) / orb.feeDenominator();
        uint256 auctionBeneficiaryShare = amount - beneficiaryRoyalty;
        uint256 userFunds = orb.fundsOf(user);
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 lastInvocationTime = orb.lastInvocationTime();

        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(user2, amount);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(0, amount);

        orb.finalizeAuction();

        // Assert storage after
        // storage that is reset
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), amount);

        // storage that persists
        assertEq(address(orb).balance, contractBalance + funds);
        assertEq(orb.fundsOf(beneficiary), beneficiaryFunds + beneficiaryRoyalty);
        assertEq(orb.keeper(), user2);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.lastInvocationTime(), lastInvocationTime); // unchanged because it's Keeper's auction
        assertEq(orb.fundsOf(user2), funds - amount);
        assertEq(orb.fundsOf(user), userFunds + auctionBeneficiaryShare);
    }

    function test_finalizeAuctionWithBeneficiaryLowRoyalties() public {
        orb.setFees(100_00, 0);
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish(true);
        uint256 amount = orb.workaround_minimumBid();
        // Bid `amount` and transfer `funds` to the contract
        prankAndBid(user2, amount);
        vm.warp(orb.auctionEndTime() + 1);
        uint256 minBeneficiaryNumerator =
            orb.keeperTaxNumerator() * orb.auctionKeeperMinimumDuration() / orb.keeperTaxPeriod();
        assertTrue(minBeneficiaryNumerator > orb.royaltyNumerator());
        uint256 minBeneficiaryRoyalty = (amount * minBeneficiaryNumerator) / orb.feeDenominator();
        uint256 auctionBeneficiaryShare = amount - minBeneficiaryRoyalty;
        uint256 userFunds = orb.fundsOf(user);
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        orb.finalizeAuction();
        assertEq(orb.fundsOf(beneficiary), beneficiaryFunds + minBeneficiaryRoyalty);
        assertEq(orb.fundsOf(user), userFunds + auctionBeneficiaryShare);
    }

    function test_finalizeAuctionWithBeneficiaryWithoutWinner() public {
        makeKeeperAndWarp(user, 1 ether);
        assertEq(orb.auctionBeneficiary(), beneficiary);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.auctionBeneficiary(), user);
        vm.warp(orb.auctionEndTime() + 1);

        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(address(0), 0);
        orb.finalizeAuction();

        // Assert storage after
        assertEq(orb.auctionBeneficiary(), user);
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), 0);

        orb.startAuction();
        assertEq(orb.auctionBeneficiary(), beneficiary);
    }
}

contract ListingTest is OrbTestBase {
    function test_revertsIfHeldByUser() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.expectRevert(IOrb.ContractDoesNotHoldOrb.selector);
        orb.listWithPrice(1 ether);
    }

    function test_revertsIfAlreadyHeldByCreator() public {
        makeKeeperAndWarp(owner, 1 ether);
        vm.expectRevert(IOrb.ContractDoesNotHoldOrb.selector);
        orb.listWithPrice(1 ether);
    }

    function test_revertsIfAuctionStarted() public {
        orb.startAuction();
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.listWithPrice(1 ether);

        vm.warp(orb.auctionEndTime() + 1);
        assertFalse(orb.workaround_auctionRunning());
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.listWithPrice(1 ether);
    }

    function test_revertsIfCalledByUser() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        orb.listWithPrice(1 ether);
    }

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);

    function test_succeedsCorrectly() public {
        uint256 listingPrice = 1 ether;
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(orb), owner, 1);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(0, listingPrice);
        orb.listWithPrice(listingPrice);
        assertEq(orb.price(), listingPrice);
        assertEq(orb.keeper(), owner);
    }
}
