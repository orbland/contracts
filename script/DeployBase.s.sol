// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

import {Orb} from "src/Orb.sol";
import {OrbPond} from "src/OrbPond.sol";
import {PaymentSplitter} from "@openzeppelin/contracts/finance/PaymentSplitter.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    address[] private beneficiaryAddresses;
    uint256[] private beneficiaryShares;

    address private immutable creatorAddress;

    string private orbName;
    string private orbSymbol;
    uint256 private immutable tokenId;

    string private oath;
    uint256 private immutable honoredUntil;

    uint256 private immutable auctionStartingPrice;
    uint256 private immutable auctionMinimumBidStep;
    uint256 private immutable auctionMinimumDuration;
    uint256 private immutable auctionBidExtension;

    uint256 private immutable holderTaxNumerator;
    uint256 private immutable royaltyNumerator;

    uint256 private immutable cooldown;

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
        string memory _oath,
        uint256 _honoredUntil,
        uint256 _auctionStartingPrice,
        uint256 _auctionMinimumBidStep,
        uint256 _auctionMinimumDuration,
        uint256 _auctionBidExtension,
        uint256 _holderTaxNumerator,
        uint256 _royaltyNumerator,
        uint256 _cooldown,
        uint256 _cleartextMaximumLength
    ) {
        beneficiaryAddresses = _beneficiaryAddresses;
        beneficiaryShares = _beneficiaryShares;
        creatorAddress = _creatorAddress;

        orbName = _orbName;
        orbSymbol = _orbSymbol;
        tokenId = _tokenId;

        oath = _oath;
        honoredUntil = _honoredUntil;

        auctionStartingPrice = _auctionStartingPrice;
        auctionMinimumBidStep = _auctionMinimumBidStep;
        auctionMinimumDuration = _auctionMinimumDuration;
        auctionBidExtension = _auctionBidExtension;

        holderTaxNumerator = _holderTaxNumerator;
        royaltyNumerator = _royaltyNumerator;

        cooldown = _cooldown;

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
            keccak256(abi.encodePacked(oath)), // oathHash
            honoredUntil,
            "https://static.orb.land/orb/" // baseURI
        );
        orb = Orb(orbPond.orbs(0));

        orbPond.configureOrb(
            0,
            auctionStartingPrice,
            auctionMinimumBidStep,
            auctionMinimumDuration,
            auctionBidExtension,
            holderTaxNumerator,
            royaltyNumerator,
            cooldown,
            cleartextMaximumLength
        );

        orbPond.transferOrbOwnership(0, creatorAddress);

        vm.stopBroadcast();
    }
}
