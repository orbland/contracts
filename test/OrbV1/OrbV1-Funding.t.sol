// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase,one-contract-per-file
pragma solidity 0.8.20;

import {OrbTestBase} from "./OrbV1.t.sol";
import {Orb} from "../../src/legacy/Orb.sol";

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

        // One day has passed since the Orb keeper got the orb
        // for bid = 1 ether. That means that the price of the
        // Orb is now 1 ether. Thus the Orb beneficiary is owed the tax
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
        amount1 = bound(amount1, 1 ether, orb.workaround_maximumPrice());
        amount2 = bound(amount2, orb.auctionStartingPrice(), amount1 - orb.auctionMinimumBidStep());
        uint256 funds1 = fundsRequiredToBidOneYear(amount1);
        uint256 funds2 = fundsRequiredToBidOneYear(amount2);
        orb.startAuction();
        prankAndBid(user2, amount2);
        prankAndBid(user, amount1);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 1 days);

        // One day has passed since the Orb keeper got the Orb
        // for bid = 1 ether. That means that the price of the
        // Orb is now 1 ether. Thus the Orb beneficiary is owed the tax
        // for 1 day.

        // The user actually transfered `funds1` and `funds2` respectively
        // ether to the contract
        uint256 owed = orb.workaround_owedSinceLastSettlement();
        assertEq(effectiveFundsOf(beneficiary), owed + amount1);
        // The user that won the auction and is holding the Orb
        // has the funds they deposited, minus the tax and minus the bid
        // amount
        assertEq(effectiveFundsOf(user), funds1 - owed - amount1);
        // The user that didn't won the auction, has the funds they
        // deposited
        assertEq(effectiveFundsOf(user2), funds2);
    }
}

contract DepositTest is OrbTestBase {
    event Deposit(address indexed depositor, uint256 indexed amount);

    function test_depositRandomUser() public {
        assertEq(orb.fundsOf(user), 0);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, 1 ether);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user), 1 ether);
    }

    function testFuzz_depositRandomUser(uint256 amount) public {
        assertEq(orb.fundsOf(user), 0);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, amount);
        vm.deal(user, amount);
        vm.prank(user);
        orb.deposit{value: amount}();
        assertEq(orb.fundsOf(user), amount);
    }

    function test_depositKeeperSolvent() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        uint256 depositAmount = 2 ether;
        makeKeeperAndWarp(user, bidAmount);
        // User bids 1 ether, but deposit enough funds
        // to cover the tax for a year, according to
        // fundsRequiredToBidOneYear(bidAmount)
        uint256 funds = orb.fundsOf(user);
        vm.expectEmit(true, true, true, true);
        // deposit 1 ether
        emit Deposit(user, depositAmount);
        vm.prank(user);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), funds + depositAmount);
    }

    function testFuzz_depositKeeperSolvent(uint256 bidAmount, uint256 depositAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, 0.1 ether, orb.workaround_maximumPrice());
        depositAmount = bound(depositAmount, 0.1 ether, orb.workaround_maximumPrice());
        makeKeeperAndWarp(user, bidAmount);
        // User bids 1 ether, but deposit enough funds
        // to cover the tax for a year, according to
        // fundsRequiredToBidOneYear(bidAmount)
        uint256 funds = orb.fundsOf(user);
        vm.expectEmit(true, true, true, true);
        // deposit 1 ether
        emit Deposit(user, depositAmount);
        vm.prank(user);
        vm.deal(user, depositAmount);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), funds + depositAmount);
    }

    function test_depositRevertsifKeeperInsolvent() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        makeKeeperAndWarp(user, bidAmount);

        // let's make the user insolvent
        // fundsRequiredToBidOneYear(bidAmount) ensures enough
        // ether for 1 year, not two
        vm.warp(block.timestamp + 731 days);

        // if a random user deposits, it should work fine
        vm.prank(user2);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user2), 1 ether);

        // if the insolvent keeper deposits, it should not work
        vm.expectRevert(Orb.KeeperInsolvent.selector);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
    }
}

contract WithdrawTest is OrbTestBase {
    event Withdrawal(address indexed recipient, uint256 indexed amount);

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

    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);

    function test_withdrawSettlesFirstIfKeeper() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 10 ether;
        uint256 smallBidAmount = 0.5 ether;
        uint256 withdrawAmount = 0.1 ether;

        orb.startAuction();
        // user2 bids
        prankAndBid(user2, smallBidAmount);
        // user1 bids and becomes the leading bidder
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

        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);

        vm.prank(user);
        orb.withdraw(withdrawAmount);

        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + withdrawAmount);

        // move ahead 10 days;
        vm.warp(block.timestamp + 10 days);

        // not keeper
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
        // user1 bids and becomes the leading bidder
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
        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);

        vm.expectEmit(true, true, true, true);
        emit Withdrawal(beneficiary, beneficiaryFunds + transferableToBeneficiary);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(user), userEffective);
        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(beneficiary.balance, initialBalance + beneficiaryEffective);
    }

    function test_withdrawAllForBeneficiaryWhenContractOwned() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish(false);

        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 initialBalance = beneficiary.balance;
        uint256 settlementTime = block.timestamp;

        vm.warp(block.timestamp + 30 days);

        // expectNotEmit Settlement
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(beneficiary, beneficiaryFunds);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), settlementTime);
        assertEq(beneficiary.balance, initialBalance + beneficiaryFunds);
    }

    function test_withdrawAllForBeneficiaryWhenCreatorOwned() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish(false);
        vm.prank(owner);
        orb.listWithPrice(1 ether);

        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 initialBalance = beneficiary.balance;

        vm.warp(block.timestamp + 30 days);

        vm.expectEmit(true, true, true, true);
        emit Withdrawal(beneficiary, beneficiaryFunds);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(beneficiary.balance, initialBalance + beneficiaryFunds);
    }

    function testFuzz_withdrawSettlesFirstIfKeeper(uint256 bidAmount, uint256 withdrawAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, orb.auctionStartingPrice(), orb.workaround_maximumPrice());
        makeKeeperAndWarp(user, bidAmount);

        // beneficiaryEffective = beneficiaryFunds + transferableToBeneficiary
        // userEffective = userFunds - transferableToBeneficiary
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 transferableToBeneficiary = beneficiaryEffective - beneficiaryFunds;
        uint256 initialBalance = user.balance;

        vm.expectEmit(true, true, true, true);
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
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(user, 1 ether);
        orb.withdraw(1 ether);
        assertEq(orb.fundsOf(user), 0);
    }
}

contract SettleTest is OrbTestBase {
    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);

    function test_settleOnlyIfKeeperHeld() public {
        vm.expectRevert(Orb.ContractHoldsOrb.selector);
        orb.settle();
        assertEq(orb.lastSettlementTime(), 0);
        makeKeeperAndWarp(user, 1 ether);
        orb.settle();
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function testFuzz_settleCorrect(uint96 bid, uint96 time) public {
        uint256 amount = bound(bid, orb.auctionStartingPrice(), orb.workaround_maximumPrice());
        // warp ahead a random amount of time
        // remain under 1 year in total, so solvent
        uint256 timeOffset = bound(time, 0, 300 days);
        vm.warp(block.timestamp + timeOffset);
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), 0);
        // it warps 30 days by default
        makeKeeperAndWarp(user, amount);

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
        orb.listWithPrice(1 ether);
        vm.warp(30 days);
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        orb.workaround_settle();
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.fundsOf(beneficiary), beneficiaryFunds);
    }
}

contract KeeperSolventTest is OrbTestBase {
    function test_keeperSolventCorrectIfNotOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.lastSettlementTime(), 0);
        // it warps 30 days by default
        makeKeeperAndWarp(user, 1 ether);
        assert(orb.keeperSolvent());
        vm.warp(block.timestamp + 700 days);
        assertFalse(orb.keeperSolvent());
    }

    function test_keeperSolventCorrectIfOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.lastSettlementTime(), 0);
        assert(orb.keeperSolvent());
        vm.warp(block.timestamp + 4885828483 days);
        assert(orb.keeperSolvent());
    }
}

contract OwedSinceLastSettlementTest is OrbTestBase {
    function test_owedSinceLastSettlementCorrectMath() public {
        // _lastSettlementTime = 0
        // secondsSinceLastSettlement = block.timestamp - _lastSettlementTime
        // KEEPER_TAX_NUMERATOR = 1_000
        // feeDenominator = 10_000
        // keeperTaxPeriod  = 365 days = 31_536_000 seconds
        // owed = _price * KEEPER_TAX_NUMERATOR * secondsSinceLastSettlement)
        // / (keeperTaxPeriod * feeDenominator);
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
