// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

import {Orb} from "src/Orb.sol";
import {PaymentSplitter} from "@openzeppelin/contracts/finance/PaymentSplitter.sol";

abstract contract DeployBase is Script {
    // Environment specific variables.
    address[] private beneficiaryAddresses;
    uint256[] private beneficiaryShares;

    address private immutable creatorAddress;
    uint256 private immutable tokenId;

    // Deploy addresses.
    PaymentSplitter public orbBeneficiary;
    Orb public orb;

    constructor(
        address[] memory _beneficiaryAddresses,
        uint256[] memory _beneficiaryShares,
        address _creatorAddress,
        uint256 _tokenId
    ) {
        beneficiaryAddresses = _beneficiaryAddresses;
        beneficiaryShares = _beneficiaryShares;
        creatorAddress = _creatorAddress;
        tokenId = _tokenId;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        orbBeneficiary = new PaymentSplitter(beneficiaryAddresses, beneficiaryShares);
        address splitterAddress = address(orbBeneficiary);

        orb = new Orb(
            "Orb", // name
            "ORB", // symbol
            tokenId, // tokenId
            splitterAddress, // beneficiary
            keccak256(abi.encodePacked("test oath")), // oathHash
            1_700_000_000 // honoredUntil
        );
        orb.transferOwnership(creatorAddress);

        vm.stopBroadcast();
    }
}
