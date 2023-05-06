// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

import {Orb} from "src/Orb.sol";
import {PaymentSplitter} from "@openzeppelin/contracts/finance/PaymentSplitter.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    address[] private contributorWallets;
    uint256[] private contributorShares;

    address private immutable creatorAddress;
    uint256 private immutable tokenId;

    // Deploy addresses.
    PaymentSplitter public orbBeneficiary;
    Orb public orb;

    constructor(
        address[] memory _contributorWallets,
        uint256[] memory _contributorShares,
        address _creatorAddress,
        uint256 _tokenId
    ) {
        contributorWallets = _contributorWallets;
        contributorShares = _contributorShares;
        creatorAddress = _creatorAddress;
        tokenId = _tokenId;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        orbBeneficiary = new PaymentSplitter(contributorWallets, contributorShares);
        address splitterAddress = address(orbBeneficiary);

        orb = new Orb(
            tokenId,
            splitterAddress // beneficiary
        );
        orb.transferOwnership(creatorAddress);

        vm.stopBroadcast();
    }
}
