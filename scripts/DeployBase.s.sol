// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

import {EricOrb} from "src/EricOrb.sol";
import {PaymentSplitter} from "@openzeppelin/contracts/finance/PaymentSplitter.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    address[] internal contributorWallets;
    uint256[] internal contributorShares;

    address internal immutable issuerWallet;
    uint256 internal immutable cooldown;
    uint256 internal immutable responseFlaggingPeriod;
    uint256 internal immutable minimumAuctionDuration;
    uint256 internal immutable bidAuctionExtension;

    // Deploy addresses.
    PaymentSplitter public orbBeneficiary;
    EricOrb public ericOrb;

    constructor(
        address[] memory _contributorWallets,
        uint256[] memory _contributorShares,
        address _issuerWallet,
        uint256 _cooldown,
        uint256 _responseFlaggingPeriod,
        uint256 _minimumAuctionDuration,
        uint256 _bidAuctionExtension
    ) {
        contributorWallets = _contributorWallets;
        contributorShares = _contributorShares;
        issuerWallet = _issuerWallet;
        cooldown = _cooldown;
        responseFlaggingPeriod = _responseFlaggingPeriod;
        minimumAuctionDuration = _minimumAuctionDuration;
        bidAuctionExtension = _bidAuctionExtension;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        orbBeneficiary = new PaymentSplitter(contributorWallets, contributorShares);
        address splitterAddress = address(orbBeneficiary);

        ericOrb = new EricOrb(
            cooldown,
            responseFlaggingPeriod,
            minimumAuctionDuration,
            bidAuctionExtension,
            splitterAddress // beneficiary
        );
        ericOrb.transferOwnership(issuerWallet);

        vm.stopBroadcast();
    }
}
