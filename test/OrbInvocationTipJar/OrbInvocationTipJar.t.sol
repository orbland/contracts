// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OrbInvocationTipJar} from "../../src/OrbInvocationTipJar.sol";
import {OrbInvocationTipJarTestUpgrade} from "../../src/test-upgrades/OrbInvocationTipJarTestUpgrade.sol";
import {OrbPond} from "../../src/OrbPond.sol";
import {OrbInvocationRegistry} from "../../src/OrbInvocationRegistry.sol";
import {OrbInvocationRegistry} from "../../src/OrbInvocationRegistry.sol";
import {Orb} from "../../src/Orb.sol";
import {Orb} from "../../src/Orb.sol";
import {PaymentSplitter} from "../../src/CustomPaymentSplitter.sol";

/* solhint-disable const-name-snakecase,func-name-mixedcase */
contract OrbTipJarBaseTest is Test {
    OrbInvocationTipJar public orbTipJar;
    OrbInvocationRegistry public orbInvocationRegistry;
    Orb public orb;
    OrbInvocationTipJar public orbTipJarImplementation;
    address public orbAddress;

    // Invocations
    string public constant invocation = "What is the meaning of life?";
    bytes32 public constant invocationHash = keccak256(abi.encodePacked(invocation));
    string private constant _invocation2 = "Who let the dogs out?";
    bytes32 public constant invocation2Hash = keccak256(abi.encodePacked(_invocation2));

    // Addresses
    address public constant keeper = address(0xBABE);
    address public constant tipper = address(0xBEEF);
    address public constant tipper2 = address(0xFACE);
    address public constant orbland = address(0xbada55);

    function setUp() public {
        uint256 startingBalance = 10_000 ether;
        vm.deal(keeper, startingBalance);
        vm.deal(tipper, startingBalance);
        vm.deal(tipper2, startingBalance);

        OrbInvocationRegistry orbInvocationRegistryImplementation = new OrbInvocationRegistry();
        OrbPond orbPondImplementation = new OrbPond();
        Orb orbImplementation = new Orb();
        PaymentSplitter paymentSplitterImplementation = new PaymentSplitter();

        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(
            address(orbInvocationRegistryImplementation),
            abi.encodeWithSelector(OrbInvocationRegistry.initialize.selector)
        );
        orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));

        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondImplementation),
            abi.encodeWithSelector(
                OrbPond.initialize.selector,
                address(orbInvocationRegistry),
                address(paymentSplitterImplementation)
            )
        );
        OrbPond orbPond = OrbPond(address(orbPondProxy));
        orbPond.registerVersion(
            1, address(orbImplementation), abi.encodeWithSelector(Orb.initialize.selector, address(0), "", "", "")
        );

        address creator = address(0xCAFEBABE);
        address[] memory beneficiaryPayees = new address[](1);
        uint256[] memory beneficiaryShares = new uint256[](1);
        beneficiaryPayees[0] = creator;
        beneficiaryShares[0] = 1;
        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "Orb", "ORB", "https://static.orb.land/orb/");
        orb = Orb(orbPond.orbs(0));
        orbAddress = address(orb);

        orb.swearOath(keccak256(abi.encodePacked("oath")), 100, 3600);
        orb.setCleartextMaximumLength(32);
        orb.transferOwnership(creator);

        vm.prank(creator);
        orb.startAuction();
        vm.prank(keeper);
        orb.bid{value: 2 ether}(1 ether, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        orbTipJarImplementation = new OrbInvocationTipJar();
        ERC1967Proxy orbTipJarProxy = new ERC1967Proxy(
            address(orbTipJarImplementation),
            abi.encodeWithSelector(
                OrbInvocationTipJar.initialize.selector,
                orbland,
                5_00 // 5%
            )
        );
        orbTipJar = OrbInvocationTipJar(address(orbTipJarProxy));
    }

    function _invoke(address orbAddress_, bytes32 invocationHash_) internal {
        vm.prank(Orb(orbAddress_).keeper());
        OrbInvocationRegistry(orbInvocationRegistry).invokeWithHash(orbAddress_, invocationHash_);
    }
}

contract InitialStateTest is OrbTipJarBaseTest {
    function test_initialState() public {
        assertEq(orbTipJar.platformAddress(), orbland);
        assertEq(orbTipJar.platformFee(), 500);
        assertEq(orbTipJar.platformFunds(), 0);
    }

    function test_revertsIf_alreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        orbTipJar.initialize(address(0), 1);
    }

    function test_revertsIf_platformAddressInvalid() public {
        vm.expectRevert(OrbInvocationTipJar.PlatformAddressInvalid.selector);
        new ERC1967Proxy(
            address(orbTipJarImplementation),
            abi.encodeWithSelector(
                OrbInvocationTipJar.initialize.selector,
                address(0),
                5_00 // 5%
            )
        );
    }

    function test_revertsIf_platformFeeInvalid() public {
        vm.expectRevert(OrbInvocationTipJar.PlatformFeeInvalid.selector);
        new ERC1967Proxy(
            address(orbTipJarImplementation),
            abi.encodeWithSelector(
                OrbInvocationTipJar.initialize.selector,
                orbland,
                100_01 // 100.01%
            )
        );
    }

    function test_initializerSuccess() public {
        ERC1967Proxy orbInvocationTipJarProxy = new ERC1967Proxy(
            address(orbTipJarImplementation), ""
        );
        OrbInvocationTipJar _orbInvocationTipJar = OrbInvocationTipJar(address(orbInvocationTipJarProxy));
        assertEq(_orbInvocationTipJar.owner(), address(0));
        _orbInvocationTipJar.initialize(orbland, 1);
        assertEq(_orbInvocationTipJar.owner(), address(this));
    }
}

contract SetMinimumTipTest is OrbTipJarBaseTest {
    event MinimumTipUpdate(address indexed orb, uint256 previousMinimumTip, uint256 indexed newMinimumTip);

    function test_revertIf_notOrbKeeper() public {
        vm.expectRevert(OrbInvocationTipJar.NotKeeper.selector);
        vm.prank(tipper);
        orbTipJar.setMinimumTip(orbAddress, 1 ether);
    }

    function test_setMinimumTip() public {
        assertEq(orbTipJar.minimumTips(orbAddress), 0);

        vm.expectEmit();
        emit MinimumTipUpdate(orbAddress, 0, 1 ether);
        vm.prank(keeper);
        orbTipJar.setMinimumTip(orbAddress, 1 ether);

        assertEq(orbTipJar.minimumTips(orbAddress), 1 ether);
    }
}

contract TipInvocationTest is OrbTipJarBaseTest {
    event TipDeposit(address indexed orb, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);

    function test_revertIf_insufficientTip() public {
        vm.prank(keeper);
        orbTipJar.setMinimumTip(orbAddress, 2 ether);

        vm.expectRevert(abi.encodeWithSelector(OrbInvocationTipJar.InsufficientTip.selector, 1 ether, 2 ether));
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
    }

    function test_revertIf_invocationClaimed() public {
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        _invoke(orbAddress, invocationHash);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 1 ether);

        vm.expectRevert(OrbInvocationTipJar.InvocationAlreadyClaimed.selector);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
    }

    function test_tipNewInvocation() public {
        vm.expectEmit();
        emit TipDeposit(orbAddress, invocationHash, address(this), 1 ether);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);

        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1 ether);
        assertEq(orbTipJar.tipperTips(address(this), orbAddress, invocationHash), 1 ether);
    }

    function test_tipExistingInvocation() public {
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);

        vm.expectEmit();
        emit TipDeposit(orbAddress, invocationHash, address(this), 1 ether);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);

        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 2 ether);
        assertEq(orbTipJar.tipperTips(address(this), orbAddress, invocationHash), 2 ether);

        vm.expectEmit();
        emit TipDeposit(orbAddress, invocationHash, tipper, 1.2 ether);
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1.2 ether}(orbAddress, invocationHash);

        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 3.2 ether);
        assertEq(orbTipJar.tipperTips(tipper, orbAddress, invocationHash), 1.2 ether);

        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1.2 ether}(orbAddress, invocationHash);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 4.4 ether);
        assertEq(orbTipJar.tipperTips(tipper, orbAddress, invocationHash), 2.4 ether);
    }
}

contract WithdrawTipTest is OrbTipJarBaseTest {
    event TipWithdrawal(address indexed orb, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);
    event TipsClaim(address indexed orb, bytes32 indexed invocationHash, address indexed invoker, uint256 tipsValue);

    function test_revertIf_notTipped() public {
        vm.expectRevert(OrbInvocationTipJar.TipNotFound.selector);
        orbTipJar.withdrawTip(orbAddress, invocationHash);
    }

    function test_revertIf_invocationClaimed() public {
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        _invoke(orbAddress, invocationHash);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 1 ether);

        vm.expectRevert(OrbInvocationTipJar.InvocationAlreadyClaimed.selector);
        orbTipJar.withdrawTip(orbAddress, invocationHash);
    }

    function test_withdrawTip() public {
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);

        vm.prank(tipper2);
        orbTipJar.tipInvocation{value: 0.5 ether}(orbAddress, invocationHash);

        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1.5 ether);
        assertEq(orbTipJar.tipperTips(tipper, orbAddress, invocationHash), 1 ether);
        assertEq(orbTipJar.tipperTips(tipper2, orbAddress, invocationHash), 0.5 ether);

        uint256 tipper2Balance = tipper2.balance;
        vm.expectEmit();
        emit TipWithdrawal(orbAddress, invocationHash, tipper2, 0.5 ether);
        vm.prank(tipper2);
        orbTipJar.withdrawTip(orbAddress, invocationHash);
        assertEq(tipper2.balance - tipper2Balance, 0.5 ether);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1 ether);
        assertEq(orbTipJar.tipperTips(tipper2, orbAddress, invocationHash), 0);

        uint256 tipperBalance = tipper.balance;
        vm.expectEmit();
        emit TipWithdrawal(orbAddress, invocationHash, tipper, 1 ether);
        vm.prank(tipper);
        orbTipJar.withdrawTip(orbAddress, invocationHash);
        assertEq(tipper.balance - tipperBalance, 1 ether);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 0);
        assertEq(orbTipJar.tipperTips(tipper, orbAddress, invocationHash), 0);
    }

    function test_revertIf_withdrawTipsArraysUneven() public {
        address[] memory orbs = new address[](1);
        orbs[0] = orbAddress;
        bytes32[] memory invocationHashes = new bytes32[](2);
        invocationHashes[0] = invocationHash;
        invocationHashes[1] = invocation2Hash;
        vm.expectRevert(OrbInvocationTipJar.UnevenArrayLengths.selector);
        vm.prank(tipper);
        orbTipJar.withdrawTips(orbs, invocationHashes);
    }

    function test_withdrawTips() public {
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 0.5 ether}(orbAddress, invocation2Hash);

        uint256 tipperBalance = tipper.balance;
        address[] memory orbs = new address[](2);
        orbs[0] = orbAddress;
        orbs[1] = orbAddress;
        bytes32[] memory invocationHashes = new bytes32[](2);
        invocationHashes[0] = invocationHash;
        invocationHashes[1] = invocation2Hash;
        vm.expectEmit();
        emit TipWithdrawal(orbAddress, invocationHash, tipper, 1 ether);
        vm.expectEmit();
        emit TipWithdrawal(orbAddress, invocation2Hash, tipper, 0.5 ether);
        vm.prank(tipper);
        orbTipJar.withdrawTips(orbs, invocationHashes);

        assertEq(tipper.balance - tipperBalance, 1.5 ether);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 0);
        assertEq(orbTipJar.tipperTips(tipper, orbAddress, invocationHash), 0);
    }

    function test_revertIf_noPlatformFunds() public {
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        _invoke(orbAddress, invocationHash);

        assertEq(orbTipJar.platformFunds(), 0);
        vm.expectRevert(OrbInvocationTipJar.NoFundsAvailable.selector);
        orbTipJar.withdrawPlatformFunds();
    }

    function test_withdrawPlatformFunds() public {
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        _invoke(orbAddress, invocationHash);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 1 ether);

        uint256 orblandBalance = orbland.balance;
        assertEq(orbTipJar.platformFunds(), 0.05 ether);
        vm.expectEmit();
        emit TipsClaim(address(0), bytes32(0), orbland, 0.05 ether);
        orbTipJar.withdrawPlatformFunds();
        assertEq(orbTipJar.platformFunds(), 0);
        assertEq(orbland.balance - orblandBalance, 0.05 ether);
    }
}

contract ClaimTipsTest is OrbTipJarBaseTest {
    event TipsClaim(address indexed orb, bytes32 indexed invocationHash, address indexed invoker, uint256 tipsValue);
    event Invocation(
        address indexed orb,
        uint256 indexed invocationId,
        address indexed invoker,
        uint256 timestamp,
        bytes32 contentHash
    );
    event CleartextRecording(address indexed orb, uint256 indexed invocationId, string cleartext);
    event ContractAuthorization(address indexed contractAddress, bool indexed authorized);

    function test_revertIf_invocationNotInvoked() public {
        vm.expectRevert(OrbInvocationTipJar.InvocationNotInvoked.selector);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 0);

        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        vm.expectRevert(OrbInvocationTipJar.InvocationNotInvoked.selector);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 0);
    }

    function test_revertIf_invocationClaimed() public {
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        _invoke(orbAddress, invocationHash);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 1 ether);

        vm.expectRevert(OrbInvocationTipJar.InvocationAlreadyClaimed.selector);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 0);
    }

    function test_revertIf_insufficientTips() public {
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        _invoke(orbAddress, invocationHash);
        vm.expectRevert(abi.encodeWithSelector(OrbInvocationTipJar.InsufficientTips.selector, 1.1 ether, 1 ether));
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 1.1 ether);

        vm.prank(tipper);
        orbTipJar.withdrawTip(orbAddress, invocationHash);
        vm.expectRevert(abi.encodeWithSelector(OrbInvocationTipJar.InsufficientTips.selector, 0.1 ether, 0));
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 0.1 ether);
    }

    function test_claimTips() public {
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        _invoke(orbAddress, invocationHash);

        uint256 keeperBalance = keeper.balance;
        uint256 orblandBalance = orbland.balance;
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1 ether);
        assertEq(orbTipJar.platformFunds(), 0);
        assertEq(orbTipJar.claimedInvocations(orbAddress, invocationHash), 0);

        vm.expectEmit();
        emit TipsClaim(orbAddress, invocationHash, keeper, 0.95 ether);
        vm.prank(tipper2); // anyone can do this
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 1 ether);

        assertEq(keeper.balance - keeperBalance, 0.95 ether);
        assertEq(orbland.balance - orblandBalance, 0 ether);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1 ether);
        assertEq(orbTipJar.platformFunds(), 0.05 ether);
        assertEq(orbTipJar.claimedInvocations(orbAddress, invocationHash), 1);
    }

    function test_claimTipsWithoutMinimumTipValue() public {
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);
        _invoke(orbAddress, invocationHash);

        vm.prank(tipper);
        orbTipJar.withdrawTip(orbAddress, invocationHash);

        vm.expectEmit();
        emit TipsClaim(orbAddress, invocationHash, keeper, 0);
        // this is intentional: not providing minimum value might mean claiming nothing
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 0);
        assertEq(orbTipJar.claimedInvocations(orbAddress, invocationHash), 1);
    }

    function test_invokeAndClaim() public {
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1 ether}(orbAddress, invocationHash);

        bytes memory claimCalldata =
            abi.encodeWithSelector(OrbInvocationTipJar.claimTipsForInvocation.selector, orbAddress, 1, 1 ether);

        // expect revert if not authorized
        vm.expectRevert(
            abi.encodeWithSelector(OrbInvocationRegistry.ContractNotAuthorized.selector, address(orbTipJar))
        );
        vm.prank(keeper);
        OrbInvocationRegistry(orbInvocationRegistry).invokeWithHashAndCall(
            orbAddress, invocationHash, address(orbTipJar), claimCalldata
        );

        vm.expectEmit();
        emit ContractAuthorization(address(orbTipJar), true);
        orbInvocationRegistry.authorizeContract(address(orbTipJar), true);

        uint256 keeperBalance = keeper.balance;
        uint256 orblandBalance = orbland.balance;
        assertEq(orbInvocationRegistry.invocationCount(orbAddress), 0);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1 ether);
        assertEq(orbTipJar.platformFunds(), 0);
        assertEq(orbTipJar.claimedInvocations(orbAddress, invocationHash), 0);

        vm.expectEmit();
        emit Invocation(orbAddress, 1, keeper, block.timestamp, invocationHash);
        vm.expectEmit();
        emit CleartextRecording(orbAddress, 1, invocation);
        vm.expectEmit();
        emit TipsClaim(orbAddress, invocationHash, keeper, 0.95 ether);
        vm.prank(keeper);
        OrbInvocationRegistry(orbInvocationRegistry).invokeWithCleartextAndCall(
            orbAddress, invocation, address(orbTipJar), claimCalldata
        );

        assertEq(keeper.balance - keeperBalance, 0.95 ether);
        assertEq(orbland.balance - orblandBalance, 0 ether);
        assertEq(orbInvocationRegistry.invocationCount(orbAddress), 1);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1 ether);
        assertEq(orbTipJar.platformFunds(), 0.05 ether);
        assertEq(orbTipJar.claimedInvocations(orbAddress, invocationHash), 1);
    }
}

contract UpgradeTest is OrbTipJarBaseTest {
    function test_upgrade_revertOnlyOwner() public {
        OrbInvocationTipJarTestUpgrade orbInvocationTipJarTestUpgradeImplementation =
            new OrbInvocationTipJarTestUpgrade();
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(tipper);
        orbTipJar.upgradeToAndCall(
            address(orbInvocationTipJarTestUpgradeImplementation),
            abi.encodeWithSelector(OrbInvocationTipJarTestUpgrade.initializeTestUpgrade.selector, 0.05 ether)
        );
    }

    function test_upgradeSucceeds() public {
        OrbInvocationTipJarTestUpgrade orbInvocationTipJarTestUpgradeImplementation =
            new OrbInvocationTipJarTestUpgrade();
        bytes4 tipModuloSelector = bytes4(keccak256("tipModulo()"));

        assertEq(orbTipJar.version(), 1);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successBefore,) = address(orbTipJar).call(abi.encodeWithSelector(tipModuloSelector));
        assertEq(successBefore, false);

        orbTipJar.upgradeToAndCall(
            address(orbInvocationTipJarTestUpgradeImplementation),
            abi.encodeWithSelector(OrbInvocationTipJarTestUpgrade.initializeTestUpgrade.selector, 0.05 ether)
        );

        assertEq(OrbInvocationTipJarTestUpgrade(address(orbTipJar)).tipModulo(), 0.05 ether);
        assertEq(orbTipJar.version(), 100);
        // solhint-disable-next-line avoid-low-level-calls
        (bool successAfter,) = address(orbTipJar).call(abi.encodeWithSelector(tipModuloSelector));
        assertEq(successAfter, true);

        vm.expectRevert("Initializable: contract is already initialized");
        OrbInvocationTipJarTestUpgrade(address(orbTipJar)).initializeTestUpgrade(0.05 ether);
    }
}
