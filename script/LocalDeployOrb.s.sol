// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable no-console */
import {console} from "../lib/forge-std/src/console.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PaymentSplitter} from "../src/legacy/CustomPaymentSplitter.sol";
import {OrbPond} from "../src/legacy/OrbPond.sol";
import {OrbPondV2} from "../src/legacy/OrbPondV2.sol";
import {InvocationRegistry} from "../src/InvocationRegistry.sol";
import {InvocationTipJar} from "../src/InvocationTipJar.sol";
import {Orb} from "../src/legacy/OrbV1Renamed.sol";
import {OrbV2} from "../src/legacy/OrbV2.sol";

contract LocalDeployOrb is Script {
    address public immutable creatorAddress = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;
    address public immutable orbLandAddress = 0x9F49230672c52A2b958F253134BB17Ac84d30833;

    // Fixed base deployment addresses
    InvocationRegistry public immutable orbInvocationRegistry =
        InvocationRegistry(0xa513E6E4b8f2a923D98304ec87F64353C4D5C853);
    OrbPondV2 public immutable orbPond = OrbPondV2(0x8A791620dd6260079BF849Dc5567aDC3F2FdC318);
    InvocationTipJar public immutable orbInvocationTipJar = InvocationTipJar(0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6);

    PaymentSplitter public orbBeneficiary;
    OrbV2 public orb;

    string public orbName = "Test Orb";
    string public orbSymbol = "ORB";

    uint256 public immutable auctionStartingPrice = 0.1 ether;
    uint256 public immutable auctionMinimumBidStep = 0.1 ether;
    uint256 public immutable auctionMinimumDuration = 2 minutes;
    uint256 public immutable auctionKeeperMinimumDuration = 1 minutes;
    uint256 public immutable auctionBidExtension = 30 seconds;

    uint256 public immutable keeperTaxNumerator = 120_00;
    uint256 public immutable purchaseRoyaltyNumerator = 10_00;
    uint256 public immutable auctionRoyaltyNumerator = 30_00;

    uint256 public immutable cooldown = 2 minutes;
    uint256 public immutable responsePeriod = 7 * 24 * 60 * 60;
    uint256 public immutable flaggingPeriod = 5 minutes;
    uint256 public immutable cleartextMaximumLength = 280;

    bytes32 public immutable oathHash = 0x21144ebccf78f508f97c58c356209917be7cc4f7f8466da7b3bbacc1132af54c;
    uint256 public immutable honoredUntil = 1_800_000_000;

    function deployContracts() public {
        int256 initialVersion = vm.envInt("INITIAL_VERSION");
        bool createAsV1 = initialVersion == 1;
        if (createAsV1) {
            orbPond.setOrbInitialVersion(1);
        }

        address[] memory beneficiaryAddresses = new address[](2);
        beneficiaryAddresses[0] = creatorAddress;
        beneficiaryAddresses[1] = orbLandAddress;
        uint256[] memory beneficiaryShares = new uint256[](2);
        beneficiaryShares[0] = 95;
        beneficiaryShares[1] = 5;

        orbPond.createOrb(
            beneficiaryAddresses, beneficiaryShares, orbName, orbSymbol, "https://static.orb.land/localhost/metadata"
        );
        uint256 orbId = orbPond.orbCount() - 1;
        console.log("Orb: ", orbPond.orbs(orbId));

        orb = OrbV2(orbPond.orbs(orbId));
        orbBeneficiary = PaymentSplitter(payable(orb.beneficiary()));
        console.log("Orb beneficiary: ", address(orbBeneficiary));

        console.log("Orb version: ", orb.version());
        console.log("Orb implementation: ", orbPond.versions(orb.version()));

        orb.setAuctionParameters(
            auctionStartingPrice,
            auctionMinimumBidStep,
            auctionMinimumDuration,
            auctionKeeperMinimumDuration,
            auctionBidExtension
        );

        if (createAsV1) {
            Orb orbV1 = Orb(orb);
            orbV1.setFees(keeperTaxNumerator, purchaseRoyaltyNumerator);
            orbV1.setCooldown(cooldown, flaggingPeriod);
            orbV1.setCleartextMaximumLength(cleartextMaximumLength);
        } else {
            orb.setFees(keeperTaxNumerator, purchaseRoyaltyNumerator, auctionRoyaltyNumerator);
            orb.setInvocationParameters(cooldown, responsePeriod, flaggingPeriod, cleartextMaximumLength);
        }

        orb.transferOwnership(creatorAddress);
        console.log("Orb ownership transferred to: ", creatorAddress);

        if (createAsV1) {
            orbPond.setOrbInitialVersion(2);
        }
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 creatorKey = vm.envUint("CREATOR_PRIVATE_KEY");

        int256 initialVersion = vm.envInt("INITIAL_VERSION");
        bool createAsV1 = initialVersion == 1;

        vm.startBroadcast(deployerKey);
        deployContracts();
        vm.stopBroadcast();

        if (vm.envBool("SWEAR_OATH")) {
            console.log("Swearing Oath");
            vm.startBroadcast(creatorKey);
            if (createAsV1) {
                Orb orbV1 = Orb(orb);
                orbV1.swearOath(oathHash, honoredUntil, responsePeriod);
            } else {
                orb.swearOath(oathHash, honoredUntil);
            }
            orb.listWithPrice(1 ether);
            orbInvocationTipJar.setMinimumTip(1, 0.05 ether);
            orb.relinquish(false);
            vm.stopBroadcast();
        }
    }
}
