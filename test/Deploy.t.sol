// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";

import {DeployLocal} from "../script/DeployLocal.s.sol";
import {Orb} from "../src/Orb.sol";

contract DeployMainnetTest is Test {
    DeployLocal internal deployScript;

    function setUp() public {
        vm.setEnv("DEPLOYER_PRIVATE_KEY", "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");

        vm.deal(vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY")), type(uint64).max);

        deployScript = new DeployLocal();
        deployScript.run();
    }

    function testOrbOwnership() public {
        assertEq(deployScript.orb().owner(), deployScript.creatorAddress());
    }

    function testBeneficiary() public {
        assertEq(deployScript.orb().beneficiary(), address(deployScript.orbBeneficiary()));
    }
}
