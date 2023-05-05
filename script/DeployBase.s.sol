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
    uint256 private immutable auctionMinimumDuration;
    uint256 private immutable auctionBidExtension;
    uint256 private immutable holderTaxNumerator;
    uint256 private immutable royaltyNumerator;
    uint256 private immutable auctionStartingPrice;
    uint256 private immutable auctionMinimumBidStep;

    // Deploy addresses.
    PaymentSplitter public orbBeneficiary;
    Orb public orb;

    constructor(
        address[] memory _contributorWallets,
        uint256[] memory _contributorShares,
        address _issuerWallet,
        uint256 _cooldown,
        uint256 _responseFlaggingPeriod,
        uint256 _auctionMinimumDuration,
        uint256 _auctionBidExtension,
        uint256 _holderTaxNumerator,
        uint256 _royaltyNumerator,
        uint256 _auctionStartingPrice,
        uint256 _auctionMinimumBidStep
    ) {
        contributorWallets = _contributorWallets;
        contributorShares = _contributorShares;
        issuerWallet = _issuerWallet;
        cooldown = _cooldown;
        responseFlaggingPeriod = _responseFlaggingPeriod;
        auctionMinimumDuration = _auctionMinimumDuration;
        auctionBidExtension = _auctionBidExtension;
        holderTaxNumerator = _holderTaxNumerator;
        royaltyNumerator = _royaltyNumerator;
        auctionStartingPrice = _auctionStartingPrice;
        auctionMinimumBidStep = _auctionMinimumBidStep;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        orbBeneficiary = new PaymentSplitter(contributorWallets, contributorShares);
        address splitterAddress = address(orbBeneficiary);

        orb = new Orb(
            cooldown,
            responseFlaggingPeriod,
            auctionMinimumDuration,
            auctionBidExtension,
            splitterAddress, // beneficiary
            holderTaxNumerator,
            royaltyNumerator,
            auctionStartingPrice,
            auctionMinimumBidStep
        );
        orb.transferOwnership(issuerWallet);

        vm.stopBroadcast();
    }
}
