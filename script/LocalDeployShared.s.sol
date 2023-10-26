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
import {OrbInvocationTipJar} from "../src/OrbInvocationTipJar.sol";
import {Orb} from "../src/Orb.sol";
import {OrbV2} from "../src/OrbV2.sol";

contract LocalDeployShared is Script {
    address public immutable creatorAddress = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;
    address public immutable orbLandAddress = 0x9F49230672c52A2b958F253134BB17Ac84d30833;

    // Deploy addresses.
    PaymentSplitter public paymentSplitterImplementation;

    OrbInvocationRegistry public orbInvocationRegistryImplementation;
    OrbInvocationRegistry public orbInvocationRegistry;

    OrbInvocationTipJar public orbInvocationTipJarImplementation;
    OrbInvocationTipJar public orbInvocationTipJar;

    OrbPond public orbPondImplementation;
    OrbPondV2 public orbPondV2Implementation;
    OrbPondV2 public orbPond;

    Orb public orbImplementation;
    OrbV2 public orbV2Implementation;
    OrbV2 public orb;

    function deployContracts() public {
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

        orbInvocationTipJarImplementation = new OrbInvocationTipJar();
        console.log("OrbInvocationTipJar implementation: ", address(orbInvocationTipJarImplementation));

        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(
            address(orbInvocationRegistryImplementation),
            abi.encodeWithSelector(OrbInvocationRegistry.initialize.selector)
        );
        orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));
        console.log("OrbInvocationRegistry: ", address(orbInvocationRegistry));

        ERC1967Proxy orbInvocationTipJarProxy = new ERC1967Proxy(
            address(orbInvocationTipJarImplementation),
            abi.encodeWithSelector(OrbInvocationTipJar.initialize.selector, address(orbLandAddress), 5_00)
        );
        orbInvocationTipJar = OrbInvocationTipJar(address(orbInvocationTipJarProxy));
        console.log("OrbInvocationTipJar: ", address(orbInvocationTipJar));

        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondImplementation),
            abi.encodeWithSelector(
                OrbPond.initialize.selector,
                address(orbInvocationRegistry),
                address(paymentSplitterImplementation)
            )
        );
        bytes memory orbPondV1InitializeCalldata = abi.encodeWithSelector(
            Orb.initialize.selector,
            address(0),
            "",
            "",
            ""
        );
        OrbPond(address(orbPondProxy)).registerVersion(1, address(orbImplementation), orbPondV1InitializeCalldata);

        OrbPond(address(orbPondProxy)).upgradeToAndCall(
            address(orbPondV2Implementation),
            abi.encodeWithSelector(OrbPondV2.initializeV2.selector, 1)
        );
        orbPond = OrbPondV2(address(orbPondProxy));
        console.log("OrbPond (V2): ", address(orbPond));
        bytes memory orbPondV2InitializeCalldata = abi.encodeWithSelector(OrbV2.initializeV2.selector);
        orbPond.registerVersion(2, address(orbV2Implementation), orbPondV2InitializeCalldata);
        orbPond.setOrbInitialVersion(2);

        address[] memory beneficiaryAddresses = new address[](2);
        beneficiaryAddresses[0] = creatorAddress;
        beneficiaryAddresses[1] = orbLandAddress;
        uint256[] memory beneficiaryShares = new uint256[](2);
        beneficiaryShares[0] = 95;
        beneficiaryShares[1] = 5;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        deployContracts();
        vm.stopBroadcast();
    }
}
