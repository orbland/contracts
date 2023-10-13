// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";

import {LocalDeploy} from "../script/LocalDeploy.s.sol";
import {Orb} from "../src/Orb.sol";

/* solhint-disable func-name-mixedcase,private-vars-leading-underscore */
contract DeployLocalTest is Test {
    LocalDeploy internal deployScript;

    function setUp() public {
        vm.setEnv("DEPLOYER_PRIVATE_KEY", "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        vm.setEnv("CREATOR_PRIVATE_KEY", "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        vm.setEnv("WITH_OATH", "false");

        vm.deal(vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY")), type(uint64).max);

        deployScript = new LocalDeploy();
        deployScript.run();
    }

    function test_orbOwnership() public {
        assertEq(deployScript.orb().owner(), deployScript.creatorAddress());
    }

    function test_beneficiary() public {
        assertEq(deployScript.orb().beneficiary(), address(deployScript.orbBeneficiary()));
    }
}
