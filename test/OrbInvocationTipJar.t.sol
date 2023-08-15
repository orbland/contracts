// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OrbInvocationTipJar} from "../src/OrbInvocationTipJar.sol";
import {OrbPond} from "../src/OrbPond.sol";
import {OrbInvocationRegistry} from "../src/OrbInvocationRegistry.sol";
import {IOrbInvocationRegistry} from "../src/IOrbInvocationRegistry.sol";
import {Orb} from "../src/Orb.sol";
import {IOrb} from "../src/IOrb.sol";
import {PaymentSplitter} from "../src/CustomPaymentSplitter.sol";

/* solhint-disable const-name-snakecase,func-name-mixedcase */
contract OrbTipJarBaseTest is Test {
    // Tipping contract
    OrbInvocationTipJar public orbTipJar;
    OrbInvocationRegistry public orbInvocationRegistry;
    Orb public orb;
    address public orbAddress;

    // Invocations
    string public constant invocation = "What is the meaning of life?";
    bytes32 public constant invocationHash = keccak256(abi.encodePacked(invocation));
    string public constant invocation2 = "Who let the dogs out?";
    bytes32 public constant invocation2Hash = keccak256(abi.encodePacked(invocation2));

    // Addresses
    address public constant keeper = address(0xBABE);
    address public constant tipper = address(0xBEEF);
    address public constant tipper2 = address(0xFACE);

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

        orbTipJar = new OrbInvocationTipJar();
    }

    function invoke(address orbAddress_, string memory invocation_) internal {
        vm.prank(IOrb(orbAddress_).keeper());
        IOrbInvocationRegistry(orbInvocationRegistry).invokeWithCleartext(orbAddress_, invocation_);
    }
}

contract InitialStateTest is OrbTipJarBaseTest {
    function test_initialState() public {}
}

contract SuggestInvocationTest is OrbTipJarBaseTest {
    event InvocationSuggestion(
        address indexed orb, bytes32 indexed invocationHash, address indexed suggester, string invocationCleartext
    );

    function test_revertIf_alreadySuggested() public {
        // Suggest invocation
        // testSuggestInvocation();

        // Suggest the same invocation again
        vm.expectRevert(OrbInvocationTipJar.InvocationAlreadySuggested.selector);
        orbTipJar.suggestInvocation(orbAddress, invocation);
    }

    function test_revertIf_cleartextTooLong() public {}

    function test_suggestWithoutTip() public {
        // Suggest invocation
        vm.expectEmit();
        emit InvocationSuggestion(orbAddress, invocationHash, address(this), invocation);
        orbTipJar.suggestInvocation(orbAddress, invocation);

        assertEq(orbTipJar.suggestedInvocations(invocationHash), invocation);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 0);
        assertEq(orbTipJar.tipperTips(address(this), orbAddress, invocationHash), 0);
    }
}

contract TipInvocationTest is OrbTipJarBaseTest {
    event InvocationSuggestion(
        address indexed orb, bytes32 indexed invocationHash, address indexed suggester, string invocationCleartext
    );
    event TipDeposit(address indexed orb, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);

    function test_revertIf_insufficientTip() public {}
    function test_revertIf_invocationNotSuggested() public {}
    function test_revertIf_invocationClaimed() public {}

    function test_suggestWithTip() public {
        // Suggest invocation with tip
        vm.expectEmit();
        emit InvocationSuggestion(orbAddress, invocationHash, address(this), invocation);
        vm.expectEmit();
        emit TipDeposit(orbAddress, invocationHash, address(this), 1 ether);
        orbTipJar.suggestInvocation{value: 1 ether}(orbAddress, invocation);

        assertEq(orbTipJar.suggestedInvocations(invocationHash), invocation);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1 ether);
        assertEq(orbTipJar.tipperTips(address(this), orbAddress, invocationHash), 1 ether);
    }

    function test_tipExistingInvocation() public {
        // Suggest invocation without tip
        orbTipJar.suggestInvocation(orbAddress, invocation);

        // Tip invocation
        vm.expectEmit();
        emit TipDeposit(orbAddress, invocationHash, address(this), 1.1 ether);
        orbTipJar.tipInvocation{value: 1.1 ether}(orbAddress, invocationHash);

        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1.1 ether);
        assertEq(orbTipJar.tipperTips(address(this), orbAddress, invocationHash), 1.1 ether);

        // Tip invocation again
        vm.prank(tipper);
        orbTipJar.tipInvocation{value: 1.2 ether}(orbAddress, invocationHash);

        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 2.3 ether);
        assertEq(orbTipJar.tipperTips(tipper, orbAddress, invocationHash), 1.2 ether);
    }
}

contract WithdrawTipTest is OrbTipJarBaseTest {
    function test_revertIf_notTipped() public {}
    function test_revertIf_invocationClaimed() public {}

    function test_withdrawTip() public {
        // Suggest invocation with tip
        vm.prank(tipper);
        orbTipJar.suggestInvocation{value: 1.1 ether}(orbAddress, invocation);

        // Tip invocation from a different account
        vm.startPrank(tipper2);
        orbTipJar.tipInvocation{value: 0.1 ether}(orbAddress, invocationHash);

        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1.2 ether);
        assertEq(orbTipJar.tipperTips(address(tipper), orbAddress, invocationHash), 1.1 ether);
        assertEq(orbTipJar.tipperTips(address(tipper2), orbAddress, invocationHash), 0.1 ether);

        uint256 balanceBeforeWithdraw = address(tipper2).balance;

        // Withdraw tip from the second tipper
        orbTipJar.withdrawTip(orbAddress, invocationHash);

        uint256 balanceAfterWithdraw = address(tipper2).balance;

        assertEq(balanceAfterWithdraw - balanceBeforeWithdraw, 0.1 ether);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 1.1 ether);
        assertEq(orbTipJar.tipperTips(address(tipper2), orbAddress, invocationHash), 0);

        vm.stopPrank();

        // Withdraw tip from the first tipper
        vm.startPrank(tipper);

        balanceBeforeWithdraw = address(tipper).balance;

        orbTipJar.withdrawTip(orbAddress, invocationHash);

        balanceAfterWithdraw = address(tipper).balance;

        assertEq(balanceAfterWithdraw - balanceBeforeWithdraw, 1.1 ether);
        assertEq(orbTipJar.totalTips(orbAddress, invocationHash), 0);
        assertEq(orbTipJar.tipperTips(address(tipper), orbAddress, invocationHash), 0);

        vm.stopPrank();
    }

    function test_withdrawTips() public {}
}

contract ClaimTipsTest is OrbTipJarBaseTest {
    event TipsClaim(address indexed orb, bytes32 indexed invocationHash, address indexed invoker, uint256 tipsValue);

    function test_revertIf_invocationClaimed() public {}
    function test_revertIf_insufficientTips() public {}

    function test_claimTips() public {
        // Suggest invocation with tip
        vm.startPrank(tipper);

        orbTipJar.suggestInvocation{value: 1.1 ether}(orbAddress, invocation);

        // Claim tips (fails because invocation is not suggested yet)
        vm.expectRevert(OrbInvocationTipJar.InvocationNotFound.selector);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 1.1 ether);

        // Suggest invocation
        invoke(orbAddress, invocation);

        uint256 balanceBeforeClaim = address(keeper).balance;

        // Claim tips (fails because `minimumTipValue` is set too high)
        vm.expectRevert(OrbInvocationTipJar.InsufficientTips.selector);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 1.2 ether);

        // Claim tips
        vm.expectEmit();
        emit TipsClaim(orbAddress, invocationHash, keeper, 1.1 ether);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 1.1 ether);

        uint256 balanceAfterClaim = address(keeper).balance;

        assertEq(balanceAfterClaim - balanceBeforeClaim, 1.1 ether);

        // Claim tips again (fails because tips are already claimed)
        vm.expectRevert(OrbInvocationTipJar.InvocationAlreadyClaimed.selector);
        orbTipJar.claimTipsForInvocation(orbAddress, 1, 0);
    }

    function test_claimTipsWithoutMinimumTipValue() public {}
}

contract SetMinimumTipTest is OrbTipJarBaseTest {
    function test_revertIf_notOrbKeeper() public {}
    function test_setMinimumTip() public {}
}
