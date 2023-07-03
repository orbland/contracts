// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";

import {OrbTestBase} from "./Orb.t.sol";
import {IOrb} from "src/IOrb.sol";
import {OrbV2} from "src/OrbV2.sol";

contract RequestUpgradeTest is OrbTestBase {
    event UpgradeRequest(address indexed requestedImplementation);

    function test_revertWhenNotNextVersion() public {
        assertEq(orb.requestedUpgradeImplementation(), address(0));
        vm.expectRevert(IOrb.NotNextVersion.selector);
        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));
        assertEq(orb.requestedUpgradeImplementation(), address(0));

        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );

        vm.expectRevert(IOrb.NotNextVersion.selector);
        vm.prank(owner);
        orb.requestUpgrade(address(0xCAFEBABE));
        assertEq(orb.requestedUpgradeImplementation(), address(0));

        vm.expectEmit(true, true, true, true);
        emit UpgradeRequest(address(orbV2Implementation));
        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));
        assertEq(orb.requestedUpgradeImplementation(), address(orbV2Implementation));
    }

    function test_ownerCanCancel() public {
        assertEq(orb.requestedUpgradeImplementation(), address(0));
        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );
        vm.expectEmit(true, true, true, true);
        emit UpgradeRequest(address(orbV2Implementation));
        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));
        assertEq(orb.requestedUpgradeImplementation(), address(orbV2Implementation));

        vm.expectEmit(true, true, true, true);
        emit UpgradeRequest(address(0));
        vm.prank(owner);
        orb.requestUpgrade(address(0));
        assertEq(orb.requestedUpgradeImplementation(), address(0));
    }

    function test_revertWhenNotOwner() public {
        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );

        assertEq(orb.requestedUpgradeImplementation(), address(0));
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        orb.requestUpgrade(address(orbV2Implementation));
        assertEq(orb.requestedUpgradeImplementation(), address(0));

        vm.expectEmit(true, true, true, true);
        emit UpgradeRequest(address(orbV2Implementation));
        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));
        assertEq(orb.requestedUpgradeImplementation(), address(orbV2Implementation));
    }
}

contract CompleteUpgradeTest is OrbTestBase {
    event UpgradeCompletion(address indexed newImplementation);

    function test_revertWhenNotRequested() public {
        makeKeeperAndWarp(user, 1 ether);
        assertEq(orb.requestedUpgradeImplementation(), address(0));
        vm.prank(user);
        vm.expectRevert(IOrb.NoUpgradeRequested.selector);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Orb");
    }

    function test_revertWhenNotKeeper() public {
        makeKeeperAndWarp(user, 1 ether);
        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));

        assertEq(orb.requestedUpgradeImplementation(), address(orbV2Implementation));
        vm.expectRevert(IOrb.NotPermitted.selector);
        vm.prank(user2);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Orb");

        vm.prank(user);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Whorb");
    }

    function test_revertWhenNotKeeperSolvent() public {
        makeKeeperAndWarp(user, 1 ether);
        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));
        assertEq(orb.requestedUpgradeImplementation(), address(orbV2Implementation));

        vm.warp(block.timestamp + 10000 days);
        vm.expectRevert(IOrb.NotPermitted.selector);
        vm.prank(user);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Orb");

        vm.warp(block.timestamp - 10000 days);
        vm.prank(user);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Whorb");
    }

    function test_revertWhenNotOwner() public {
        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));
        assertEq(orb.keeper(), address(orb));

        vm.expectRevert(IOrb.NotPermitted.selector);
        vm.prank(user);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Orb");

        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Whorb");
    }

    function test_revertWhenAuctionRunning() public {
        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));

        vm.expectRevert(IOrb.NotPermitted.selector);
        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Orb");

        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();

        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Whorb");
    }

    function test_revertWhenImplementationChanged() public {
        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));

        OrbV2 orbV2AnotherImplementation = new OrbV2();
        orbPond.registerVersion(
            2,
            address(orbV2AnotherImplementation),
            abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );

        vm.expectRevert(IOrb.NotNextVersion.selector);
        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Orb");

        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.upgradeToNextVersion();
        assertEq(OrbV2(address(orb)).name(), "Whorb");
    }

    function test_upgradeSucceeds() public {
        orbPond.registerVersion(
            2, address(orbV2Implementation), abi.encodeWithSelector(OrbV2.initializeV2.selector, "Whorb", "WHORB")
        );
        vm.prank(owner);
        orb.requestUpgrade(address(orbV2Implementation));
        assertEq(OrbV2(address(orb)).name(), "Orb");
        assertEq(OrbV2(address(orb)).symbol(), "ORB");
        assertEq(OrbV2(address(orb)).version(), 1);
        assertEq(orb.requestedUpgradeImplementation(), address(orbV2Implementation));

        bytes4 numberSelector = bytes4(keccak256("number()"));

        // solhint-disable-next-line avoid-low-level-calls
        (bool successBefore,) = address(orb).call(abi.encodeWithSelector(numberSelector));
        assertEq(successBefore, false);

        vm.expectEmit(true, true, true, true);
        emit UpgradeCompletion(address(orbV2Implementation));
        vm.prank(owner);
        orb.upgradeToNextVersion();

        // solhint-disable-next-line avoid-low-level-calls
        (bool successAfter,) = address(orb).call(abi.encodeWithSelector(numberSelector));
        assertEq(successAfter, true);
        assertEq(OrbV2(address(orb)).number(), 69);
        assertEq(OrbV2(address(orb)).name(), "Whorb");
        assertEq(OrbV2(address(orb)).symbol(), "WHORB");
        assertEq(OrbV2(address(orb)).version(), 2);

        assertEq(orb.requestedUpgradeImplementation(), address(0));

        vm.expectRevert("Initializable: contract is already initialized");
        OrbV2(address(orb)).initializeV2("Error", "ERROR");
    }
}
