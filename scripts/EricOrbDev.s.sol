// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {EricOrb} from "src/EricOrb.sol";

contract DeployEricOrbDev is Script {
    function run() external {
        vm.startBroadcast();
        new EricOrb(
            5 minutes, // cooldown
            5 minutes, // responseFlaggingPeriod
            5 minutes, // minimumAuctionDuration
            30 seconds // bidAuctionExtension
        );
        vm.stopBroadcast();
    }
}
