// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

import {Orb} from "src/Orb.sol";
import {PaymentSplitter} from "@openzeppelin/contracts/finance/PaymentSplitter.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    address[] private contributorWallets;
    uint256[] private contributorShares;

    address private immutable issuerWallet;
    uint256 private immutable cooldown;
    uint256 private immutable responseFlaggingPeriod;
    uint256 private immutable minimumAuctionDuration;
    uint256 private immutable bidAuctionExtension;
    uint256 private immutable holderTaxNumerator;
    uint256 private immutable saleRoyaltiesNumerator;
    uint256 private immutable startingPrice;
    uint256 private immutable minimumBidStep;

    // Deploy addresses.
    PaymentSplitter public orbBeneficiary;
    Orb public orb;

    constructor(
        address[] memory _contributorWallets,
        uint256[] memory _contributorShares,
        address _issuerWallet,
        uint256 _cooldown,
        uint256 _responseFlaggingPeriod,
        uint256 _minimumAuctionDuration,
        uint256 _bidAuctionExtension,
        uint256 _holderTaxNumerator,
        uint256 _saleRoyaltiesNumerator,
        uint256 _startingPrice,
        uint256 _minimumBidStep
    ) {
        contributorWallets = _contributorWallets;
        contributorShares = _contributorShares;
        issuerWallet = _issuerWallet;
        cooldown = _cooldown;
        responseFlaggingPeriod = _responseFlaggingPeriod;
        minimumAuctionDuration = _minimumAuctionDuration;
        bidAuctionExtension = _bidAuctionExtension;
        holderTaxNumerator = _holderTaxNumerator;
        saleRoyaltiesNumerator = _saleRoyaltiesNumerator;
        startingPrice = _startingPrice;
        minimumBidStep = _minimumBidStep;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        orbBeneficiary = new PaymentSplitter(contributorWallets, contributorShares);
        address splitterAddress = address(orbBeneficiary);

        orb = new Orb(
            cooldown,
            responseFlaggingPeriod,
            minimumAuctionDuration,
            bidAuctionExtension,
            splitterAddress, // beneficiary
            holderTaxNumerator,
            saleRoyaltiesNumerator,
            startingPrice,
            minimumBidStep
        );
        orb.transferOwnership(issuerWallet);

        vm.stopBroadcast();
    }
}
