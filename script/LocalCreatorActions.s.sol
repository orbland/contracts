// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable no-console */
import {console} from "../lib/forge-std/src/console.sol";
import {Script} from "../lib/forge-std/src/Script.sol";

import {OrbInvocationTipJar} from "../src/OrbInvocationTipJar.sol";
import {OrbV2} from "../src/OrbV2.sol";

contract LocalCreatorActions is Script {
    OrbV2 public orb;
    OrbInvocationTipJar public orbTipJar;

    bytes32 public immutable oathHash = 0x21144ebccf78f508f97c58c356209917be7cc4f7f8466da7b3bbacc1132af54c;
    uint256 public immutable honoredUntil = 1_700_000_000;
    uint256 public immutable responsePeriod = 7 * 24 * 60 * 60;

    function runCreatorActions() public {
        orb.swearOath(oathHash, honoredUntil, responsePeriod);

        orb.listWithPrice(50 ether);
        orbTipJar.setMinimumTip(address(orb), 0.05 ether);
        orb.relinquish(false);
    }

    function run() external {
        uint256 creatorKey = vm.envUint("CREATOR_PRIVATE_KEY");
        orb = OrbV2(vm.envAddress("ORB_ADDRESS"));
        orbTipJar = OrbInvocationTipJar(vm.envAddress("ORB_TIP_JAR_ADDRESS"));

        vm.startBroadcast(creatorKey);
        runCreatorActions();
        vm.stopBroadcast();
    }
}
