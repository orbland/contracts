// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* solhint-disable no-console */
import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";

import {Orb} from "../src/Orb.sol";

contract OrbScenario is Script {
    /* solhint-disable quotes,max-line-length */
    string public oath =
        '{"oath":"My orb is my promise, and my promise is my orb.","allowPublicInvocations":true,"allowPrivateInvocations":true,"allowPrivateResponses":true,"allowReadPastInvocations":true,"allowRevealOwnInvocations":true,"allowRevealPastInvocations":true}';
    /* solhint-enable quotes,max-line-length */
    uint256 public immutable honoredUntil = 1_700_000_000;
    uint256 public immutable responsePeriod = 7 * 24 * 60 * 60;

    function run() external {
        Orb orb = Orb(vm.envAddress("ORB_ADDRESS"));
        bytes32 oathHash = keccak256(abi.encodePacked(oath));
        console.log("Oath hash:");
        console.logBytes32(oathHash);

        vm.startBroadcast(vm.envUint("CREATOR_PRIVATE_KEY"));
        orb.swearOath(oathHash, honoredUntil, responsePeriod);
        vm.stopBroadcast();
    }
}
