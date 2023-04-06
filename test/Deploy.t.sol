// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DeployLocal} from "../scripts/DeployLocal.s.sol";
import {EricOrb} from "src/EricOrb.sol";

contract DeployMainnetTest is Test {
    DeployLocal internal deployScript;

    function setUp() public {
        vm.setEnv("DEPLOYER_PRIVATE_KEY", "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");

        vm.deal(vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY")), type(uint64).max);

        deployScript = new DeployLocal();
        deployScript.run();
    }

    function testOrbOwnership() public {
        assertEq(deployScript.ericOrb().owner(), deployScript.issuerWallet());
    }

    function testBeneficiary() public {
        assertEq(deployScript.ericOrb().beneficiary(), address(deployScript.orbBeneficiary()));
    }
}
