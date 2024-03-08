// SPDX-License-Identifier: MIT
// solhint-disable no-console,func-name-mixedcase,private-vars-leading-underscore,one-contract-per-file
pragma solidity 0.8.20;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Address} from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {Initializable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {PaymentSplitter} from "../../src/legacy/CustomPaymentSplitter.sol";
import {OrbPond} from "../../src/legacy/OrbPond.sol";
import {OrbInvocationRegistry} from "../../src/legacy/OrbInvocationRegistry.sol";
import {OrbInvocationRegistryTestUpgrade} from "../../src/legacy/test-upgrades/OrbInvocationRegistryTestUpgrade.sol";
import {Orb} from "../../src/legacy/Orb.sol";
import {Orb} from "../../src/legacy/Orb.sol";
import {OrbInvocationRegistry} from "../../src/legacy/OrbInvocationRegistry.sol";
import {ExternalCallee} from "./ExternalCallee.sol";

contract OrbInvocationRegistryTestBase is Test {
    PaymentSplitter internal paymentSplitterImplementation;

    OrbInvocationRegistry internal orbInvocationRegistryImplementation;
    OrbInvocationRegistry internal orbInvocationRegistry;

    OrbPond internal orbPondImplementation;
    OrbPond internal orbPond;

    Orb internal orbImplementation;
    Orb internal orb;

    address internal admin;
    address internal beneficiary;
    address internal creator;
    address internal user;
    address internal user2;

    uint256 internal startingBalance;

    function setUp() public {
        admin = address(this);
        user = address(0xBEEF);
        user2 = address(0xFEEEEEB);

        address[] memory beneficiaryPayees = new address[](2);
        uint256[] memory beneficiaryShares = new uint256[](2);
        beneficiaryPayees[0] = address(0xC0FFEE);
        beneficiaryPayees[1] = address(0xFACEB00C);
        beneficiaryShares[0] = 95;
        beneficiaryShares[1] = 5;

        creator = address(0xCAFEBABE);
        startingBalance = 10_000 ether;
        vm.deal(user, startingBalance);
        vm.deal(user2, startingBalance);

        orbInvocationRegistryImplementation = new OrbInvocationRegistry();
        orbPondImplementation = new OrbPond();
        orbImplementation = new Orb();
        paymentSplitterImplementation = new PaymentSplitter();

        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(
            address(orbInvocationRegistryImplementation),
            abi.encodeWithSelector(OrbInvocationRegistry.initialize.selector)
        );
        orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));

        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondImplementation),
            abi.encodeWithSelector(
                OrbPond.initialize.selector, address(orbInvocationRegistry), address(paymentSplitterImplementation)
            )
        );
        orbPond = OrbPond(address(orbPondProxy));
        bytes memory orbPondV1InitializeCalldata =
            abi.encodeWithSelector(Orb.initialize.selector, address(0), "", "", "");
        orbPond.registerVersion(1, address(orbImplementation), orbPondV1InitializeCalldata);

        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "Orb", "ORB", "https://static.orb.land/orb/");

        orb = Orb(orbPond.orbs(0));
        beneficiary = orb.beneficiary();

        orb.swearOath(
            keccak256(abi.encodePacked("test oath")), // oathHash
            100, // 1_700_000_000 // honoredUntil
            3600 // responsePeriod
        );
        orb.setAuctionParameters(0.1 ether, 0.1 ether, 1 days, 6 hours, 5 minutes);
        orb.setCleartextMaximumLength(20);
        orb.transferOwnership(creator);

        vm.prank(creator);
        orb.startAuction();

        uint256 bidAmount = 1 ether;
        uint256 finalAmount = fundsRequiredToBidOneYear(bidAmount);
        vm.deal(user, startingBalance + finalAmount);
        vm.prank(user);
        orb.bid{value: finalAmount}(bidAmount, bidAmount);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);
    }

    function fundsRequiredToBidOneYear(uint256 amount) public view returns (uint256) {
        return amount + (amount * orb.keeperTaxNumerator()) / orb.feeDenominator();
    }
}

contract InitialStateTest is OrbInvocationRegistryTestBase {
    function test_initialState() public {
        assertEq(orbInvocationRegistry.version(), 1);
        assertEq(orbInvocationRegistry.invocationCount(address(orb)), 0);
        assertEq(orbInvocationRegistry.flaggedResponsesCount(address(orb)), 0);
    }

    function test_revertsInitializer() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        orbInvocationRegistry.initialize();
    }

    function test_initializerSuccess() public {
        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(address(orbInvocationRegistryImplementation), "");
        OrbInvocationRegistry _orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));
        assertEq(_orbInvocationRegistry.owner(), address(0));
        _orbInvocationRegistry.initialize();
        assertEq(_orbInvocationRegistry.owner(), address(this));
    }
}

contract SupportsInterfaceTest is OrbInvocationRegistryTestBase {
    // Test that the initial state is correct
    function test_supportsInterface() public view {
        // console.logBytes4(type(OrbInvocationRegistry).interfaceId);
        assert(orbInvocationRegistry.supportsInterface(0x01ffc9a7)); // ERC165 Interface ID for ERC165
        assert(orbInvocationRegistry.supportsInterface(0x767dfef3)); // ERC165 Interface ID for OrbInvocationRegistry
    }
}

contract InvokeWithCleartextTest is OrbInvocationRegistryTestBase {
    event Invocation(
        address indexed orb,
        uint256 indexed invocationId,
        address indexed invoker,
        uint256 timestamp,
        bytes32 contentHash
    );
    event CleartextRecording(address indexed orb, uint256 indexed invocationId, string cleartext);

    function test_revertsIfLongLength() public {
        vm.prank(creator);
        string memory text = "this text does not need to be very long to be too long";
        uint256 length = bytes(text).length;
        vm.expectRevert(abi.encodeWithSelector(OrbInvocationRegistry.CleartextTooLong.selector, length, 20));
        orbInvocationRegistry.invokeWithCleartext(address(orb), text);
    }

    function test_callsInvokeWithHashCorrectly() public {
        string memory text = "hi there";
        vm.expectEmit(true, true, true, true);
        emit Invocation(address(orb), 1, user, block.timestamp, keccak256(abi.encodePacked(text)));
        vm.expectEmit(true, true, true, true);
        emit CleartextRecording(address(orb), 1, text);
        vm.prank(user);
        orbInvocationRegistry.invokeWithCleartext(address(orb), text);
    }
}

contract InvokeWithCleartextAndCallTest is OrbInvocationRegistryTestBase {
    ExternalCallee public externalCallee;

    event Invocation(
        address indexed orb,
        uint256 indexed invocationId,
        address indexed invoker,
        uint256 timestamp,
        bytes32 contentHash
    );
    event CleartextRecording(address indexed orb, uint256 indexed invocationId, string cleartext);

    function test_revertsIfContractUnauthorized() public {
        externalCallee = new ExternalCallee();
        vm.expectRevert(
            abi.encodeWithSelector(OrbInvocationRegistry.ContractNotAuthorized.selector, address(externalCallee))
        );
        vm.prank(user);
        orbInvocationRegistry.invokeWithCleartextAndCall(
            address(orb),
            "hi three",
            address(externalCallee),
            abi.encodeWithSelector(ExternalCallee.setNumber.selector, 69)
        );
    }

    function test_passesRevertFromContract() public {
        externalCallee = new ExternalCallee();
        orbInvocationRegistry.authorizeContract(address(externalCallee), true);
        vm.expectRevert(abi.encodeWithSelector(ExternalCallee.InvalidNumber.selector, 0));
        vm.prank(user);
        orbInvocationRegistry.invokeWithCleartextAndCall(
            address(orb),
            "hi three",
            address(externalCallee),
            abi.encodeWithSelector(ExternalCallee.setNumber.selector, 0)
        );
    }

    function test_revertsFromContractIfFunctionNotFound() public {
        externalCallee = new ExternalCallee();
        orbInvocationRegistry.authorizeContract(address(externalCallee), true);
        vm.expectRevert(Address.FailedInnerCall.selector);
        vm.prank(user);
        orbInvocationRegistry.invokeWithCleartextAndCall(
            address(orb),
            "hi three",
            address(externalCallee),
            abi.encodeWithSelector(OrbInvocationRegistry.version.selector)
        );
    }

    function test_callsInvokeWithCleartextCorrectly() public {
        externalCallee = new ExternalCallee();
        orbInvocationRegistry.authorizeContract(address(externalCallee), true);
        assertEq(orbInvocationRegistry.invocationCount(address(orb)), 0);
        assertEq(externalCallee.number(), 42);
        string memory text = "hi there";
        vm.expectEmit(true, true, true, true);
        emit Invocation(address(orb), 1, user, block.timestamp, keccak256(abi.encodePacked(text)));
        vm.expectEmit(true, true, true, true);
        emit CleartextRecording(address(orb), 1, text);
        vm.prank(user);
        orbInvocationRegistry.invokeWithCleartextAndCall(
            address(orb), text, address(externalCallee), abi.encodeWithSelector(ExternalCallee.setNumber.selector, 69)
        );
        assertEq(orbInvocationRegistry.invocationCount(address(orb)), 1);
        assertEq(externalCallee.number(), 69);
    }
}

contract InvokeWthHashTest is OrbInvocationRegistryTestBase {
    event Invocation(
        address indexed orb,
        uint256 indexed invocationId,
        address indexed invoker,
        uint256 timestamp,
        bytes32 contentHash
    );

    function test_revertWhen_NotKeeper() public {
        bytes32 hash = keccak256(abi.encodePacked("hi there"));
        vm.prank(user2);
        vm.expectRevert(OrbInvocationRegistry.NotKeeper.selector);
        orbInvocationRegistry.invokeWithHash(address(orb), hash);

        vm.expectEmit(true, true, true, true);
        emit Invocation(address(orb), 1, user, block.timestamp, hash);
        vm.prank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), hash);
    }

    function test_revertWhen_KeeperInsolvent() public {
        bytes32 hash = keccak256(abi.encodePacked("hi there"));
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(OrbInvocationRegistry.KeeperInsolvent.selector);
        orbInvocationRegistry.invokeWithHash(address(orb), hash);
    }

    function test_revertWhen_CooldownIncomplete() public {
        bytes32 hash = keccak256(abi.encodePacked("hi there"));
        vm.startPrank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), hash);
        (address invocationUser1, bytes32 invocationHash1, uint256 invocationTimestamp1) =
            orbInvocationRegistry.invocations(address(orb), 1);
        assertEq(invocationUser1, user);
        assertEq(invocationHash1, hash);
        assertEq(invocationTimestamp1, block.timestamp);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrbInvocationRegistry.CooldownIncomplete.selector,
                block.timestamp - 1 days + orb.cooldown() - block.timestamp
            )
        );
        orbInvocationRegistry.invokeWithHash(address(orb), hash);
        (address invocationUser2, bytes32 invocationHash2, uint256 invocationTimestamp2) =
            orbInvocationRegistry.invocations(address(orb), 2);
        assertEq(invocationUser2, address(0));
        assertEq(invocationHash2, bytes32(0));
        assertEq(invocationTimestamp2, 0);
        vm.warp(block.timestamp + orb.cooldown() - 1 days + 1);
        orbInvocationRegistry.invokeWithHash(address(orb), hash);
        (address invocationUser3, bytes32 invocationHash3, uint256 invocationTimestamp3) =
            orbInvocationRegistry.invocations(address(orb), 2);
        assertEq(invocationUser3, user);
        assertEq(invocationHash3, hash);
        assertEq(invocationTimestamp3, block.timestamp);
    }

    function test_success() public {
        bytes32 hash = keccak256(abi.encodePacked("hi there"));
        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        emit Invocation(address(orb), 1, user, block.timestamp, hash);
        orbInvocationRegistry.invokeWithHash(address(orb), hash);
        (address invocactionUser, bytes32 invocationHash, uint256 invocationTimestamp) =
            orbInvocationRegistry.invocations(address(orb), 1);
        assertEq(invocactionUser, user);
        assertEq(invocationHash, hash);
        assertEq(invocationTimestamp, block.timestamp);
        assertEq(orb.lastInvocationTime(), block.timestamp);
        assertEq(orbInvocationRegistry.invocationCount(address(orb)), 1);
    }
}

contract InvokeWithHashAndCallTest is OrbInvocationRegistryTestBase {
    ExternalCallee public externalCallee;

    event Invocation(
        address indexed orb,
        uint256 indexed invocationId,
        address indexed invoker,
        uint256 timestamp,
        bytes32 contentHash
    );

    function test_revertsIfContractUnauthorized() public {
        externalCallee = new ExternalCallee();
        vm.expectRevert(
            abi.encodeWithSelector(OrbInvocationRegistry.ContractNotAuthorized.selector, address(externalCallee))
        );
        vm.prank(user);
        orbInvocationRegistry.invokeWithHashAndCall(
            address(orb),
            keccak256(abi.encodePacked("hi there")),
            address(externalCallee),
            abi.encodeWithSelector(ExternalCallee.setNumber.selector, 69)
        );
    }

    function test_passesRevertFromContract() public {
        externalCallee = new ExternalCallee();
        orbInvocationRegistry.authorizeContract(address(externalCallee), true);
        vm.expectRevert(abi.encodeWithSelector(ExternalCallee.InvalidNumber.selector, 0));
        vm.prank(user);
        orbInvocationRegistry.invokeWithHashAndCall(
            address(orb),
            keccak256(abi.encodePacked("hi there")),
            address(externalCallee),
            abi.encodeWithSelector(ExternalCallee.setNumber.selector, 0)
        );
    }

    function test_revertsFromContractIfFunctionNotFound() public {
        externalCallee = new ExternalCallee();
        orbInvocationRegistry.authorizeContract(address(externalCallee), true);
        vm.expectRevert(Address.FailedInnerCall.selector);
        vm.prank(user);
        orbInvocationRegistry.invokeWithHashAndCall(
            address(orb),
            keccak256(abi.encodePacked("hi there")),
            address(externalCallee),
            abi.encodeWithSelector(OrbInvocationRegistry.version.selector)
        );
    }

    function test_callsInvokeWithHashCorrectly() public {
        externalCallee = new ExternalCallee();
        orbInvocationRegistry.authorizeContract(address(externalCallee), true);
        assertEq(orbInvocationRegistry.invocationCount(address(orb)), 0);
        assertEq(externalCallee.number(), 42);
        bytes32 hash = keccak256(abi.encodePacked("hi there"));
        vm.expectEmit(true, true, true, true);
        emit Invocation(address(orb), 1, user, block.timestamp, hash);
        vm.prank(user);
        orbInvocationRegistry.invokeWithHashAndCall(
            address(orb), hash, address(externalCallee), abi.encodeWithSelector(ExternalCallee.setNumber.selector, 69)
        );
        assertEq(orbInvocationRegistry.invocationCount(address(orb)), 1);
        assertEq(externalCallee.number(), 69);
    }
}

contract RespondTest is OrbInvocationRegistryTestBase {
    event Response(
        address indexed orb,
        uint256 indexed invocationId,
        address indexed responder,
        uint256 timestamp,
        bytes32 contentHash
    );

    function test_revertWhen_notOwner() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));

        vm.expectRevert(OrbInvocationRegistry.NotCreator.selector);
        orbInvocationRegistry.respond(address(orb), 1, response);
        vm.stopPrank();

        vm.prank(creator);
        vm.expectEmit(true, true, true, true);
        emit Response(address(orb), 1, creator, block.timestamp, response);
        orbInvocationRegistry.respond(address(orb), 1, response);
    }

    function test_revertWhen_invocationIdIncorrect() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.stopPrank();

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(OrbInvocationRegistry.InvocationNotFound.selector, address(orb), 2));
        orbInvocationRegistry.respond(address(orb), 2, response);

        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(OrbInvocationRegistry.InvocationNotFound.selector, address(orb), 0));
        orbInvocationRegistry.respond(address(orb), 0, response);
    }

    function test_revertWhen_responseAlreadyExists() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.stopPrank();

        vm.startPrank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);
        vm.expectRevert(abi.encodeWithSelector(OrbInvocationRegistry.ResponseExists.selector, address(orb), 1));
        orbInvocationRegistry.respond(address(orb), 1, response);
    }

    function test_success() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.stopPrank();

        vm.prank(creator);
        vm.expectEmit(true, true, true, true);
        emit Response(address(orb), 1, creator, block.timestamp, response);
        orbInvocationRegistry.respond(address(orb), 1, response);
        (bytes32 hash, uint256 time) = orbInvocationRegistry.responses(address(orb), 1);
        assertEq(hash, response);
        assertEq(time, block.timestamp);
    }
}

contract FlagResponseTest is OrbInvocationRegistryTestBase {
    event ResponseFlagging(address indexed orb, uint256 indexed invocationId, address indexed flagger);

    function test_revertWhen_NotKeeper() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);
        vm.prank(user2);
        vm.expectRevert(OrbInvocationRegistry.NotKeeper.selector);
        orbInvocationRegistry.flagResponse(address(orb), 1);

        vm.prank(user);
        orbInvocationRegistry.flagResponse(address(orb), 1);
    }

    function test_revertWhen_KeeperInsolvent() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(OrbInvocationRegistry.KeeperInsolvent.selector);
        orbInvocationRegistry.flagResponse(address(orb), 1);

        vm.warp(block.timestamp - 13130000 days);
        vm.prank(user);
        orbInvocationRegistry.flagResponse(address(orb), 1);
    }

    function test_revertWhen_ResponseNotExist() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(OrbInvocationRegistry.ResponseNotFound.selector, address(orb), 188));
        orbInvocationRegistry.flagResponse(address(orb), 188);

        orbInvocationRegistry.flagResponse(address(orb), 1);
    }

    function test_revertWhen_outsideFlaggingPeriod() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);

        vm.warp(block.timestamp + 100 days);
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrbInvocationRegistry.FlaggingPeriodExpired.selector, address(orb), 1, 100 days, orb.cooldown()
            )
        );
        orbInvocationRegistry.flagResponse(address(orb), 1);

        vm.warp(block.timestamp - (100 days - orb.cooldown()));
        orbInvocationRegistry.flagResponse(address(orb), 1);
    }

    function test_revertWhen_flaggingTwice() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);

        vm.startPrank(user);
        orbInvocationRegistry.flagResponse(address(orb), 1);

        // forge fmt is not very smart
        bytes memory revertData =
            abi.encodeWithSelector(OrbInvocationRegistry.ResponseAlreadyFlagged.selector, address(orb), 1);
        vm.expectRevert(revertData);
        orbInvocationRegistry.flagResponse(address(orb), 1);
    }

    function test_revertWhen_responseToPreviousKeeper() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);

        vm.startPrank(user2);
        orb.purchase{value: 3 ether}(2 ether, 1 ether, 10_00, 10_00, 7 days, 20);
        vm.expectRevert(
            abi.encodeWithSelector(
                OrbInvocationRegistry.FlaggingPeriodExpired.selector,
                address(orb),
                1,
                orb.keeperReceiveTime(),
                block.timestamp
            )
        );
        orbInvocationRegistry.flagResponse(address(orb), 1);

        vm.warp(block.timestamp + orb.cooldown());
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.stopPrank();
        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 2, response);
        vm.prank(user2);
        orbInvocationRegistry.flagResponse(address(orb), 2);
    }

    function test_success() public {
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), keccak256(bytes(cleartext)));
        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);
        vm.prank(user);
        assertEq(orbInvocationRegistry.responseFlagged(address(orb), 1), false);
        assertEq(orbInvocationRegistry.flaggedResponsesCount(address(orb)), 0);
        vm.expectEmit(true, true, true, true);
        emit ResponseFlagging(address(orb), 1, user);
        vm.prank(user);
        orbInvocationRegistry.flagResponse(address(orb), 1);
        assertEq(orbInvocationRegistry.responseFlagged(address(orb), 1), true);
        assertEq(orbInvocationRegistry.flaggedResponsesCount(address(orb)), 1);
    }
}

contract AuthorizeContractTest is OrbInvocationRegistryTestBase {
    event ContractAuthorization(address indexed contractAddress, bool indexed authorized);

    function test_revertOnlyOwner() public {
        assertEq(orbInvocationRegistry.authorizedContracts(address(orb)), false);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        vm.prank(user);
        orbInvocationRegistry.authorizeContract(address(orb), true);

        assertEq(orbInvocationRegistry.authorizedContracts(address(orb)), false);
        orbInvocationRegistry.authorizeContract(address(orb), true);
        assertEq(orbInvocationRegistry.authorizedContracts(address(orb)), true);
    }

    function test_success() public {
        // (not work) auth (and works) deauth (and does not work anymore)
        ExternalCallee externalCallee = new ExternalCallee();
        vm.expectRevert(
            abi.encodeWithSelector(OrbInvocationRegistry.ContractNotAuthorized.selector, address(externalCallee))
        );
        vm.prank(user);
        orbInvocationRegistry.invokeWithCleartextAndCall(
            address(orb),
            "hi three",
            address(externalCallee),
            abi.encodeWithSelector(ExternalCallee.setNumber.selector, 69)
        );

        assertEq(orbInvocationRegistry.invocationCount(address(orb)), 0);
        assertEq(externalCallee.number(), 42);

        assertEq(orbInvocationRegistry.authorizedContracts(address(externalCallee)), false);
        vm.expectEmit(true, true, true, true);
        emit ContractAuthorization(address(externalCallee), true);
        vm.prank(admin);
        orbInvocationRegistry.authorizeContract(address(externalCallee), true);
        assertEq(orbInvocationRegistry.authorizedContracts(address(externalCallee)), true);

        vm.prank(user);
        orbInvocationRegistry.invokeWithCleartextAndCall(
            address(orb),
            "hi three",
            address(externalCallee),
            abi.encodeWithSelector(ExternalCallee.setNumber.selector, 69)
        );

        assertEq(orbInvocationRegistry.invocationCount(address(orb)), 1);
        assertEq(externalCallee.number(), 69);

        assertEq(orbInvocationRegistry.authorizedContracts(address(externalCallee)), true);
        vm.expectEmit(true, true, true, true);
        emit ContractAuthorization(address(externalCallee), false);
        vm.prank(admin);
        orbInvocationRegistry.authorizeContract(address(externalCallee), false);
        assertEq(orbInvocationRegistry.authorizedContracts(address(externalCallee)), false);

        vm.warp(block.timestamp + orb.cooldown());

        vm.expectRevert(
            abi.encodeWithSelector(OrbInvocationRegistry.ContractNotAuthorized.selector, address(externalCallee))
        );
        vm.prank(user);
        orbInvocationRegistry.invokeWithCleartextAndCall(
            address(orb),
            "hi three",
            address(externalCallee),
            abi.encodeWithSelector(ExternalCallee.setNumber.selector, 42)
        );

        assertEq(orbInvocationRegistry.invocationCount(address(orb)), 1);
        assertEq(externalCallee.number(), 69);
    }
}

contract UpgradeTest is OrbInvocationRegistryTestBase {
    function test_upgrade_revertOnlyOwner() public {
        OrbInvocationRegistryTestUpgrade orbInvocationRegistryTestUpgradeImplementation =
            new OrbInvocationRegistryTestUpgrade();
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        vm.prank(user);
        orbInvocationRegistry.upgradeToAndCall(
            address(orbInvocationRegistryTestUpgradeImplementation),
            abi.encodeWithSelector(OrbInvocationRegistryTestUpgrade.initializeTestUpgrade.selector, address(0xBABEFACE))
        );
    }

    function test_upgradeSucceeds() public {
        OrbInvocationRegistryTestUpgrade orbInvocationRegistryTestUpgradeImplementation =
            new OrbInvocationRegistryTestUpgrade();
        bytes4 lateResponseFundSelector = bytes4(keccak256("lateResponseFund()"));

        assertEq(orbInvocationRegistry.version(), 1);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successBefore,) = address(orbInvocationRegistry).call(abi.encodeWithSelector(lateResponseFundSelector));
        assertEq(successBefore, false);

        orbInvocationRegistry.upgradeToAndCall(
            address(orbInvocationRegistryTestUpgradeImplementation),
            abi.encodeWithSelector(OrbInvocationRegistryTestUpgrade.initializeTestUpgrade.selector, address(0xBABEFACE))
        );

        assertEq(
            OrbInvocationRegistryTestUpgrade(address(orbInvocationRegistry)).lateResponseFund(), address(0xBABEFACE)
        );
        assertEq(orbInvocationRegistry.version(), 100);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successAfter,) = address(orbInvocationRegistry).call(abi.encodeWithSelector(lateResponseFundSelector));
        assertEq(successAfter, true);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        OrbInvocationRegistryTestUpgrade(address(orbInvocationRegistry)).initializeTestUpgrade(address(0xCAFEBABE));
    }
}
