// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {Orb} from "src/Orb.sol";
import {OrbPond} from "src/OrbPond.sol";
import {PaymentSplitter} from "openzeppelin-contracts/contracts/finance/PaymentSplitter.sol";

/* solhint-disable private-vars-leading-underscore */
abstract contract DeployBase is Script {
    // Environment specific variables.
    address[] private beneficiaryAddresses;
    uint256[] private beneficiaryShares;

    address private immutable creatorAddress;

    string private orbName;
    string private orbSymbol;
    uint256 private immutable tokenId;

    uint256 private immutable auctionStartingPrice;
    uint256 private immutable auctionMinimumBidStep;
    uint256 private immutable auctionMinimumDuration;
    uint256 private immutable auctionKeeperMinimumDuration;
    uint256 private immutable auctionBidExtension;

    uint256 private immutable keeperTaxNumerator;
    uint256 private immutable royaltyNumerator;

    uint256 private immutable cooldown;
    uint256 private immutable flaggingPeriod;

    uint256 private immutable cleartextMaximumLength;

    // Deploy addresses.
    PaymentSplitter public orbBeneficiary;
    Orb public orb;
    OrbPond public orbPond;

    constructor(
        address[] memory _beneficiaryAddresses,
        uint256[] memory _beneficiaryShares,
        address _creatorAddress,
        string memory _orbName,
        string memory _orbSymbol,
        uint256 _tokenId,
        uint256 _auctionStartingPrice,
        uint256 _auctionMinimumBidStep,
        uint256 _auctionMinimumDuration,
        uint256 _auctionKeeperMinimumDuration,
        uint256 _auctionBidExtension,
        uint256 _keeperTaxNumerator,
        uint256 _royaltyNumerator,
        uint256 _cooldown,
        uint256 _flaggingPeriod,
        uint256 _cleartextMaximumLength
    ) {
        beneficiaryAddresses = _beneficiaryAddresses;
        beneficiaryShares = _beneficiaryShares;
        creatorAddress = _creatorAddress;

        orbName = _orbName;
        orbSymbol = _orbSymbol;
        tokenId = _tokenId;

        auctionStartingPrice = _auctionStartingPrice;
        auctionMinimumBidStep = _auctionMinimumBidStep;
        auctionMinimumDuration = _auctionMinimumDuration;
        auctionKeeperMinimumDuration = _auctionKeeperMinimumDuration;
        auctionBidExtension = _auctionBidExtension;

        keeperTaxNumerator = _keeperTaxNumerator;
        royaltyNumerator = _royaltyNumerator;

        cooldown = _cooldown;
        flaggingPeriod = _flaggingPeriod;

        cleartextMaximumLength = _cleartextMaximumLength;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        orbPond = new OrbPond();

        orbBeneficiary = new PaymentSplitter(beneficiaryAddresses, beneficiaryShares);
        address splitterAddress = address(orbBeneficiary);

        orbPond.createOrb(
            orbName,
            orbSymbol,
            tokenId, // tokenId
            splitterAddress, // beneficiary
            "https://static.orb.land/orb/" // baseURI
        );
        orb = Orb(orbPond.orbs(0));

        orbPond.configureOrb(
            0,
            auctionStartingPrice,
            auctionMinimumBidStep,
            auctionMinimumDuration,
            auctionKeeperMinimumDuration,
            auctionBidExtension,
            keeperTaxNumerator,
            royaltyNumerator,
            cooldown,
            flaggingPeriod,
            cleartextMaximumLength
        );

        orbPond.transferOrbOwnership(0, creatorAddress);

        vm.stopBroadcast();
    }
}
