// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* solhint-disable no-console */
import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";

import {Orb} from "../src/Orb.sol";
import {OrbPond} from "../src/OrbPond.sol";

contract OrbScenario is Script {
    address private immutable creatorAddress;
    Orb public orb;
    OrbPond public orbPond;

    /* solhint-disable quotes,max-line-length */
    string public oath =
        '{"oath":"My orb is my promise, and my promise is my orb.","allowPublicInvocations":true,"allowPrivateInvocations":true,"allowPrivateResponses":true,"allowReadPastInvocations":true,"allowRevealOwnInvocations":true,"allowRevealPastInvocations":true}';
    /* solhint-enable quotes,max-line-length */
    uint256 public immutable honoredUntil = 1_700_000_000;
    uint256 public immutable responsePeriod = 7 * 24 * 60 * 60;

    constructor() {
        creatorAddress = vm.envAddress("CREATOR_ADDRESS");
        orbPond = OrbPond(vm.envAddress("ORB_POND_ADDRESS"));
    }

    function run() external {
        uint256 creatorKey = vm.envUint("CREATOR_PRIVATE_KEY");

        // OrbPond = 0x5fbdb2315678afecb367f032d93f642f64180aa3
        // PaymentSplitter = 0xe7f1725e7734ce288f8367e1bb143e90bb3f0512
        // First Orb = 0xa16E02E87b7454126E5E10d957A927A7F5B5d2be

        orb = Orb(orbPond.orbs(0));
        console.log("orb address", address(orb));

        console.log("oath hash");
        console.logBytes32(keccak256(abi.encodePacked(oath)));

        vm.startBroadcast(creatorKey);
        orb.swearOath(keccak256(abi.encodePacked(oath)), honoredUntil, responsePeriod);
        vm.stopBroadcast();
    }
}
