// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* solhint-disable no-console */
import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PaymentSplitter} from "../src/CustomPaymentSplitter.sol";
import {OrbPond} from "../src/OrbPond.sol";
import {OrbPondV2} from "../src/OrbPondV2.sol";
import {OrbPondTestUpgrade} from "../src/test-upgrades/OrbPondTestUpgrade.sol";
import {OrbInvocationRegistry} from "../src/OrbInvocationRegistry.sol";
import {Orb} from "../src/Orb.sol";
import {OrbV2} from "../src/OrbV2.sol";
import {OrbTestUpgrade} from "../src/test-upgrades/OrbTestUpgrade.sol";
import {IOrb} from "../src/IOrb.sol";

/* solhint-disable func-name-mixedcase,private-vars-leading-underscore */
contract OrbPondTestBase is Test {
    PaymentSplitter internal paymentSplitterImplementation;

    OrbInvocationRegistry internal orbInvocationRegistryImplementation;
    OrbInvocationRegistry internal orbInvocationRegistry;

    OrbPond internal orbPondV1Implementation;
    OrbPondV2 internal orbPondV2Implementation;
    OrbPondV2 internal orbPond;

    Orb internal orbV1Implementation;
    OrbV2 internal orbV2Implementation;

    address[] internal beneficiaryPayees = new address[](2);
    uint256[] internal beneficiaryShares = new uint256[](2);

    address internal owner;
    address internal user;
    address internal beneficiary;

    function setUp() public {
        orbInvocationRegistryImplementation = new OrbInvocationRegistry();
        orbPondV1Implementation = new OrbPond();
        orbPondV2Implementation = new OrbPondV2();
        orbV1Implementation = new Orb();
        orbV2Implementation = new OrbV2();
        paymentSplitterImplementation = new PaymentSplitter();

        beneficiaryPayees[0] = address(0xC0FFEE);
        beneficiaryPayees[1] = address(0xFACEBABE);
        beneficiaryShares[0] = 95;
        beneficiaryShares[1] = 5;

        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(
            address(orbInvocationRegistryImplementation),
            abi.encodeWithSelector(OrbInvocationRegistry.initialize.selector)
        );
        orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));

        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondV1Implementation),
            abi.encodeWithSelector(
                OrbPond.initialize.selector,
                address(orbInvocationRegistry),
                address(paymentSplitterImplementation)
            )
        );
        OrbPond orbPondV1 = OrbPond(address(orbPondProxy));
        bytes memory orbPondV1InitializeCalldata =
            abi.encodeWithSelector(Orb.initialize.selector, address(0), "", "", "");
        orbPondV1.registerVersion(1, address(orbV1Implementation), orbPondV1InitializeCalldata);
        orbPondV1.upgradeToAndCall(
            address(orbPondV2Implementation), abi.encodeWithSelector(OrbPondV2.initializeV2.selector, 1)
        );
        orbPond = OrbPondV2(address(orbPondProxy));

        user = address(0xBEEF);
        // vm.deal(user, 10000 ether);
        owner = orbPond.owner();
        beneficiary = address(0xC0FFEE);
    }

    function deployDefaults() public returns (Orb orb) {
        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "TestOrb", "TEST", "test baseURI");
        return Orb(orbPond.orbs(0));
    }
}

contract InitialStateTest is OrbPondTestBase {
    // Test that the initial state is correct
    function test_initialState() public {
        // Note: needs to be updated with every new version
        assertEq(orbPond.version(), 2);
        assertEq(orbPond.latestVersion(), 1);
        assertEq(orbPond.registry(), address(orbInvocationRegistry));
        assertEq(orbPond.orbCount(), 0);
    }

    function test_revertsInitializer() public {
        vm.expectRevert("Initializable: contract is already initialized");
        orbPond.initialize(address(0), address(0));
    }

    function test_initializerSequenceSuccess() public {
        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondV1Implementation), ""
        );
        OrbPond _orbPondV1 = OrbPond(address(orbPondProxy));
        assertEq(_orbPondV1.owner(), address(0));
        assertEq(_orbPondV1.registry(), address(0));
        _orbPondV1.initialize(address(0xBABEFACE), address(0xFACEBABE));
        assertEq(_orbPondV1.owner(), address(this));
        assertEq(_orbPondV1.registry(), address(0xBABEFACE));
        assertEq(_orbPondV1.paymentSplitterImplementation(), address(0xFACEBABE));

        _orbPondV1.upgradeToAndCall(
            address(orbPondV2Implementation), abi.encodeWithSelector(OrbPondV2.initializeV2.selector, 17)
        );
        OrbPondV2 _orbPondV2 = OrbPondV2(address(orbPondProxy));
        assertEq(_orbPondV2.orbInitialVersion(), 17);
    }
}

contract CreateOrbTest is OrbPondTestBase {
    function test_revertWhen_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "TestOrb", "TEST", "test baseURI");
    }

    event Creation();
    event OrbCreation(uint256 indexed orbId, address indexed orbAddress);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function test_createOrb() public {
        assertEq(orbPond.orbCount(), 0);

        vm.expectEmit(true, true, true, true);
        emit Creation();

        vm.expectEmit(true, false, false, true);
        emit OwnershipTransferred(address(orbPond), address(this));

        vm.expectEmit(true, true, true, true);
        emit OrbCreation(0, 0x7bb886E6fCe69554E427e4DCC5CD8EAf5A3C9dd0);

        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "TestOrb", "TEST", "test baseURI");

        Orb orb = Orb(orbPond.orbs(0));

        assertEq(orb.owner(), address(this));
        assertEq(PaymentSplitter(payable(orb.beneficiary())).totalShares(), 100);
        assertEq(orb.name(), "TestOrb");
        assertEq(orb.symbol(), "TEST");
        assertEq(orb.tokenURI(1), "test baseURI");

        assertEq(orbPond.orbCount(), 1);
    }
}

contract PaymentSplitterTest is OrbPondTestBase {
    event PaymentReleased(address to, uint256 amount);

    function test_paymentSplitter() public {
        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "TestOrb", "TEST", "test baseURI");
        Orb orb = Orb(orbPond.orbs(0));
        PaymentSplitter paymentSplitter = PaymentSplitter(payable(orb.beneficiary()));

        assertEq(paymentSplitter.totalShares(), 100);
        assertEq(paymentSplitter.totalReleased(), 0);
        assertEq(paymentSplitter.payee(0), address(0xC0FFEE));
        assertEq(paymentSplitter.payee(1), address(0xFACEBABE));
        assertEq(paymentSplitter.shares(address(0xC0FFEE)), 95);
        assertEq(paymentSplitter.shares(address(0xFACEBABE)), 5);
        assertEq(paymentSplitter.releasable(address(0xC0FFEE)), 0);
        assertEq(paymentSplitter.releasable(address(0xFACEBABE)), 0);

        vm.expectRevert("Initializable: contract is already initialized");
        paymentSplitter.initialize(beneficiaryPayees, beneficiaryShares);

        (bool success,) = payable(paymentSplitter).call{value: 100 ether}("");
        assertTrue(success);
        assertEq(paymentSplitter.totalReleased(), 0);
        assertEq(address(paymentSplitter).balance, 100 ether);
        assertEq(paymentSplitter.releasable(address(0xC0FFEE)), 95 ether);
        assertEq(paymentSplitter.releasable(address(0xFACEBABE)), 5 ether);

        assertEq(address(0xC0FFEE).balance, 0);
        vm.expectEmit(true, true, true, true);
        emit PaymentReleased(address(0xC0FFEE), 95 ether);
        paymentSplitter.release(payable(address(0xC0FFEE)));
        assertEq(address(0xC0FFEE).balance, 95 ether);
        assertEq(address(paymentSplitter).balance, 5 ether);

        vm.expectRevert("PaymentSplitter: account is not due payment");
        paymentSplitter.release(payable(address(0xC0FFEE)));

        vm.expectRevert("PaymentSplitter: account has no shares");
        paymentSplitter.release(payable(address(0xBAADF00D)));
    }
}

contract RegisterVersionTest is OrbPondTestBase {
    event VersionRegistration(uint256 indexed versionNumber, address indexed implementation);

    function test_revertWhen_NotOwner() public {
        OrbTestUpgrade orbTestUpgradeImplementation = new OrbTestUpgrade();
        uint256 latestVersion = orbPond.latestVersion();

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orbPond.registerVersion(latestVersion + 1, address(orbTestUpgradeImplementation), "");
    }

    function test_revertWhen_UnsettingNotLatest() public {
        OrbTestUpgrade orbTestUpgradeImplementation = new OrbTestUpgrade();
        uint256 latestVersion = orbPond.latestVersion();

        vm.prank(owner);
        orbPond.registerVersion(latestVersion + 1, address(orbTestUpgradeImplementation), "");
        vm.prank(owner);
        orbPond.registerVersion(latestVersion + 2, address(orbTestUpgradeImplementation), "");

        vm.prank(owner);
        vm.expectRevert(OrbPond.InvalidVersion.selector);
        orbPond.registerVersion(latestVersion + 1, address(0), "");
    }

    function test_revertWhen_TooLargeVersion() public {
        OrbTestUpgrade orbTestUpgradeImplementation = new OrbTestUpgrade();
        uint256 latestVersion = orbPond.latestVersion();

        vm.prank(owner);
        vm.expectRevert(OrbPond.InvalidVersion.selector);
        orbPond.registerVersion(latestVersion + 2, address(orbTestUpgradeImplementation), "");
    }

    function test_registerNewVersion() public {
        OrbTestUpgrade orbTestUpgradeImplementation = new OrbTestUpgrade();
        uint256 latestVersion = orbPond.latestVersion();

        vm.expectEmit(true, true, true, true);
        emit VersionRegistration(latestVersion + 1, address(orbTestUpgradeImplementation));
        vm.prank(owner);
        orbPond.registerVersion(latestVersion + 1, address(orbTestUpgradeImplementation), "randomdata");
        assertEq(orbPond.versions(latestVersion + 1), address(orbTestUpgradeImplementation));
        assertEq(orbPond.upgradeCalldata(latestVersion + 1), "randomdata");
        assertEq(orbPond.latestVersion(), latestVersion + 1);
    }

    function test_changeExistingVersion() public {
        OrbTestUpgrade orbTestUpgradeImplementation = new OrbTestUpgrade();
        uint256 latestVersion = orbPond.latestVersion();

        vm.expectEmit(true, true, true, true);
        emit VersionRegistration(latestVersion + 1, address(orbTestUpgradeImplementation));
        vm.prank(owner);
        orbPond.registerVersion(latestVersion + 1, address(orbTestUpgradeImplementation), "");
        assertEq(orbPond.versions(latestVersion + 1), address(orbTestUpgradeImplementation));

        vm.expectEmit(true, true, true, true);
        emit VersionRegistration(latestVersion + 1, address(orbV2Implementation));
        vm.prank(owner);
        orbPond.registerVersion(latestVersion + 1, address(orbV2Implementation), "");
        assertEq(orbPond.versions(latestVersion + 1), address(orbV2Implementation));
    }

    function test_unregisterVersion() public {
        OrbTestUpgrade orbTestUpgradeImplementation = new OrbTestUpgrade();
        uint256 latestVersion = orbPond.latestVersion();

        vm.expectEmit(true, true, true, true);
        emit VersionRegistration(latestVersion + 1, address(orbTestUpgradeImplementation));
        vm.prank(owner);
        orbPond.registerVersion(latestVersion + 1, address(orbTestUpgradeImplementation), "randomdata");
        assertEq(orbPond.versions(latestVersion + 1), address(orbTestUpgradeImplementation));
        assertEq(orbPond.upgradeCalldata(latestVersion + 1), "randomdata");
        assertEq(orbPond.latestVersion(), latestVersion + 1);

        vm.expectEmit(true, true, true, true);
        emit VersionRegistration(latestVersion + 1, address(0));
        vm.prank(owner);
        orbPond.registerVersion(latestVersion + 1, address(0), "");
        assertEq(orbPond.versions(latestVersion + 1), address(0));
        assertEq(orbPond.upgradeCalldata(latestVersion + 1), "");
        assertEq(orbPond.latestVersion(), latestVersion);
    }
}

contract SetOrbInitialVersionTest is OrbPondTestBase {
    event OrbInitialVersionUpdate(uint256 previousInitialVersion, uint256 indexed newInitialVersion);

    function test_revertWhen_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orbPond.setOrbInitialVersion(1);
    }

    function test_revertWhen_SetInitialVersionNotExisting() public {
        vm.prank(owner);
        vm.expectRevert(OrbPond.InvalidVersion.selector);
        orbPond.setOrbInitialVersion(2);
    }

    function test_setInitialOrbVersion() public {
        uint256 latestVersion = orbPond.latestVersion();

        bytes memory orbPondV1InitializeCalldata =
            abi.encodeWithSelector(Orb.initialize.selector, address(0), "", "", "");
        vm.prank(owner);
        orbPond.registerVersion(latestVersion + 1, address(orbV2Implementation), orbPondV1InitializeCalldata);
        assertEq(orbPond.versions(latestVersion + 1), address(orbV2Implementation));
        assertEq(orbPond.upgradeCalldata(latestVersion + 1), orbPondV1InitializeCalldata);
        assertEq(orbPond.latestVersion(), latestVersion + 1);
        assertEq(orbPond.orbCount(), 0);

        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "TestOrb", "TEST", "test baseURI");
        Orb orb1_ = Orb(orbPond.orbs(0));
        assertEq(orb1_.version(), 1);

        assertEq(orbPond.orbInitialVersion(), 1);

        vm.expectEmit(true, true, true, true);
        emit OrbInitialVersionUpdate(1, 2);
        vm.prank(owner);
        orbPond.setOrbInitialVersion(2);
        assertEq(orbPond.orbInitialVersion(), 2);

        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "TestOrb", "TEST", "test baseURI");
        Orb orb2_ = Orb(orbPond.orbs(1));
        assertEq(orb2_.version(), 2);
    }
}

contract UpgradeTest is OrbPondTestBase {
    function test_upgrade_revertOnlyOwner() public {
        OrbPondTestUpgrade orbPondTestUpgradeImplementation = new OrbPondTestUpgrade();
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        orbPond.upgradeToAndCall(
            address(orbPondTestUpgradeImplementation),
            abi.encodeWithSelector(OrbPondTestUpgrade.initializeTestUpgrade.selector, address(0xBABEFACE))
        );
    }

    function test_upgradeSucceeds() public {
        OrbPondTestUpgrade orbPondTestUpgradeImplementation = new OrbPondTestUpgrade();
        bytes4 orbLandWalletSelector = bytes4(keccak256("orbLandWallet()"));

        // Note: needs to be updated with every new Pond version
        assertEq(orbPond.version(), 2);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successBefore,) = address(orbPond).call(abi.encodeWithSelector(orbLandWalletSelector));
        assertEq(successBefore, false);

        orbPond.upgradeToAndCall(
            address(orbPondTestUpgradeImplementation),
            abi.encodeWithSelector(OrbPondTestUpgrade.initializeTestUpgrade.selector, address(0xBABEFACE))
        );

        assertEq(OrbPondTestUpgrade(address(orbPond)).orbLandWallet(), address(0xBABEFACE));
        assertEq(orbPond.version(), 100);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successAfter,) = address(orbPond).call(abi.encodeWithSelector(orbLandWalletSelector));
        assertEq(successAfter, true);

        vm.expectRevert("Initializable: contract is already initialized");
        OrbPondTestUpgrade(address(orbPond)).initializeTestUpgrade(address(0xCAFEBABE));
    }
}
