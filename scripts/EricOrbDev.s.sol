// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "src/EricOrbDev.sol";

contract DeployEricOrbDev is Script {
    function run() external {
        vm.startBroadcast();
        new EricOrbDev();
        vm.stopBroadcast();
    }
}
