// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase,private-vars-leading-underscore,one-contract-per-file
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {OrbHarness} from "./OrbV2Harness.sol";
import {OrbTestBase} from "./OrbV2.t.sol";
import {Orb} from "../../src/legacy/Orb.sol";
import {OrbTestUpgrade} from "../../src/legacy/test-upgrades/OrbTestUpgrade.sol";

contract RequestUpgradeTest is OrbTestBase {
    event UpgradeRequest(address indexed requestedImplementation);

    function test_revertWhenNotNextVersion() public {
        assertEq(orb.requestedUpgradeImplementation(), address(0));
        vm.expectRevert(Orb.NotNextVersion.selector);
        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));
        assertEq(orb.requestedUpgradeImplementation(), address(0));

        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );

        vm.expectRevert(Orb.NotNextVersion.selector);
        vm.prank(owner);
        orb.requestUpgrade(address(0xCAFEBABE));
        assertEq(orb.requestedUpgradeImplementation(), address(0));

        vm.expectEmit(true, true, true, true);
        emit UpgradeRequest(address(orbTestUpgradeImplementation));
        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));
        assertEq(orb.requestedUpgradeImplementation(), address(orbTestUpgradeImplementation));
    }

    function test_ownerCanCancel() public {
        assertEq(orb.requestedUpgradeImplementation(), address(0));
        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );
        vm.expectEmit(true, true, true, true);
        emit UpgradeRequest(address(orbTestUpgradeImplementation));
        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));
        assertEq(orb.requestedUpgradeImplementation(), address(orbTestUpgradeImplementation));

        vm.expectEmit(true, true, true, true);
        emit UpgradeRequest(address(0));
        vm.prank(owner);
        orb.requestUpgrade(address(0));
        assertEq(orb.requestedUpgradeImplementation(), address(0));
    }

    function test_revertWhenNotOwner() public {
        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );

        assertEq(orb.requestedUpgradeImplementation(), address(0));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        vm.prank(user);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));
        assertEq(orb.requestedUpgradeImplementation(), address(0));

        vm.expectEmit(true, true, true, true);
        emit UpgradeRequest(address(orbTestUpgradeImplementation));
        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));
        assertEq(orb.requestedUpgradeImplementation(), address(orbTestUpgradeImplementation));
    }
}

contract CompleteUpgradeTest is OrbTestBase {
    event Upgraded(address indexed implementation);

    function test_revertWhenNotRequested() public {
        makeKeeperAndWarp(user, 1 ether);
        assertEq(orb.requestedUpgradeImplementation(), address(0));
        vm.prank(user);
        vm.expectRevert(Orb.NoUpgradeRequested.selector);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Orb");
    }

    function test_revertWhenNotKeeper() public {
        makeKeeperAndWarp(user, 1 ether);
        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));

        assertEq(orb.requestedUpgradeImplementation(), address(orbTestUpgradeImplementation));
        vm.expectRevert(Orb.NotPermitted.selector);
        vm.prank(user2);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Orb");

        vm.prank(user);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Whorb");
    }

    function test_revertWhenNotKeeperSolvent() public {
        makeKeeperAndWarp(user, 1 ether);
        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));
        assertEq(orb.requestedUpgradeImplementation(), address(orbTestUpgradeImplementation));

        vm.warp(block.timestamp + 10000 days);
        vm.expectRevert(Orb.NotPermitted.selector);
        vm.prank(user);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Orb");

        vm.warp(block.timestamp - 10000 days);
        vm.prank(user);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Whorb");
    }

    function test_revertWhenNotOwner() public {
        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));
        assertEq(orb.keeper(), address(orb));

        vm.expectRevert(Orb.NotPermitted.selector);
        vm.prank(user);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Orb");

        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Whorb");
    }

    function test_revertWhenAuctionRunning() public {
        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));

        vm.expectRevert(Orb.NotPermitted.selector);
        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Orb");

        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();

        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Whorb");
    }

    function test_revertWhenImplementationChanged() public {
        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));

        OrbTestUpgrade orbTestUpgradeAnotherImplementation = new OrbTestUpgrade();
        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeAnotherImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );

        vm.expectRevert(Orb.NotNextVersion.selector);
        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Orb");

        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbTestUpgrade(address(orb)).name(), "Whorb");
    }

    function test_upgradeSucceeds() public {
        orbPond.registerVersion(
            orb.version() + 1,
            address(orbTestUpgradeImplementation),
            abi.encodeWithSelector(OrbTestUpgrade.initializeTestUpgrade.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbTestUpgradeImplementation));
        assertEq(OrbTestUpgrade(address(orb)).name(), "Orb");
        assertEq(OrbTestUpgrade(address(orb)).symbol(), "ORB");
        // Note: needs to be updated with every new base version
        assertEq(OrbTestUpgrade(address(orb)).version(), 2);
        assertEq(orb.requestedUpgradeImplementation(), address(orbTestUpgradeImplementation));

        bytes4 numberSelector = bytes4(keccak256("number()"));

        // solhint-disable-next-line avoid-low-level-calls
        (bool successBefore,) = address(orb).call(abi.encodeWithSelector(numberSelector));
        assertEq(successBefore, false);

        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(orbTestUpgradeImplementation));
        vm.prank(owner);
        orb.upgradeToNextVersion();

        // solhint-disable-next-line avoid-low-level-calls
        (bool successAfter,) = address(orb).call(abi.encodeWithSelector(numberSelector));
        assertEq(successAfter, true);
        assertEq(OrbTestUpgrade(address(orb)).number(), 69);
        assertEq(OrbTestUpgrade(address(orb)).name(), "Whorb");
        assertEq(OrbTestUpgrade(address(orb)).symbol(), "WHORB");
        assertEq(OrbTestUpgrade(address(orb)).version(), 100);

        assertEq(orb.requestedUpgradeImplementation(), address(0));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        OrbTestUpgrade(address(orb)).initializeTestUpgrade("Error", "ERROR");
    }
}

contract UpgradeFromV1Test is OrbTestBase {
    function test_upgradeSucceeds() public {
        orbPond.setOrbInitialVersion(1);

        address[] memory beneficiaryPayees = new address[](2);
        uint256[] memory beneficiaryShares = new uint256[](2);
        beneficiaryPayees[0] = address(0xC0FFEE);
        beneficiaryPayees[1] = address(0xFACEB00C);
        beneficiaryShares[0] = 95;
        beneficiaryShares[1] = 5;
        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "Orb", "ORB", "https://static.orb.land/orb/");

        assertEq(orbPond.orbCount(), 2);
        Orb testOrbV1 = Orb(orbPond.orbs(1));

        assertEq(testOrbV1.version(), 1);
        assertEq(testOrbV1.responsePeriod(), 0);
        assertEq(testOrbV1.royaltyNumerator(), 10_00);
        bytes4 auctionRoyaltyNumeratorSelector = bytes4(keccak256("auctionRoyaltyNumerator()"));
        // solhint-disable-next-line avoid-low-level-calls
        (bool successBefore,) = address(testOrbV1).call(abi.encodeWithSelector(auctionRoyaltyNumeratorSelector));
        assertEq(successBefore, false);

        testOrbV1.requestUpgrade(address(orbV2Implementation));
        testOrbV1.upgradeToNextVersion();

        OrbHarness testOrbV2 = OrbHarness(orbPond.orbs(1));

        assertEq(testOrbV2.version(), 2);
        assertEq(testOrbV2.responsePeriod(), 7 days);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successAfter,) = address(testOrbV2).call(abi.encodeWithSelector(auctionRoyaltyNumeratorSelector));
        assertEq(successAfter, true);
        assertEq(testOrbV2.auctionRoyaltyNumerator(), 10_00);
    }
}
