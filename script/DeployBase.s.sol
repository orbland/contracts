// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable no-console */
import {console} from "../lib/forge-std/src/console.sol";
import {Script} from "../lib/forge-std/src/Script.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PaymentSplitter} from "../src/CustomPaymentSplitter.sol";
import {OrbPond} from "../src/OrbPond.sol";
import {OrbPondV2} from "../src/OrbPondV2.sol";
import {OrbInvocationRegistry} from "../src/OrbInvocationRegistry.sol";
import {Orb} from "../src/Orb.sol";
import {OrbV2} from "../src/OrbV2.sol";

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
    PaymentSplitter internal paymentSplitterImplementation;

    PaymentSplitter public orbBeneficiary;

    OrbInvocationRegistry public orbInvocationRegistryImplementation;
    OrbInvocationRegistry public orbInvocationRegistry;

    OrbPond public orbPondImplementation;
    OrbPondV2 public orbPondV2Implementation;
    OrbPondV2 public orbPond;

    Orb public orbImplementation;
    OrbV2 public orbV2Implementation;
    OrbV2 public orb;

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
        // address deployerAddress = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        orbInvocationRegistryImplementation = new OrbInvocationRegistry();
        console.log("OrbInvocationRegistry implementation: ", address(orbInvocationRegistryImplementation));

        orbPondImplementation = new OrbPond();
        console.log("OrbPond V1 implementation: ", address(orbPondImplementation));
        orbPondV2Implementation = new OrbPondV2();
        console.log("OrbPond V2 implementation: ", address(orbPondV2Implementation));

        orbImplementation = new Orb();
        console.log("Orb V1 implementation: ", address(orbImplementation));
        orbV2Implementation = new OrbV2();
        console.log("Orb V2 implementation: ", address(orbV2Implementation));

        paymentSplitterImplementation = new PaymentSplitter();
        console.log("PaymentSplitter implementation: ", address(paymentSplitterImplementation));

        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(
            address(orbInvocationRegistryImplementation),
            abi.encodeWithSelector(OrbInvocationRegistry.initialize.selector)
        );
        orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));
        console.log("OrbInvocationRegistry: ", address(orbInvocationRegistry));

        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondImplementation),
            abi.encodeWithSelector(
                OrbPond.initialize.selector,
                address(orbInvocationRegistry),
                address(paymentSplitterImplementation)
            )
        );
        bytes memory orbPondV1InitializeCalldata =
            abi.encodeWithSelector(Orb.initialize.selector, address(0), "", "", "");
        OrbPond(address(orbPondProxy)).registerVersion(1, address(orbImplementation), orbPondV1InitializeCalldata);

        OrbPond(address(orbPondProxy)).upgradeToAndCall(
            address(orbPondV2Implementation), abi.encodeWithSelector(OrbPondV2.initializeV2.selector, 1)
        );
        orbPond = OrbPondV2(address(orbPondProxy));
        console.log("OrbPond (V2): ", address(orbPond));
        orbPond.registerVersion(2, address(orbV2Implementation), orbPondV1InitializeCalldata);
        orbPond.setOrbInitialVersion(2);

        orbPond.createOrb(beneficiaryAddresses, beneficiaryShares, orbName, orbSymbol, "https://static.orb.land/orb/");
        orb = OrbV2(orbPond.orbs(0));
        console.log("Orb (V2): ", address(orb));
        orbBeneficiary = PaymentSplitter(payable(orb.beneficiary()));
        console.log("Orb beneficiary: ", address(orbBeneficiary));

        orb.setAuctionParameters(
            auctionStartingPrice,
            auctionMinimumBidStep,
            auctionMinimumDuration,
            auctionKeeperMinimumDuration,
            auctionBidExtension
        );
        orb.setFees(keeperTaxNumerator, royaltyNumerator);
        orb.setCooldown(cooldown, flaggingPeriod);
        orb.setCleartextMaximumLength(cleartextMaximumLength);

        orb.transferOwnership(creatorAddress);
        console.log("Orb ownership transferred to: ", creatorAddress);

        vm.stopBroadcast();
    }
}
