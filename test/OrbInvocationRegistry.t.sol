// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* solhint-disable no-console */
import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OrbPond} from "src/OrbPond.sol";
import {OrbInvocationRegistry} from "src/OrbInvocationRegistry.sol";
import {OrbInvocationRegistryV2} from "src/OrbInvocationRegistryV2.sol";
import {Orb} from "src/Orb.sol";
import {IOrb} from "src/IOrb.sol";
import {IOrbInvocationRegistry} from "src/IOrbInvocationRegistry.sol";

/* solhint-disable func-name-mixedcase,private-vars-leading-underscore */
contract OrbInvocationRegistryTestBase is Test {
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
        beneficiary = address(0xC0FFEE);
        creator = address(0xCAFEBABE);
        startingBalance = 10_000 ether;
        vm.deal(user, startingBalance);
        vm.deal(user2, startingBalance);

        orbInvocationRegistryImplementation = new OrbInvocationRegistry();
        orbPondImplementation = new OrbPond();
        orbImplementation = new Orb();

        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(
            address(orbInvocationRegistryImplementation),
            abi.encodeWithSelector(OrbInvocationRegistry.initialize.selector)
        );
        orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));

        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondImplementation),
            abi.encodeWithSelector(OrbPond.initialize.selector, address(orbInvocationRegistry))
        );
        orbPond = OrbPond(address(orbPondProxy));
        bytes memory orbPondV1InitializeCalldata =
            abi.encodeWithSelector(Orb.initialize.selector, address(0), "", "", "");
        orbPond.registerVersion(1, address(orbImplementation), orbPondV1InitializeCalldata);

        orbPond.createOrb(beneficiary, "Orb", "ORB", "https://static.orb.land/orb/");

        orb = Orb(orbPond.orbs(0));

        orb.swearOath(
            keccak256(abi.encodePacked("test oath")), // oathHash
            100, // 1_700_000_000 // honoredUntil
            3600 // responsePeriod
        );
        orb.setAuctionParameters(0.1 ether, 0.1 ether, 1 days, 6 hours, 5 minutes);
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
        vm.expectRevert("Initializable: contract is already initialized");
        orbInvocationRegistry.initialize();
    }

    function test_initializerSuccess() public {
        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(
            address(orbInvocationRegistryImplementation), ""
        );
        OrbInvocationRegistry _orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));
        assertEq(_orbInvocationRegistry.owner(), address(0));
        _orbInvocationRegistry.initialize();
        assertEq(_orbInvocationRegistry.owner(), address(this));
    }
}

contract SupportsInterfaceTest is OrbInvocationRegistryTestBase {
    // Test that the initial state is correct
    function test_supportsInterface() public view {
        // console.logBytes4(type(IOrbInvocationRegistry).interfaceId);
        assert(orbInvocationRegistry.supportsInterface(0x01ffc9a7)); // ERC165 Interface ID for ERC165
        assert(orbInvocationRegistry.supportsInterface(0xd4f5d1b6)); // ERC165 Interface ID for IOrbInvocationRegistry
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
        uint256 max = orb.cleartextMaximumLength();
        string memory text =
            "asfsafsfsafsafasdfasfdsakfjdsakfjasdlkfajsdlfsdlfkasdfjdjasfhasdljhfdaslkfjsda;kfjasdklfjasdklfjasd;ladlkfjasdfad;flksadjf;lkasdjf;lsadsdlsdlkfjas;dlkfjas;dlkfjsad;lkfjsad;lda;lkfj;kasjf;klsadjf;lsadsdlkfjasd;lkfjsad;lfkajsd;flkasdjf;lsdkfjas;lfkasdflkasdf;laskfj;asldkfjsad;lfs;lf;flksajf;lk"; // solhint-disable-line
        uint256 length = bytes(text).length;
        vm.expectRevert(abi.encodeWithSelector(IOrbInvocationRegistry.CleartextTooLong.selector, length, max));
        orbInvocationRegistry.invokeWithCleartext(address(orb), text);
    }

    function test_callsInvokeWithHashCorrectly() public {
        string memory text = "fjasdklfjasdklfjasdasdffakfjsad;lfs;lf;flksajf;lk";
        vm.expectEmit(true, true, true, true);
        emit Invocation(address(orb), 1, user, block.timestamp, keccak256(abi.encodePacked(text)));
        vm.expectEmit(true, true, true, true);
        emit CleartextRecording(address(orb), 1, text);
        vm.prank(user);
        orbInvocationRegistry.invokeWithCleartext(address(orb), text);
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
        bytes32 hash = "asdfsaf";
        vm.prank(user2);
        vm.expectRevert(IOrbInvocationRegistry.NotKeeper.selector);
        orbInvocationRegistry.invokeWithHash(address(orb), hash);

        vm.expectEmit(true, true, true, true);
        emit Invocation(address(orb), 1, user, block.timestamp, hash);
        vm.prank(user);
        orbInvocationRegistry.invokeWithHash(address(orb), hash);
    }

    function test_revertWhen_KeeperInsolvent() public {
        bytes32 hash = "asdfsaf";
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(IOrbInvocationRegistry.KeeperInsolvent.selector);
        orbInvocationRegistry.invokeWithHash(address(orb), hash);
    }

    function test_revertWhen_CooldownIncomplete() public {
        bytes32 hash = "asdfsaf";
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
                IOrbInvocationRegistry.CooldownIncomplete.selector,
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
        bytes32 hash = "asdfsaf";
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

        vm.expectRevert(IOrbInvocationRegistry.NotCreator.selector);
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
        vm.expectRevert(abi.encodeWithSelector(IOrbInvocationRegistry.InvocationNotFound.selector, address(orb), 2));
        orbInvocationRegistry.respond(address(orb), 2, response);

        vm.prank(creator);
        orbInvocationRegistry.respond(address(orb), 1, response);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IOrbInvocationRegistry.InvocationNotFound.selector, address(orb), 0));
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
        vm.expectRevert(abi.encodeWithSelector(IOrbInvocationRegistry.ResponseExists.selector, address(orb), 1));
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
        vm.expectRevert(IOrbInvocationRegistry.NotKeeper.selector);
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
        vm.expectRevert(IOrbInvocationRegistry.KeeperInsolvent.selector);
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
        vm.expectRevert(abi.encodeWithSelector(IOrbInvocationRegistry.ResponseNotFound.selector, address(orb), 188));
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
                IOrbInvocationRegistry.FlaggingPeriodExpired.selector, address(orb), 1, 100 days, orb.cooldown()
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
            abi.encodeWithSelector(IOrbInvocationRegistry.ResponseAlreadyFlagged.selector, address(orb), 1);
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
        orb.purchase{value: 3 ether}(2 ether, 1 ether, 10_00, 10_00, 7 days, 280);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrbInvocationRegistry.FlaggingPeriodExpired.selector,
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

contract UpgradeTest is OrbInvocationRegistryTestBase {
    function test_upgrade_revertOnlyOwner() public {
        OrbInvocationRegistryV2 orbInvocationRegistryV2Implementation = new OrbInvocationRegistryV2();
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        orbInvocationRegistry.upgradeToAndCall(
            address(orbInvocationRegistryV2Implementation),
            abi.encodeWithSelector(OrbInvocationRegistryV2.initializeV2.selector, address(0xBABEFACE))
        );
    }

    function test_upgradeSucceeds() public {
        OrbInvocationRegistryV2 orbInvocationRegistryV2Implementation = new OrbInvocationRegistryV2();
        bytes4 lateResponseFundSelector = bytes4(keccak256("lateResponseFund()"));

        assertEq(orbInvocationRegistry.version(), 1);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successBefore,) = address(orbInvocationRegistry).call(abi.encodeWithSelector(lateResponseFundSelector));
        assertEq(successBefore, false);

        orbInvocationRegistry.upgradeToAndCall(
            address(orbInvocationRegistryV2Implementation),
            abi.encodeWithSelector(OrbInvocationRegistryV2.initializeV2.selector, address(0xBABEFACE))
        );

        assertEq(OrbInvocationRegistryV2(address(orbInvocationRegistry)).lateResponseFund(), address(0xBABEFACE));
        assertEq(orbInvocationRegistry.version(), 2);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successAfter,) = address(orbInvocationRegistry).call(abi.encodeWithSelector(lateResponseFundSelector));
        assertEq(successAfter, true);
    }
}
