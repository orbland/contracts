// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {OrbPond} from "src/OrbPond.sol";
import {OrbHarness} from "./harness/OrbHarness.sol";
import {Orb} from "src/Orb.sol";
import {IOrb} from "src/IOrb.sol";

/* solhint-disable func-name-mixedcase */
contract OrbPondTestBase is Test {
    OrbPond internal orbPond;

    address internal owner;
    address internal user;
    address internal beneficiary;

    function setUp() public {
        orbPond = new OrbPond();

        user = address(0xBEEF);
        // vm.deal(user, 10000 ether);

        owner = orbPond.owner();
        beneficiary = address(0xC0FFEE);
    }

    function deployDefaults() public returns (Orb orb) {
        orbPond.createOrb(
            "TestOrb",
            "TEST",
            100,
            beneficiary,
            0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc,
            100,
            "test baseURI"
        );

        return orbPond.orbs(0);
    }
}

contract InitialStateTest is OrbPondTestBase {
    // Test that the initial state is correct
    function test_initialState() public {
        assertEq(orbPond.orbCount(), 0);
    }
}

contract DeployTest is OrbPondTestBase {
    function test_revertWhen_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orbPond.createOrb(
            "TestOrb",
            "TEST",
            100,
            beneficiary,
            0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc,
            100,
            "test baseURI"
        );
    }

    event Creation(bytes32 oathHash, uint256 honoredUntil);
    event OrbCreation(
        uint256 indexed orbId, address indexed orbAddress, bytes32 indexed oathHash, uint256 honoredUntil
    );

    function test_deploy() public {
        vm.expectEmit(true, true, true, true);
        // keccak hash of "test oath"
        emit Creation(0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc, 100);

        vm.expectEmit(true, true, true, true);
        emit OrbCreation(
            0,
            0x104fBc016F4bb334D775a19E8A6510109AC63E00,
            0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc,
            100
        );

        orbPond.createOrb(
            "TestOrb",
            "TEST",
            100,
            beneficiary,
            0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc,
            100,
            "test baseURI"
        );
    }
}

contract ConfigureTest is OrbPondTestBase {
    function test_revertWhen_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orbPond.configureOrb(
            0, // orbId
            0.1 ether, // auctionStartingPrice
            0.1 ether, // auctionMinimumBidStep
            1 days, // auctionMinimumDuration
            5 minutes, // auctionBidExtension
            20_00, // holderTaxNumerator
            20_00, // royaltyNumerator
            3 days, // cooldownDuration
            100 // cooldownMaximumDuration
        );
    }

    event AuctionParametersUpdate(
        uint256 previousStartingPrice,
        uint256 newStartingPrice,
        uint256 previousMinimumBidStep,
        uint256 newMinimumBidStep,
        uint256 previousMinimumDuration,
        uint256 newMinimumDuration,
        uint256 previousBidExtension,
        uint256 newBidExtension
    );
    event FeesUpdate(
        uint256 previousHolderTaxNumerator,
        uint256 newHolderTaxNumerator,
        uint256 previousRoyaltyNumerator,
        uint256 newRoyaltyNumerator
    );
    event CooldownUpdate(uint256 previousCooldown, uint256 newCooldown);
    event CleartextMaximumLengthUpdate(uint256 previousCleartextMaximumLength, uint256 newCleartextMaximumLength);

    function test_success() public {
        Orb orb = deployDefaults();

        assertEq(orb.auctionStartingPrice(), 0);
        assertEq(orb.auctionMinimumBidStep(), 1);
        assertEq(orb.auctionMinimumDuration(), 1 days);
        assertEq(orb.auctionBidExtension(), 5 minutes);

        assertEq(orb.holderTaxNumerator(), 10_00);
        assertEq(orb.royaltyNumerator(), 10_00);

        assertEq(orb.cooldown(), 7 days);

        assertEq(orb.cleartextMaximumLength(), 280);

        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdate(
            0, // previousStartingPrice
            0.2 ether, // newStartingPrice
            1, // previousMinimumBidStep
            0.2 ether, // newMinimumBidStep
            1 days, // previousMinimumDuration
            2 days, // newMinimumDuration
            5 minutes, // previousBidExtension
            10 minutes // newBidExtension
        );

        vm.expectEmit(true, true, true, true);
        emit FeesUpdate(
            10_00, // previousHolderTaxNumerator
            20_00, // newHolderTaxNumerator
            10_00, // previousRoyaltyNumerator
            20_00 // newRoyaltyNumerator
        );

        vm.expectEmit(true, true, true, true);
        emit CooldownUpdate(7 days, 3 days);

        vm.expectEmit(true, true, true, true);
        emit CleartextMaximumLengthUpdate(280, 100);

        vm.prank(owner);
        orbPond.configureOrb(
            0, // orbId
            0.2 ether, // auctionStartingPrice
            0.2 ether, // auctionMinimumBidStep
            2 days, // auctionMinimumDuration
            10 minutes, // auctionBidExtension
            20_00, // holderTaxNumerator
            20_00, // royaltyNumerator
            3 days, // cooldown
            100 // cleartextMaximumLength
        );

        assertEq(orb.auctionStartingPrice(), 0.2 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.2 ether);
        assertEq(orb.auctionMinimumDuration(), 2 days);
        assertEq(orb.auctionBidExtension(), 10 minutes);

        assertEq(orb.holderTaxNumerator(), 20_00);
        assertEq(orb.royaltyNumerator(), 20_00);

        assertEq(orb.cooldown(), 3 days);

        assertEq(orb.cleartextMaximumLength(), 100);
    }
}

contract TransferOrbOwnershipTest is OrbPondTestBase {
    function test_revertWhen_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orbPond.transferOrbOwnership(0, user);
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function test_success() public {
        Orb orb = deployDefaults();
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit OwnershipTransferred(address(orbPond), user);
        orbPond.transferOrbOwnership(0, user);
        assertEq(orb.owner(), user);
    }
}
