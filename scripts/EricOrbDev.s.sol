// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {EricOrb} from "src/EricOrb.sol";

contract DeployEricOrbDev is Script {
    function run() external {
        vm.startBroadcast();
        new EricOrb(
            2 minutes, // cooldown
            2 minutes, // responseFlaggingPeriod
            2 minutes, // minimumAuctionDuration
            30 seconds // bidAuctionExtension
        );
        vm.stopBroadcast();
    }
}
