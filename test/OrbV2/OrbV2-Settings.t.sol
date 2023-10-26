// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {ClonesUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/ClonesUpgradeable.sol";

import {OrbTestBase} from "./OrbV2.t.sol";
import {Orb} from "../../src/Orb.sol";
import {OrbV2} from "../../src/OrbV2.sol";
import {PaymentSplitter} from "../../src/CustomPaymentSplitter.sol";

/* solhint-disable func-name-mixedcase */
contract SwearOathTest is OrbTestBase {
    event OathSwearing(bytes32 indexed oathHash, uint256 indexed honoredUntil);

    function test_swearOathOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 10_000_000);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 10_000_000);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 10_000_000);
    }

    function test_swearOathCorrectly() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        // keccak hash of "test oath"
        emit OathSwearing(0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc, 10_000_000);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 10_000_000);
        assertEq(orb.honoredUntil(), 10_000_000);
    }

    function test_swearOathWhileOwnerHeld() public {
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 10_000_000);
        orb.listWithPrice(1 ether);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit OathSwearing(0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc, 5_000_000);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 5_000_000);
        assertEq(orb.honoredUntil(), 5_000_000);
    }

    function test_reswearIfPreviousOathExpired() public {
        makeKeeperAndWarp(user, 1 ether);

        assertGt(orb.honoredUntil(), block.timestamp);
        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 30_000_000);

        vm.warp(orb.honoredUntil() + 1);
        assertLt(orb.honoredUntil(), block.timestamp);

        vm.prank(owner);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 30_000_000);
        assertGt(orb.honoredUntil(), block.timestamp);
    }

    function test_previousFunctionSignatureNotSupported() public {
        vm.prank(owner);
        vm.expectRevert(Orb.NotSupported.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 20_000_000, 3600);
    }
}

contract ExtendHonoredUntilTest is OrbTestBase {
    event HonoredUntilUpdate(uint256 previousHonoredUntil, uint256 indexed newHonoredUntil);

    function test_extendHonoredUntilOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.extendHonoredUntil(20_000_001);

        makeKeeperAndWarp(user, 1 ether);
        vm.prank(owner);
        orb.extendHonoredUntil(20_000_001);
    }

    function test_extendHonoredUntilNotDecrease() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(owner);
        vm.expectRevert(Orb.HonoredUntilNotDecreasable.selector);
        orb.extendHonoredUntil(99);
    }

    function test_extendHonoredUntilCorrectly() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit HonoredUntilUpdate(20_000_000, 20_000_001);
        orb.extendHonoredUntil(20_000_001);
    }
}

contract SettingTokenURITest is OrbTestBase {
    function test_tokenURIrevertsIfUser() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setTokenURI("https://static.orb.land/new/");
    }

    function test_tokenURISetsCorrectState() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(owner);
        orb.setTokenURI("https://static.orb.land/new/");
        assertEq(orb.workaround_tokenURI(), "https://static.orb.land/new/");
    }
}

contract SettingAuctionParametersTest is OrbTestBase {
    event AuctionParametersUpdate(
        uint256 previousStartingPrice,
        uint256 indexed newStartingPrice,
        uint256 previousMinimumBidStep,
        uint256 indexed newMinimumBidStep,
        uint256 previousMinimumDuration,
        uint256 indexed newMinimumDuration,
        uint256 previousKeeperMinimumDuration,
        uint256 newKeeperMinimumDuration,
        uint256 previousBidExtension,
        uint256 newBidExtension
    );

    function test_setAuctionParametersOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);
    }

    function test_revertIfAuctionDurationZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Orb.InvalidAuctionDuration.selector, 0));
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 0, 1 days, 10 minutes);
    }

    function test_allowKeeperAuctionDurationZero() public {
        vm.prank(owner);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 0, 10 minutes);
    }

    function test_boundMinBidStepToAbove0() public {
        assertEq(orb.auctionStartingPrice(), 0.1 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.1 ether);
        vm.prank(owner);
        orb.setAuctionParameters(0, 0, 1 days, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0);
        assertEq(orb.auctionMinimumBidStep(), 1);

        vm.prank(owner);
        orb.setAuctionParameters(0, 2, 1 days, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0);
        assertEq(orb.auctionMinimumBidStep(), 2);
    }

    function test_setAuctionParametersSucceedsCorrectly() public {
        assertEq(orb.auctionStartingPrice(), 0.1 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.1 ether);
        assertEq(orb.auctionMinimumDuration(), 1 days);
        assertEq(orb.auctionKeeperMinimumDuration(), 6 hours);
        assertEq(orb.auctionBidExtension(), 5 minutes);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdate(
            0.1 ether, 0.2 ether, 0.1 ether, 0.2 ether, 1 days, 2 days, 6 hours, 1 days, 5 minutes, 10 minutes
        );
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0.2 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.2 ether);
        assertEq(orb.auctionMinimumDuration(), 2 days);
        assertEq(orb.auctionKeeperMinimumDuration(), 1 days);
        assertEq(orb.auctionBidExtension(), 10 minutes);
    }

    function test_succeedsIfOathExpired() public {
        makeKeeperAndWarp(user, 1 ether);

        assertGt(orb.honoredUntil(), block.timestamp);
        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);

        assertTrue(orb.auctionStartingPrice() != 0.2 ether);
        assertTrue(orb.auctionMinimumBidStep() != 0.2 ether);
        assertTrue(orb.auctionMinimumDuration() != 2 days);
        assertTrue(orb.auctionKeeperMinimumDuration() != 1 days);
        assertTrue(orb.auctionBidExtension() != 10 minutes);

        vm.warp(orb.honoredUntil() + 1);
        assertLt(orb.honoredUntil(), block.timestamp);

        vm.prank(owner);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0.2 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.2 ether);
        assertEq(orb.auctionMinimumDuration(), 2 days);
        assertEq(orb.auctionKeeperMinimumDuration(), 1 days);
        assertEq(orb.auctionBidExtension(), 10 minutes);
    }

    function test_setAuctionParametersWhileOwnerHeld() public {
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 20_000_000);
        orb.listWithPrice(1 ether);

        assertTrue(orb.auctionStartingPrice() != 0.2 ether);
        assertTrue(orb.auctionMinimumBidStep() != 0.2 ether);
        assertTrue(orb.auctionMinimumDuration() != 2 days);
        assertTrue(orb.auctionKeeperMinimumDuration() != 1 days);
        assertTrue(orb.auctionBidExtension() != 10 minutes);
        assertGt(orb.honoredUntil(), block.timestamp);

        vm.prank(owner);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0.2 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.2 ether);
        assertEq(orb.auctionMinimumDuration(), 2 days);
        assertEq(orb.auctionKeeperMinimumDuration(), 1 days);
        assertEq(orb.auctionBidExtension(), 10 minutes);
    }
}

contract SettingFeesTest is OrbTestBase {
    event FeesUpdate(
        uint256 previousKeeperTaxNumerator,
        uint256 indexed newKeeperTaxNumerator,
        uint256 previousPurchaseRoyaltyNumerator,
        uint256 indexed newPurchaseRoyaltyNumerator,
        uint256 previousAuctionRoyaltyNumerator,
        uint256 indexed newAuctionRoyaltyNumerator
    );

    function test_setFeesOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setFees(100_00, 100_00, 100_00);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.setFees(100_00, 100_00, 100_00);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.setFees(100_00, 100_00, 100_00);
    }

    function test_revertIfRoyaltyNumeratorExceedsDenominator() public {
        uint256 largeNumerator = orb.feeDenominator() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Orb.RoyaltyNumeratorExceedsDenominator.selector, largeNumerator, orb.feeDenominator()
            )
        );
        vm.prank(owner);
        orb.setFees(largeNumerator, largeNumerator - 1, largeNumerator);
        vm.expectRevert(
            abi.encodeWithSelector(
                Orb.RoyaltyNumeratorExceedsDenominator.selector, largeNumerator, orb.feeDenominator()
            )
        );
        vm.prank(owner);
        orb.setFees(largeNumerator, largeNumerator, largeNumerator - 1);

        vm.prank(owner);
        orb.setFees(largeNumerator, orb.feeDenominator(), orb.feeDenominator());

        assertEq(orb.keeperTaxNumerator(), largeNumerator);
        assertEq(orb.purchaseRoyaltyNumerator(), orb.feeDenominator());
        assertEq(orb.auctionRoyaltyNumerator(), orb.feeDenominator());
    }

    function test_setFeesSucceedsCorrectly() public {
        assertEq(orb.keeperTaxNumerator(), 120_00);
        assertEq(orb.purchaseRoyaltyNumerator(), 10_00);
        assertEq(orb.auctionRoyaltyNumerator(), 30_00);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeesUpdate(120_00, 100_00, 10_00, 100_00, 30_00, 100_00);

        orb.setFees(100_00, 100_00, 100_00);
        assertEq(orb.keeperTaxNumerator(), 100_00);
        assertEq(orb.purchaseRoyaltyNumerator(), 100_00);
        assertEq(orb.auctionRoyaltyNumerator(), 100_00);
    }

    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);

    function test_succeedsIfOathExpired() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.deposit{value: 1000 ether}();
        uint256 expectedSettlementTime = block.timestamp - 30 days;
        assertGt(orb.workaround_owedSinceLastSettlement(), 0);
        assertEq(orb.lastSettlementTime(), expectedSettlementTime);

        assertGt(orb.honoredUntil(), block.timestamp);
        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.setFees(200_00, 90_00, 90_00);

        assertTrue(orb.keeperTaxNumerator() != 200_00);
        assertTrue(orb.purchaseRoyaltyNumerator() != 90_00);
        assertTrue(orb.auctionRoyaltyNumerator() != 90_00);

        vm.warp(orb.honoredUntil() + 1);
        assertLt(orb.honoredUntil(), block.timestamp);
        assertGt(orb.workaround_owedSinceLastSettlement(), 0);
        assertEq(orb.lastSettlementTime(), expectedSettlementTime);
        uint256 owed = orb.workaround_owedSinceLastSettlement();

        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, owed);
        vm.prank(owner);
        orb.setFees(200_00, 90_00, 90_00);
        assertEq(orb.keeperTaxNumerator(), 200_00);
        assertEq(orb.purchaseRoyaltyNumerator(), 90_00);
        assertEq(orb.auctionRoyaltyNumerator(), 90_00);
    }

    function test_setFeesWhileOwnerHeld() public {
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 20_000_000);
        orb.listWithPrice(1 ether);

        assertTrue(orb.keeperTaxNumerator() != 200_00);
        assertTrue(orb.purchaseRoyaltyNumerator() != 90_00);
        assertTrue(orb.auctionRoyaltyNumerator() != 90_00);
        assertGt(orb.honoredUntil(), block.timestamp);

        vm.prank(owner);
        orb.setFees(200_00, 90_00, 90_00);
        assertEq(orb.keeperTaxNumerator(), 200_00);
        assertEq(orb.purchaseRoyaltyNumerator(), 90_00);
        assertEq(orb.auctionRoyaltyNumerator(), 90_00);
    }

    function test_previousFunctionSignatureNotSupported() public {
        vm.prank(owner);
        vm.expectRevert(Orb.NotSupported.selector);
        orb.setFees(100_00, 10_00);
    }
}

contract SettingInvocationParametersTest is OrbTestBase {
    event InvocationParametersUpdate(
        uint256 previousCooldown,
        uint256 indexed newCooldown,
        uint256 previousResponsePeriod,
        uint256 indexed newResponsePeriod,
        uint256 previousFlaggingPeriod,
        uint256 indexed newFlaggingPeriod,
        uint256 previousCleartextMaximumLength,
        uint256 newCleartextMaximumLength
    );

    function test_setInvocationParametersOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setInvocationParameters(1 days, 2 days, 3 days, 420);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.setInvocationParameters(1 days, 2 days, 3 days, 420);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.setInvocationParameters(1 days, 2 days, 3 days, 420);
    }

    function test_revertsWhenCooldownTooLong() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Orb.CooldownExceedsMaximumDuration.selector, 3651 days, 3650 days));
        orb.setInvocationParameters(3651 days, 2 days, 3 days, 420);
    }

    function test_revertIfCleartextMaximumLengthZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Orb.InvalidCleartextMaximumLength.selector, 0));
        orb.setInvocationParameters(1 days, 2 days, 3 days, 0);
    }

    function test_setInvocationParametersSucceedsCorrectly() public {
        assertEq(orb.cooldown(), 7 days);
        assertEq(orb.responsePeriod(), 7 days);
        assertEq(orb.flaggingPeriod(), 7 days);
        assertEq(orb.cleartextMaximumLength(), 300);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit InvocationParametersUpdate(7 days, 1 days, 7 days, 2 days, 7 days, 3 days, 300, 420);
        orb.setInvocationParameters(1 days, 2 days, 3 days, 420);
        assertEq(orb.cooldown(), 1 days);
        assertEq(orb.responsePeriod(), 2 days);
        assertEq(orb.flaggingPeriod(), 3 days);
        assertEq(orb.cleartextMaximumLength(), 420);
    }

    function test_succeedsIfOathExpired() public {
        makeKeeperAndWarp(user, 1 ether);

        assertGt(orb.honoredUntil(), block.timestamp);
        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.setInvocationParameters(1 days, 2 days, 3 days, 420);

        assertTrue(orb.cooldown() != 1 days);
        assertTrue(orb.responsePeriod() != 2 days);
        assertTrue(orb.flaggingPeriod() != 3 days);
        assertTrue(orb.cleartextMaximumLength() != 420);

        vm.warp(orb.honoredUntil() + 1);
        assertLt(orb.honoredUntil(), block.timestamp);

        vm.prank(owner);
        orb.setInvocationParameters(1 days, 2 days, 3 days, 420);
        assertEq(orb.cooldown(), 1 days);
        assertEq(orb.responsePeriod(), 2 days);
        assertEq(orb.flaggingPeriod(), 3 days);
        assertEq(orb.cleartextMaximumLength(), 420);
    }

    function test_setInvocationParametersWhileOwnerHeld() public {
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 20_000_000);
        orb.listWithPrice(1 ether);

        assertTrue(orb.cooldown() != 1 days);
        assertTrue(orb.responsePeriod() != 2 days);
        assertTrue(orb.flaggingPeriod() != 3 days);
        assertTrue(orb.cleartextMaximumLength() != 420);
        assertGt(orb.honoredUntil(), block.timestamp);

        vm.prank(owner);
        orb.setInvocationParameters(1 days, 2 days, 3 days, 420);
        assertEq(orb.cooldown(), 1 days);
        assertEq(orb.responsePeriod(), 2 days);
        assertEq(orb.flaggingPeriod(), 3 days);
        assertEq(orb.cleartextMaximumLength(), 420);
    }

    function test_previousFunctionSignatureNotSupported() public {
        vm.expectRevert(Orb.NotSupported.selector);
        orb.setCleartextMaximumLength(256);

        vm.expectRevert(Orb.NotSupported.selector);
        orb.setCooldown(1 days, 2 days);
    }
}

contract SettingBeneficiaryWithdrawalAddressTest is OrbTestBase {
    event BeneficiaryWithdrawalAddressUpdate(
        address previousBeneficiaryWithdrawalAddress, address indexed newBeneficiaryWithdrawalAddress
    );

    function test_revertsWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setBeneficiaryWithdrawalAddress(address(0xBABEFACE));
    }

    function test_revertsWhenAddressNotPermitted() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(OrbV2.AddressNotPermitted.selector, address(address(0xBABEFACE))));
        orb.setBeneficiaryWithdrawalAddress(address(0xBABEFACE));
    }

    function test_zeroAddressAlwaysPermitted() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BeneficiaryWithdrawalAddressUpdate(address(0), address(0));
        orb.setBeneficiaryWithdrawalAddress(address(0));
        assertEq(orb.beneficiaryWithdrawalAddress(), address(0));
    }

    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);
    event Withdrawal(address indexed recipient, uint256 indexed amount);
    event WithdrawalAddressAuthorization(address indexed withdrawalAddress, bool indexed authorized);

    function test_succeedsCorrectly() public {
        assertEq(orb.beneficiaryWithdrawalAddress(), address(0));
        assertEq(orb.fundsOf(beneficiary), 0);

        makeKeeperAndWarp(user, 1 ether);
        // beneficiary now has funds from auction proceeeds, and from time since then
        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, orb.workaround_owedSinceLastSettlement());
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(beneficiary, orb.fundsOf(beneficiary) + orb.workaround_owedSinceLastSettlement());
        vm.prank(user);
        orb.withdrawAllForBeneficiary();

        // setting to not permitted reverts
        vm.expectRevert(abi.encodeWithSelector(OrbV2.AddressNotPermitted.selector, address(address(0xBABEFACE))));
        vm.prank(owner);
        orb.setBeneficiaryWithdrawalAddress(address(0xBABEFACE));

        // new PaymentSplitter
        address[] memory newSplitterPayees = new address[](2);
        uint256[] memory newSplitterShares = new uint256[](2);
        newSplitterPayees[0] = address(0xC0FFEE);
        newSplitterPayees[1] = address(0xFACEB00C);
        newSplitterShares[0] = 50;
        newSplitterShares[1] = 50;
        address newSplitter = ClonesUpgradeable.clone(address(paymentSplitterImplementation));
        PaymentSplitter(payable(newSplitter)).initialize(newSplitterPayees, newSplitterShares);

        assertEq(orbPond.beneficiaryWithdrawalAddressPermitted(newSplitter), false);
        vm.expectEmit(true, true, true, true);
        emit WithdrawalAddressAuthorization(newSplitter, true);
        orbPond.authorizeWithdrawalAddress(newSplitter, true);
        assertEq(orbPond.beneficiaryWithdrawalAddressPermitted(newSplitter), true);

        // now setting works
        assertEq(orb.beneficiaryWithdrawalAddress(), address(0));
        vm.expectEmit(true, true, true, true);
        emit BeneficiaryWithdrawalAddressUpdate(address(0), newSplitter);
        vm.prank(owner);
        orb.setBeneficiaryWithdrawalAddress(newSplitter);
        assertEq(orb.beneficiaryWithdrawalAddress(), newSplitter);

        // now withdrawal happens to new address
        vm.warp(block.timestamp + 30 days);
        uint256 expectedBeneficiaryFunds = orb.workaround_owedSinceLastSettlement();
        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, expectedBeneficiaryFunds);
        orb.settle();
        assertEq(orb.fundsOf(beneficiary), expectedBeneficiaryFunds);
        assertEq(orb.fundsOf(newSplitter), 0);

        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, 0);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(newSplitter, expectedBeneficiaryFunds);
        vm.prank(user);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.fundsOf(newSplitter), 0);

        // test balance of newSplitter
        assertEq(newSplitter.balance, expectedBeneficiaryFunds);
        assertEq(PaymentSplitter(payable(newSplitter)).releasable(address(0xC0FFEE)), expectedBeneficiaryFunds / 2);
        assertEq(PaymentSplitter(payable(newSplitter)).releasable(address(0xFACEB00C)), expectedBeneficiaryFunds / 2);
    }

    function test_settingToZeroAddressWithdrawsToBeneficiary() public {
        assertEq(orb.beneficiaryWithdrawalAddress(), address(0));
        assertEq(orb.fundsOf(beneficiary), 0);

        // new PaymentSplitter
        address[] memory newSplitterPayees = new address[](2);
        uint256[] memory newSplitterShares = new uint256[](2);
        newSplitterPayees[0] = address(0xC0FFEE);
        newSplitterPayees[1] = address(0xFACEB00C);
        newSplitterShares[0] = 50;
        newSplitterShares[1] = 50;
        address newSplitter = ClonesUpgradeable.clone(address(paymentSplitterImplementation));
        PaymentSplitter(payable(newSplitter)).initialize(newSplitterPayees, newSplitterShares);
        orbPond.authorizeWithdrawalAddress(newSplitter, true);
        vm.prank(owner);
        orb.setBeneficiaryWithdrawalAddress(newSplitter);
        assertEq(orb.beneficiaryWithdrawalAddress(), newSplitter);

        makeKeeperAndWarp(user, 1 ether);
        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, orb.workaround_owedSinceLastSettlement());
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(newSplitter, orb.fundsOf(beneficiary) + orb.workaround_owedSinceLastSettlement());
        vm.prank(user);
        orb.withdrawAllForBeneficiary();

        vm.expectEmit(true, true, true, true);
        emit BeneficiaryWithdrawalAddressUpdate(newSplitter, address(0));
        vm.prank(owner);
        orb.setBeneficiaryWithdrawalAddress(address(0));
        assertEq(orb.beneficiaryWithdrawalAddress(), address(0));
        uint256 originalSplitterBalanceBefore = beneficiary.balance;

        // now withdrawal happens to original beneficiary
        vm.warp(block.timestamp + 30 days);
        uint256 expectedBeneficiaryFunds = orb.workaround_owedSinceLastSettlement();
        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, expectedBeneficiaryFunds);
        orb.settle();
        assertEq(orb.fundsOf(beneficiary), expectedBeneficiaryFunds);

        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, 0);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(beneficiary, expectedBeneficiaryFunds);
        vm.prank(user);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.fundsOf(newSplitter), 0);
        assertEq(beneficiary.balance, originalSplitterBalanceBefore + expectedBeneficiaryFunds);
    }
}
