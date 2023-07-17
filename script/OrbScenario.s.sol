// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* solhint-disable no-console */
import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";

import {Orb} from "../src/Orb.sol";

contract OrbScenario is Script {
    bytes32 public immutable oathHash = 0x7f504772a68002f66cb889faaf26ccb17f5da54cfc0032f12f8bdce7f64242de;
    uint256 public immutable honoredUntil = 1_700_000_000;
    uint256 public immutable responsePeriod = 7 * 24 * 60 * 60;

    function run() external {
        Orb orb = Orb(vm.envAddress("ORB_ADDRESS"));
        vm.startBroadcast(vm.envUint("CREATOR_PRIVATE_KEY"));
        orb.swearOath(oathHash, honoredUntil, responsePeriod);
        vm.stopBroadcast();

        // bytes32 oathHash = keccak256(abi.encodePacked(oath));
        // console.log("Oath hash:");
        // console.logBytes32(oathHash);
    }
}
