// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* solhint-disable no-console */
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

import {OrbPond} from "src/OrbPond.sol";
import {OrbInvocationRegistry} from "src/OrbInvocationRegistry.sol";
import {Orb} from "src/Orb.sol";
import {IOrb} from "src/IOrb.sol";

/* solhint-disable func-name-mixedcase,private-vars-leading-underscore */
contract OrbPondTestBase is Test {
    OrbInvocationRegistry internal orbInvocationRegistryImplementation;
    OrbInvocationRegistry internal orbInvocationRegistry;

    OrbPond internal orbPondImplementation;
    OrbPond internal orbPond;

    Orb internal orbImplementation;
    // Orb internal orb;

    address internal owner;
    address internal user;
    address internal beneficiary;

    function setUp() public {
        orbInvocationRegistryImplementation = new OrbInvocationRegistry();
        orbPondImplementation = new OrbPond();
        orbImplementation = new Orb();

        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(
            address(orbInvocationRegistryImplementation),
            abi.encodeWithSelector(OrbInvocationRegistry.initialize.selector)
        );
        orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));

        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondImplementation),
            abi.encodeWithSelector(OrbPond.initialize.selector, address(orbInvocationRegistry))
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
        orbPond.createOrb(beneficiary, "TestOrb", "TEST", "test baseURI");

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
}

contract DeployTest is OrbPondTestBase {
    function test_revertWhen_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orbPond.createOrb(beneficiary, "TestOrb", "TEST", "test baseURI");
    }

    event Creation();
    event OrbCreation(uint256 indexed orbId, address indexed orbAddress);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function test_deploy() public {
        vm.expectEmit(true, true, true, true);
        emit Creation();

        vm.expectEmit(true, false, false, true);
        emit OwnershipTransferred(address(orbPond), address(this));

        vm.expectEmit(true, true, true, true);
        emit OrbCreation(0, 0xa38D17ef017A314cCD72b8F199C0e108EF7Ca04c);

        orbPond.createOrb(beneficiary, "TestOrb", "TEST", "test baseURI");

        Orb orb = Orb(orbPond.orbs(0));

        assertEq(orb.owner(), address(this));
    }
}
