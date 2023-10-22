// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {OrbTestBase} from "./OrbV1.t.sol";
import {Orb} from "../../src/Orb.sol";

/* solhint-disable func-name-mixedcase */
contract SwearOathTest is OrbTestBase {
    event OathSwearing(bytes32 indexed oathHash, uint256 indexed honoredUntil, uint256 indexed responsePeriod);

    function test_swearOathOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100, 3600);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100, 3600);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100, 3600);
    }

    function test_swearOathCorrectly() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        // keccak hash of "test oath"
        emit OathSwearing(0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc, 100, 3600);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100, 3600);
        assertEq(orb.honoredUntil(), 100);
        assertEq(orb.responsePeriod(), 3600);
    }
}

contract ExtendHonoredUntilTest is OrbTestBase {
    event HonoredUntilUpdate(uint256 previousHonoredUntil, uint256 indexed newHonoredUntil);

    function test_extendHonoredUntilOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.extendHonoredUntil(101);

        makeKeeperAndWarp(user, 1 ether);
        vm.prank(owner);
        orb.extendHonoredUntil(101);
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
        emit HonoredUntilUpdate(100, 101);
        orb.extendHonoredUntil(101);
    }
}

contract SettingTokenURITest is OrbTestBase {
    function test_tokenURIrevertsIfUser() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setTokenURI("https://static.orb.land/new/");
    }

    function test_tokenURISetsCorrectState() public {
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
}

contract SettingFeesTest is OrbTestBase {
    event FeesUpdate(
        uint256 previousKeeperTaxNumerator,
        uint256 indexed newKeeperTaxNumerator,
        uint256 previousRoyaltyNumerator,
        uint256 indexed newRoyaltyNumerator
    );

    function test_setFeesOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setFees(100_00, 100_00);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.setFees(100_00, 100_00);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.setFees(100_00, 100_00);
    }

    function test_revertIfRoyaltyNumeratorExceedsDenominator() public {
        uint256 largeNumerator = orb.feeDenominator() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                Orb.RoyaltyNumeratorExceedsDenominator.selector, largeNumerator, orb.feeDenominator()
            )
        );
        vm.prank(owner);
        orb.setFees(largeNumerator, largeNumerator);

        vm.prank(owner);
        orb.setFees(largeNumerator, orb.feeDenominator());

        assertEq(orb.keeperTaxNumerator(), largeNumerator);
        assertEq(orb.royaltyNumerator(), orb.feeDenominator());
    }

    function test_setFeesSucceedsCorrectly() public {
        assertEq(orb.keeperTaxNumerator(), 10_00);
        assertEq(orb.royaltyNumerator(), 10_00);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeesUpdate(10_00, 100_00, 10_00, 100_00);
        orb.setFees(100_00, 100_00);
        assertEq(orb.keeperTaxNumerator(), 100_00);
        assertEq(orb.royaltyNumerator(), 100_00);
    }
}

contract SettingCooldownTest is OrbTestBase {
    event CooldownUpdate(
        uint256 previousCooldown,
        uint256 indexed newCooldown,
        uint256 previousFlaggingPeriod,
        uint256 indexed newFlaggingPeriod
    );

    function test_setCooldownOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setCooldown(1 days, 2 days);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.setCooldown(1 days, 2 days);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.setCooldown(1 days, 2 days);
    }

    function test_revertsWhenCooldownTooLong() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Orb.CooldownExceedsMaximumDuration.selector, 3651 days, 3650 days));
        orb.setCooldown(3651 days, 2 days);
    }

    function test_setCooldownSucceedsCorrectly() public {
        assertEq(orb.cooldown(), 7 days);
        assertEq(orb.flaggingPeriod(), 7 days);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit CooldownUpdate(7 days, 1 days, 7 days, 2 days);
        orb.setCooldown(1 days, 2 days);
        assertEq(orb.cooldown(), 1 days);
        assertEq(orb.flaggingPeriod(), 2 days);
    }
}

contract SettingCleartextMaximumLengthTest is OrbTestBase {
    event CleartextMaximumLengthUpdate(
        uint256 previousCleartextMaximumLength, uint256 indexed newCleartextMaximumLength
    );

    function test_setCleartextMaximumLengthOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setCleartextMaximumLength(1);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(Orb.AuctionRunning.selector);
        orb.setCleartextMaximumLength(1);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(Orb.CreatorDoesNotControlOrb.selector);
        orb.setCleartextMaximumLength(1);
    }

    function test_revertIfCleartextMaximumLengthZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Orb.InvalidCleartextMaximumLength.selector, 0));
        orb.setCleartextMaximumLength(0);
    }

    function test_setCleartextMaximumLengthSucceedsCorrectly() public {
        assertEq(orb.cleartextMaximumLength(), 280);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit CleartextMaximumLengthUpdate(280, 1);
        orb.setCleartextMaximumLength(1);
        assertEq(orb.cleartextMaximumLength(), 1);
    }
}
