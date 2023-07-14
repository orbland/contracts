// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* solhint-disable no-console */
import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PaymentSplitter} from "../src/CustomPaymentSplitter.sol";
import {OrbPond} from "../src/OrbPond.sol";
import {OrbPondV2} from "../src/OrbPondV2.sol";
import {OrbInvocationRegistry} from "../src/OrbInvocationRegistry.sol";
import {Orb} from "../src/Orb.sol";
import {OrbV2} from "../src/OrbV2.sol";
import {IOrb} from "../src/IOrb.sol";

/* solhint-disable func-name-mixedcase,private-vars-leading-underscore */
contract OrbPondTestBase is Test {
    PaymentSplitter internal paymentSplitterImplementation;

    OrbInvocationRegistry internal orbInvocationRegistryImplementation;
    OrbInvocationRegistry internal orbInvocationRegistry;

    OrbPond internal orbPondImplementation;
    OrbPond internal orbPond;

    Orb internal orbImplementation;
    // Orb internal orb;

    address[] beneficiaryPayees = new address[](2);
    uint256[] beneficiaryShares = new uint256[](2);

    address internal owner;
    address internal user;
    address internal beneficiary;

    function setUp() public {
        orbInvocationRegistryImplementation = new OrbInvocationRegistry();
        orbPondImplementation = new OrbPond();
        orbImplementation = new Orb();
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
            address(orbPondImplementation),
            abi.encodeWithSelector(
                OrbPond.initialize.selector,
                address(orbInvocationRegistry),
                address(paymentSplitterImplementation)
            )
        );
        orbPond = OrbPond(address(orbPondProxy));
        bytes memory orbPondV1InitializeCalldata =
            abi.encodeWithSelector(Orb.initialize.selector, address(0), "", "", "");
        orbPond.registerVersion(1, address(orbImplementation), orbPondV1InitializeCalldata);

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
        assertEq(orbPond.version(), 1);
        assertEq(orbPond.registry(), address(orbInvocationRegistry));
        assertEq(orbPond.orbCount(), 0);
    }

    function test_revertsInitializer() public {
        vm.expectRevert("Initializable: contract is already initialized");
        orbPond.initialize(address(0), address(0));
    }

    function test_initializerSuccess() public {
        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondImplementation), ""
        );
        OrbPond _orbPond = OrbPond(address(orbPondProxy));
        assertEq(_orbPond.owner(), address(0));
        assertEq(_orbPond.registry(), address(0));
        _orbPond.initialize(address(0xBABEFACE), address(0xFACEBABE));
        assertEq(_orbPond.owner(), address(this));
        assertEq(_orbPond.registry(), address(0xBABEFACE));
        assertEq(_orbPond.paymentSplitterImplementation(), address(0xFACEBABE));
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
        emit OrbCreation(0, 0xf5Ba21691a8bC011B7b430854B41d5be0B78b938);

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
    function test_revertWhen_NotOwner() public {
        OrbV2 orbV2Implementation = new OrbV2();

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orbPond.registerVersion(2, address(orbV2Implementation), "");
    }

    function test_revertWhen_UnsettingNotLatest() public {
        OrbV2 orbV2Implementation = new OrbV2();

        vm.prank(owner);
        orbPond.registerVersion(2, address(orbV2Implementation), "");
        vm.prank(owner);
        orbPond.registerVersion(3, address(orbV2Implementation), "");

        vm.prank(owner);
        vm.expectRevert(OrbPond.InvalidVersion.selector);
        orbPond.registerVersion(2, address(0), "");
    }

    function test_revertWhen_TooLargeVersion() public {
        OrbV2 orbV2Implementation = new OrbV2();

        vm.prank(owner);
        vm.expectRevert(OrbPond.InvalidVersion.selector);
        orbPond.registerVersion(3, address(orbV2Implementation), "");
    }

    function test_registerNewVersion() public {
        OrbV2 orbV2Implementation = new OrbV2();
        assertEq(orbPond.latestVersion(), 1);

        vm.prank(owner);
        orbPond.registerVersion(2, address(orbV2Implementation), "randomdata");
        assertEq(orbPond.versions(2), address(orbV2Implementation));
        assertEq(orbPond.upgradeCalldata(2), "randomdata");
        assertEq(orbPond.latestVersion(), 2);
    }

    function test_changeExistingVersion() public {
        OrbV2 orbV2Implementation = new OrbV2();
        vm.prank(owner);
        orbPond.registerVersion(2, address(orbV2Implementation), "");
        assertEq(orbPond.versions(2), address(orbV2Implementation));

        orbPond.registerVersion(2, address(orbImplementation), "");
        assertEq(orbPond.versions(2), address(orbImplementation));
    }

    function test_unregisterVersion() public {
        OrbV2 orbV2Implementation = new OrbV2();
        vm.prank(owner);
        orbPond.registerVersion(2, address(orbV2Implementation), "randomdata");
        assertEq(orbPond.versions(2), address(orbV2Implementation));
        assertEq(orbPond.upgradeCalldata(2), "randomdata");
        assertEq(orbPond.latestVersion(), 2);

        orbPond.registerVersion(2, address(0), "");
        assertEq(orbPond.versions(2), address(0));
        assertEq(orbPond.upgradeCalldata(2), "");
        assertEq(orbPond.latestVersion(), 1);
    }
}

contract UpgradeTest is OrbPondTestBase {
    function test_upgrade_revertOnlyOwner() public {
        OrbPondV2 orbPondV2Implementation = new OrbPondV2();
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        orbPond.upgradeToAndCall(
            address(orbPondV2Implementation),
            abi.encodeWithSelector(OrbPondV2.initializeV2.selector, address(0xBABEFACE))
        );
    }

    function test_upgradeSucceeds() public {
        OrbPondV2 orbPondV2Implementation = new OrbPondV2();
        bytes4 orbLandWalletSelector = bytes4(keccak256("orbLandWallet()"));

        assertEq(orbPond.version(), 1);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successBefore,) = address(orbPond).call(abi.encodeWithSelector(orbLandWalletSelector));
        assertEq(successBefore, false);

        orbPond.upgradeToAndCall(
            address(orbPondV2Implementation),
            abi.encodeWithSelector(OrbPondV2.initializeV2.selector, address(0xBABEFACE))
        );

        assertEq(OrbPondV2(address(orbPond)).orbLandWallet(), address(0xBABEFACE));
        assertEq(orbPond.version(), 2);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successAfter,) = address(orbPond).call(abi.encodeWithSelector(orbLandWalletSelector));
        assertEq(successAfter, true);

        vm.expectRevert("Initializable: contract is already initialized");
        OrbPondV2(address(orbPond)).initializeV2(address(0xCAFEBABE));
    }
}
