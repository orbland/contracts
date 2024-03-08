// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase,private-vars-leading-underscore
pragma solidity 0.8.20;

import {Test} from "../../lib/forge-std/src/Test.sol";

import {LocalDeployBase} from "../../script/LocalDeployBase.s.sol";
import {LocalDeployOrb} from "../../script/LocalDeployOrb.s.sol";

contract DeployLocalTest is Test {
    LocalDeployBase internal deployBaseScript;
    LocalDeployOrb internal deployOrbScript;

    function setUp() public {
        vm.setEnv("DEPLOYER_PRIVATE_KEY", "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
        vm.setEnv("CREATOR_PRIVATE_KEY", "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
        vm.setEnv("INITIAL_VERSION", "2");
        vm.setEnv("SWEAR_OATH", "true");

        vm.deal(vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY")), type(uint64).max);

        deployBaseScript = new LocalDeployBase();
        deployBaseScript.run();

        // deployOrbScript = new LocalDeployOrb();
        // deployOrbScript.run();
    }

    // function test_orbOwnership() public {
    //     // assertEq(deployBaseScript.orb().owner(), deployBaseScript.creatorAddress());
    // }

    // function test_beneficiary() public {
    //     // assertEq(deployBaseScript.orb().beneficiary(), address(deployBaseScript.orbBeneficiary()));
    // }
}
