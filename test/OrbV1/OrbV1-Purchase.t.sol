// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {OrbTestBase} from "./OrbV1.t.sol";
import {Orb} from "../../src/Orb.sol";

/* solhint-disable func-name-mixedcase */
contract SetPriceTest is OrbTestBase {
    function test_setPriceRevertsIfNotKeeper() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.expectRevert(Orb.NotKeeper.selector);
        vm.prank(user2);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 10 ether);

        vm.prank(user);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 1 ether);
    }

    function test_setPriceRevertsIfKeeperInsolvent() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 600 days);
        vm.startPrank(user);
        vm.expectRevert(Orb.KeeperInsolvent.selector);
        orb.setPrice(1 ether);

        // As the user can't deposit funds to become solvent again
        // we modify a variable to trick the contract
        orb.workaround_setLastSettlementTime(block.timestamp);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
    }

    function test_setPriceSettlesBefore() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.prank(user);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);

    function test_setPriceRevertsIfMaxPrice() public {
        uint256 maxPrice = orb.workaround_maximumPrice();
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Orb.InvalidNewPrice.selector, maxPrice + 1));
        orb.setPrice(maxPrice + 1);

        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(10 ether, maxPrice);
        orb.setPrice(maxPrice);
    }
}

contract PurchaseTest is OrbTestBase {
    function test_revertsIfHeldByContract() public {
        vm.prank(user);
        vm.expectRevert(Orb.ContractHoldsOrb.selector);
        orb.purchase(100, 0, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfKeeperInsolvent() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user2);
        vm.expectRevert(Orb.KeeperInsolvent.selector);
        orb.purchase(100, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_purchaseSettlesFirst() public {
        makeKeeperAndWarp(user, 1 ether);
        // after making `user` the current keeper of the Orb, `makeKeeperAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user2);
        orb.purchase{value: 1.1 ether}(2 ether, 1 ether, 10_00, 10_00, 7 days, 280);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function test_revertsIfBeneficiary() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.deal(beneficiary, 1.1 ether);
        vm.prank(beneficiary);
        vm.expectRevert(abi.encodeWithSelector(Orb.NotPermitted.selector));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);

        // does not revert
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user2);
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function test_revertsIfWrongCurrentPrice() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Orb.CurrentValueIncorrect.selector, 2 ether, 1 ether));
        orb.purchase{value: 1.1 ether}(3 ether, 2 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfWrongCurrentValues() public {
        orb.listWithPrice(1 ether);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Orb.CurrentValueIncorrect.selector, 20_00, 10_00));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 20_00, 10_00, 7 days, 280);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Orb.CurrentValueIncorrect.selector, 30_00, 10_00));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 30_00, 7 days, 280);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Orb.CurrentValueIncorrect.selector, 8 days, 7 days));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 8 days, 280);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Orb.CurrentValueIncorrect.selector, 140, 280));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 140);

        vm.prank(user);
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfIfAlreadyKeeper() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.expectRevert(Orb.AlreadyKeeper.selector);
        vm.prank(user);
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfInsufficientFunds() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(Orb.InsufficientFunds.selector, 1 ether - 1, 1 ether));
        vm.prank(user2);
        orb.purchase{value: 1 ether - 1}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfPurchasingAfterSetPrice() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.setPrice(0);
        vm.expectRevert(abi.encodeWithSelector(Orb.PurchasingNotPermitted.selector));
        vm.prank(user2);
        orb.purchase(1 ether, 0, 10_00, 10_00, 7 days, 280);
    }

    event Purchase(address indexed seller, address indexed buyer, uint256 indexed price);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);
    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);

    function test_beneficiaryAllProceedsIfOwnerSells() public {
        uint256 bidAmount = 1 ether;
        uint256 newPrice = 3 ether;
        uint256 purchaseAmount = bidAmount / 2;
        uint256 depositAmount = bidAmount / 2;
        // bidAmount will be the `_price` of the Orb
        makeKeeperAndWarp(owner, bidAmount);
        orb.settle();
        vm.warp(block.timestamp + 1 days);
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        vm.startPrank(user);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), userBefore + depositAmount);
        vm.expectEmit(true, true, true, true);
        emit Purchase(owner, user, bidAmount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(owner, user, 1);
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        orb.purchase{value: purchaseAmount + 1}(newPrice, bidAmount, 10_00, 10_00, 7 days, 280);
        uint256 beneficiaryRoyalty = bidAmount;
        assertEq(orb.fundsOf(beneficiary), beneficiaryBefore + beneficiaryRoyalty);
        assertEq(orb.fundsOf(owner), ownerBefore);
        // The price of the Orb was 1 ether and user2 transfered 1 ether + 1 to buy it
        assertEq(orb.fundsOf(user), 1);
        assertEq(orb.price(), newPrice);
        assertEq(orb.lastInvocationTime(), block.timestamp - orb.cooldown());
        assertEq(orb.keeperSolvent(), true);
    }

    function test_succeedsCorrectly() public {
        uint256 bidAmount = 1 ether;
        uint256 newPrice = 3 ether;
        uint256 expectedSettlement = bidAmount * orb.purchaseRoyaltyNumerator() / orb.feeDenominator();
        uint256 purchaseAmount = bidAmount / 2;
        uint256 depositAmount = bidAmount / 2;
        // bidAmount will be the `_price` of the Orb
        makeKeeperAndWarp(user, bidAmount);
        orb.settle();
        vm.prank(user);
        orb.deposit{value: expectedSettlement}();
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        uint256 lastInvocationTimeBefore = orb.lastInvocationTime();
        vm.warp(block.timestamp + 365 days);
        vm.prank(user2);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user2), depositAmount);
        vm.expectEmit(true, true, true, true);
        // 1 year has passed since the last settlement
        emit Settlement(user, beneficiary, expectedSettlement);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(bidAmount, newPrice);
        vm.expectEmit(true, true, true, true);
        emit Purchase(user, user2, bidAmount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(user, user2, 1);
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        vm.prank(user2);
        orb.purchase{value: purchaseAmount + 1}(newPrice, bidAmount, 10_00, 10_00, 7 days, 280);
        uint256 beneficiaryRoyalty = ((bidAmount * orb.purchaseRoyaltyNumerator()) / orb.feeDenominator());
        assertEq(orb.fundsOf(beneficiary), beneficiaryBefore + beneficiaryRoyalty + expectedSettlement);
        assertEq(orb.fundsOf(user), userBefore + (bidAmount - beneficiaryRoyalty - expectedSettlement));
        assertEq(orb.fundsOf(owner), ownerBefore);
        // The price of the Orb was 1 ether and user2 transfered 1 ether + 1 to buy it
        assertEq(orb.fundsOf(user2), 1);
        assertEq(orb.price(), newPrice);
        assertEq(orb.lastInvocationTime(), lastInvocationTimeBefore);
    }

    function testFuzz_succeedsCorrectly(uint256 bidAmount, uint256 newPrice, uint256 buyPrice, uint256 diff) public {
        bidAmount = bound(bidAmount, 0.1 ether, orb.workaround_maximumPrice() - 1);
        newPrice = bound(newPrice, 1, orb.workaround_maximumPrice());
        buyPrice = bound(buyPrice, bidAmount + 1, orb.workaround_maximumPrice());
        diff = bound(diff, 1, buyPrice);
        uint256 expectedSettlement = bidAmount * orb.purchaseRoyaltyNumerator() / orb.feeDenominator();
        vm.deal(user2, buyPrice);
        /// Break up the amount between depositing and purchasing to test more scenarios
        uint256 purchaseAmount = buyPrice - diff;
        uint256 depositAmount = diff;
        // bidAmount will be the `_price` of the Orb
        makeKeeperAndWarp(user, bidAmount);
        vm.deal(user, bidAmount + expectedSettlement);
        orb.settle();
        vm.startPrank(user);
        orb.deposit{value: expectedSettlement}();
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days);
        vm.prank(user2);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user2), depositAmount);
        vm.expectEmit(true, true, true, true);
        // 1 year has passed since the last settlement
        emit Settlement(user, beneficiary, expectedSettlement);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(bidAmount, newPrice);
        vm.expectEmit(true, true, true, true);
        emit Purchase(user, user2, bidAmount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(user, user2, 1);
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        // We bound the purchaseAmount to be higher than the current price (bidAmount)
        vm.prank(user2);
        orb.purchase{value: purchaseAmount}(newPrice, bidAmount, 10_00, 10_00, 7 days, 280);
        uint256 beneficiaryRoyalty = ((bidAmount * orb.purchaseRoyaltyNumerator()) / orb.feeDenominator());
        assertEq(orb.fundsOf(beneficiary), beneficiaryBefore + beneficiaryRoyalty + expectedSettlement);
        assertEq(orb.fundsOf(user), userBefore + (bidAmount - beneficiaryRoyalty - expectedSettlement));
        assertEq(orb.fundsOf(owner), ownerBefore);
        // User2 transfered buyPrice to the contract
        // User2 paid bidAmount
        assertEq(orb.fundsOf(user2), buyPrice - bidAmount);
        assertEq(orb.price(), newPrice);
    }
}
