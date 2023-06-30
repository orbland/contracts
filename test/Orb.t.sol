// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/* solhint-disable no-console */
import {console} from "../lib/forge-std/src/console.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OrbHarness} from "./harness/OrbHarness.sol";
import {OrbPond} from "src/OrbPond.sol";
import {OrbInvocationRegistry} from "src/OrbInvocationRegistry.sol";
import {Orb} from "src/Orb.sol";
import {IOrb} from "src/IOrb.sol";

/* solhint-disable func-name-mixedcase,private-vars-leading-underscore */
contract OrbTestBase is Test {
    OrbInvocationRegistry internal orbInvocationRegistryImplementation;
    OrbInvocationRegistry internal orbInvocationRegistry;

    OrbPond internal orbPondImplementation;
    OrbPond internal orbPond;

    OrbHarness internal orbImplementation;
    OrbHarness internal orb;

    address internal user;
    address internal user2;
    address internal beneficiary;
    address internal owner;

    uint256 internal startingBalance;

    event Creation();

    function setUp() public {
        user = address(0xBEEF);
        user2 = address(0xFEEEEEB);
        beneficiary = address(0xC0FFEE);
        startingBalance = 10_000 ether;
        vm.deal(user, startingBalance);
        vm.deal(user2, startingBalance);

        orbInvocationRegistryImplementation = new OrbInvocationRegistry();
        orbPondImplementation = new OrbPond();
        orbImplementation = new OrbHarness();

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

        vm.expectEmit(true, true, true, true);
        emit Creation();
        orbPond.createOrb(beneficiary, "Orb", "ORB", "https://static.orb.land/orb/");

        orb = OrbHarness(orbPond.orbs(0));

        orb.swearOath(
            keccak256(abi.encodePacked("test oath")), // oathHash
            100, // 1_700_000_000 // honoredUntil
            3600 // responsePeriod
        );
        orb.setAuctionParameters(0.1 ether, 0.1 ether, 1 days, 6 hours, 5 minutes);
        owner = orb.owner();
    }

    function prankAndBid(address bidder, uint256 bidAmount) internal {
        uint256 finalAmount = fundsRequiredToBidOneYear(bidAmount);
        vm.deal(bidder, startingBalance + finalAmount);
        vm.prank(bidder);
        orb.bid{value: finalAmount}(bidAmount, bidAmount);
    }

    function makeKeeperAndWarp(address newKeeper, uint256 bid) public {
        orb.startAuction();
        prankAndBid(newKeeper, bid);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);
    }

    function fundsRequiredToBidOneYear(uint256 amount) public view returns (uint256) {
        return amount + (amount * orb.keeperTaxNumerator()) / orb.feeDenominator();
    }

    function effectiveFundsOf(address user_) public view returns (uint256) {
        uint256 unadjustedFunds = orb.fundsOf(user_);
        address keeper = orb.keeper();

        if (user_ == orb.owner()) {
            return unadjustedFunds;
        }

        if (user_ == beneficiary || user_ == keeper) {
            uint256 owedFunds = orb.workaround_owedSinceLastSettlement();
            uint256 keeperFunds = orb.fundsOf(keeper);
            uint256 transferableToBeneficiary = keeperFunds <= owedFunds ? keeperFunds : owedFunds;

            if (user_ == beneficiary) {
                return unadjustedFunds + transferableToBeneficiary;
            }
            if (user_ == keeper) {
                return unadjustedFunds - transferableToBeneficiary;
            }
        }

        return unadjustedFunds;
    }
}

contract InitialStateTest is OrbTestBase {
    // Test that the initial state is correct
    function test_initialState() public {
        assertEq(address(orb), orb.keeper());
        assertFalse(orb.workaround_auctionRunning());
        assertEq(orb.owner(), address(this));
        assertEq(orb.beneficiary(), address(0xC0FFEE));
        assertEq(orb.honoredUntil(), 100); // 1_700_000_000
        assertEq(orb.responsePeriod(), 3600);

        assertEq(orb.name(), "Orb");
        assertEq(orb.symbol(), "ORB");

        assertEq(orb.workaround_tokenURI(), "https://static.orb.land/orb/");

        assertEq(orb.cleartextMaximumLength(), 280);

        assertEq(orb.price(), 0);
        assertEq(orb.keeperTaxNumerator(), 10_00);
        assertEq(orb.royaltyNumerator(), 10_00);
        assertEq(orb.lastInvocationTime(), 0);

        assertEq(orb.auctionStartingPrice(), 0.1 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.1 ether);
        assertEq(orb.auctionMinimumDuration(), 1 days);
        assertEq(orb.auctionKeeperMinimumDuration(), 6 hours);
        assertEq(orb.auctionBidExtension(), 5 minutes);

        assertEq(orb.auctionBeneficiary(), address(0));
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.leadingBid(), 0);

        assertEq(orb.lastSettlementTime(), 0);
        assertEq(orb.keeperReceiveTime(), 0);
    }

    function test_constants() public {
        assertEq(orb.feeDenominator(), 100_00);
        assertEq(orb.keeperTaxPeriod(), 365 days);

        assertEq(orb.workaround_maximumPrice(), 2 ** 128);
        assertEq(orb.workaround_cooldownMaximumDuration(), 3650 days);
    }
}

contract SupportsInterfaceTest is OrbTestBase {
    // Test that the initial state is correct
    function test_supportsInterface() public view {
        // console.logBytes4(type(IOrb).interfaceId);
        assert(orb.supportsInterface(0x01ffc9a7)); // ERC165 Interface ID for ERC165
        assert(orb.supportsInterface(0x80ac58cd)); // ERC165 Interface ID for ERC721
        assert(orb.supportsInterface(0x5b5e139f)); // ERC165 Interface ID for ERC721Metadata
        assert(orb.supportsInterface(0xfa7ffdd1)); // ERC165 Interface ID for Orb
    }
}

contract ERC721Test is OrbTestBase {
    // tokenURI

    function test_erc721BalanceOf() public {
        assertEq(orb.balanceOf(address(orb)), 1);
        assertEq(orb.balanceOf(user), 0);
        makeKeeperAndWarp(user, 1 ether);
        assertEq(orb.balanceOf(address(orb)), 0);
        assertEq(orb.balanceOf(user), 1);
    }

    function test_erc721OwnerOf() public {
        assertEq(orb.ownerOf(1), address(orb));
        makeKeeperAndWarp(user, 1 ether);
        assertEq(orb.ownerOf(1), user);
    }

    function test_erc721TokenURI() public {
        assertEq(orb.tokenURI(1), "https://static.orb.land/orb/");
        assertEq(orb.tokenURI(69), "https://static.orb.land/orb/");
    }

    function test_erc721FunctionsRevert() public {
        vm.expectRevert(IOrb.NotSupported.selector);
        orb.approve(address(0), 1);
        vm.expectRevert(IOrb.NotSupported.selector);
        orb.setApprovalForAll(address(0), true);
        vm.expectRevert(IOrb.NotSupported.selector);
        orb.getApproved(0);
        vm.expectRevert(IOrb.NotSupported.selector);
        orb.isApprovedForAll(address(0), owner);
    }

    function test_transfersRevert() public {
        address newOwner = address(0xBEEF);
        uint256 tokenId = 1;
        vm.expectRevert(IOrb.NotSupported.selector);
        orb.transferFrom(address(this), newOwner, tokenId);
        vm.expectRevert(IOrb.NotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, tokenId);
        vm.expectRevert(IOrb.NotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, tokenId, bytes(""));
    }
}

contract SwearOathTest is OrbTestBase {
    event OathSwearing(bytes32 indexed oathHash, uint256 indexed honoredUntil, uint256 indexed responsePeriod);

    function test_swearOathOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100, 3600);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100, 3600);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(IOrb.CreatorDoesNotControlOrb.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100, 3600);
    }

    function test_swearOathCorrectly() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        // keccak hash of "test oath"
        emit OathSwearing(0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc, 100, 3600);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100, 3600);
        assertEq(orb.honoredUntil(), 100);
        assertEq(orb.responsePeriod(), 3600);
    }
}

contract ExtendHonoredUntilTest is OrbTestBase {
    event HonoredUntilUpdate(uint256 previousHonoredUntil, uint256 indexed newHonoredUntil);

    function test_extendHonoredUntilOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.extendHonoredUntil(101);

        makeKeeperAndWarp(user, 1 ether);
        vm.prank(owner);
        orb.extendHonoredUntil(101);
    }

    function test_extendHonoredUntilNotDecrease() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(owner);
        vm.expectRevert(IOrb.HonoredUntilNotDecreasable.selector);
        orb.extendHonoredUntil(99);
    }

    function test_extendHonoredUntilCorrectly() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit HonoredUntilUpdate(100, 101);
        orb.extendHonoredUntil(101);
    }
}

contract SettingTokenURITest is OrbTestBase {
    function test_tokenURIrevertsIfUser() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setTokenURI("https://static.orb.land/new/");
    }

    function test_tokenURISetsCorrectState() public {
        vm.prank(owner);
        orb.setTokenURI("https://static.orb.land/new/");
        assertEq(orb.workaround_tokenURI(), "https://static.orb.land/new/");
    }
}

contract SettingAuctionParametersTest is OrbTestBase {
    event AuctionParametersUpdate(
        uint256 previousStartingPrice,
        uint256 indexed newStartingPrice,
        uint256 previousMinimumBidStep,
        uint256 indexed newMinimumBidStep,
        uint256 previousMinimumDuration,
        uint256 indexed newMinimumDuration,
        uint256 previousKeeperMinimumDuration,
        uint256 newKeeperMinimumDuration,
        uint256 previousBidExtension,
        uint256 newBidExtension
    );

    function test_setAuctionParametersOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(IOrb.CreatorDoesNotControlOrb.selector);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);
    }

    function test_revertIfAuctionDurationZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InvalidAuctionDuration.selector, 0));
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 0, 1 days, 10 minutes);
    }

    function test_allowKeeperAuctionDurationZero() public {
        vm.prank(owner);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 0, 10 minutes);
    }

    function test_boundMinBidStepToAbove0() public {
        assertEq(orb.auctionStartingPrice(), 0.1 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.1 ether);
        vm.prank(owner);
        orb.setAuctionParameters(0, 0, 1 days, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0);
        assertEq(orb.auctionMinimumBidStep(), 1);

        vm.prank(owner);
        orb.setAuctionParameters(0, 2, 1 days, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0);
        assertEq(orb.auctionMinimumBidStep(), 2);
    }

    function test_setAuctionParametersSucceedsCorrectly() public {
        assertEq(orb.auctionStartingPrice(), 0.1 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.1 ether);
        assertEq(orb.auctionMinimumDuration(), 1 days);
        assertEq(orb.auctionKeeperMinimumDuration(), 6 hours);
        assertEq(orb.auctionBidExtension(), 5 minutes);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AuctionParametersUpdate(
            0.1 ether, 0.2 ether, 0.1 ether, 0.2 ether, 1 days, 2 days, 6 hours, 1 days, 5 minutes, 10 minutes
        );
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0.2 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.2 ether);
        assertEq(orb.auctionMinimumDuration(), 2 days);
        assertEq(orb.auctionKeeperMinimumDuration(), 1 days);
        assertEq(orb.auctionBidExtension(), 10 minutes);
    }
}

contract SettingFeesTest is OrbTestBase {
    event FeesUpdate(
        uint256 previousKeeperTaxNumerator,
        uint256 indexed newKeeperTaxNumerator,
        uint256 previousRoyaltyNumerator,
        uint256 indexed newRoyaltyNumerator
    );

    function test_setFeesOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setFees(100_00, 100_00);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.setFees(100_00, 100_00);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(IOrb.CreatorDoesNotControlOrb.selector);
        orb.setFees(100_00, 100_00);
    }

    function test_revertIfRoyaltyNumeratorExceedsDenominator() public {
        uint256 largeNumerator = orb.feeDenominator() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrb.RoyaltyNumeratorExceedsDenominator.selector, largeNumerator, orb.feeDenominator()
            )
        );
        vm.prank(owner);
        orb.setFees(largeNumerator, largeNumerator);

        vm.prank(owner);
        orb.setFees(largeNumerator, orb.feeDenominator());

        assertEq(orb.keeperTaxNumerator(), largeNumerator);
        assertEq(orb.royaltyNumerator(), orb.feeDenominator());
    }

    function test_setFeesSucceedsCorrectly() public {
        assertEq(orb.keeperTaxNumerator(), 10_00);
        assertEq(orb.royaltyNumerator(), 10_00);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit FeesUpdate(10_00, 100_00, 10_00, 100_00);
        orb.setFees(100_00, 100_00);
        assertEq(orb.keeperTaxNumerator(), 100_00);
        assertEq(orb.royaltyNumerator(), 100_00);
    }
}

contract SettingCooldownTest is OrbTestBase {
    event CooldownUpdate(
        uint256 previousCooldown,
        uint256 indexed newCooldown,
        uint256 previousFlaggingPeriod,
        uint256 indexed newFlaggingPeriod
    );

    function test_setCooldownOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setCooldown(1 days, 2 days);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.setCooldown(1 days, 2 days);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(IOrb.CreatorDoesNotControlOrb.selector);
        orb.setCooldown(1 days, 2 days);
    }

    function test_revertsWhenCooldownTooLong() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrb.CooldownExceedsMaximumDuration.selector, 3651 days, 3650 days));
        orb.setCooldown(3651 days, 2 days);
    }

    function test_setCooldownSucceedsCorrectly() public {
        assertEq(orb.cooldown(), 7 days);
        assertEq(orb.flaggingPeriod(), 7 days);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit CooldownUpdate(7 days, 1 days, 7 days, 2 days);
        orb.setCooldown(1 days, 2 days);
        assertEq(orb.cooldown(), 1 days);
        assertEq(orb.flaggingPeriod(), 2 days);
    }
}

contract SettingCleartextMaximumLengthTest is OrbTestBase {
    event CleartextMaximumLengthUpdate(
        uint256 previousCleartextMaximumLength, uint256 indexed newCleartextMaximumLength
    );

    function test_setCleartextMaximumLengthOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setCleartextMaximumLength(1);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.setCleartextMaximumLength(1);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(IOrb.CreatorDoesNotControlOrb.selector);
        orb.setCleartextMaximumLength(1);
    }

    function test_revertIfCleartextMaximumLengthZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InvalidCleartextMaximumLength.selector, 0));
        orb.setCleartextMaximumLength(0);
    }

    function test_setCleartextMaximumLengthSucceedsCorrectly() public {
        assertEq(orb.cleartextMaximumLength(), 280);
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit CleartextMaximumLengthUpdate(280, 1);
        orb.setCleartextMaximumLength(1);
        assertEq(orb.cleartextMaximumLength(), 1);
    }
}

contract MinimumBidTest is OrbTestBase {
    function test_minimumBidReturnsCorrectValues() public {
        uint256 bidAmount = 0.6 ether;
        orb.startAuction();
        assertEq(orb.workaround_minimumBid(), orb.auctionStartingPrice());
        prankAndBid(user, bidAmount);
        assertEq(orb.workaround_minimumBid(), bidAmount + orb.auctionMinimumBidStep());
    }
}

contract StartAuctionTest is OrbTestBase {
    function test_startAuctionOnlyOrbCreator() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("Ownable: caller is not the owner");
        orb.startAuction();
        orb.startAuction();
    }

    event AuctionStart(
        uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
    );

    function test_startAuctionCorrectly() public {
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration(), beneficiary);
        orb.startAuction();
        assertEq(orb.auctionEndTime(), block.timestamp + orb.auctionMinimumDuration());
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
    }

    function test_startAuctionOnlyContractHeld() public {
        orb.workaround_setOrbKeeper(address(0xBEEF));
        vm.expectRevert(IOrb.ContractDoesNotHoldOrb.selector);
        orb.startAuction();
        orb.workaround_setOrbKeeper(address(orb));
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration(), beneficiary);
        orb.startAuction();
    }

    function test_startAuctionNotDuringAuction() public {
        assertEq(orb.auctionEndTime(), 0);
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration(), beneficiary);
        orb.startAuction();
        assertGt(orb.auctionEndTime(), 0);
        vm.warp(orb.auctionEndTime());

        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.startAuction();
    }
}

contract BidTest is OrbTestBase {
    function test_bidOnlyDuringAuction() public {
        uint256 bidAmount = 0.6 ether;
        vm.deal(user, bidAmount);
        vm.expectRevert(IOrb.AuctionNotRunning.selector);
        vm.prank(user);
        orb.bid{value: bidAmount}(bidAmount, bidAmount);
        orb.startAuction();
        assertEq(orb.leadingBid(), 0 ether);
        prankAndBid(user, bidAmount);
        assertEq(orb.leadingBid(), bidAmount);
    }

    function test_bidUsesTotalFunds() public {
        orb.deposit{value: 1 ether}();
        orb.startAuction();
        vm.prank(user);
        assertEq(orb.leadingBid(), 0 ether);
        prankAndBid(user, 0.5 ether);
        assertEq(orb.leadingBid(), 0.5 ether);
    }

    function test_bidRevertsIfBeneficiary() public {
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
        vm.deal(beneficiary, amount);
        vm.expectRevert(abi.encodeWithSelector(IOrb.BeneficiaryDisallowed.selector));
        vm.prank(beneficiary);
        orb.bid{value: amount}(amount, amount);

        // will not revert
        prankAndBid(user, amount);
        assertEq(orb.leadingBid(), amount);
    }

    function test_bidRevertsIfLtMinimumBid() public {
        orb.startAuction();
        // minimum bid will be the STARTING_PRICE
        uint256 amount = orb.workaround_minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientBid.selector, amount, orb.workaround_minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);

        // Add back + 1 to amount
        amount++;
        // will not revert
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);
        assertEq(orb.leadingBid(), amount);

        // minimum bid will be the leading bid + MINIMUM_BID_STEP
        amount = orb.workaround_minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientBid.selector, amount, orb.workaround_minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);
    }

    function test_bidRevertsIfLtFundsRequired() public {
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
        uint256 funds = amount - 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientFunds.selector, funds, funds + 1));
        vm.prank(user);
        orb.bid{value: funds}(amount, amount);

        funds++;
        vm.prank(user);
        // will not revert
        orb.bid{value: funds}(amount, amount);
        assertEq(orb.leadingBid(), amount);
    }

    function test_bidRevertsIfPriceTooHigh() public {
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
        uint256 price = orb.workaround_maximumPrice() + 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InvalidNewPrice.selector, price));
        vm.prank(user);
        orb.bid{value: amount}(amount, price);

        // Bring price back to acceptable amount
        price--;
        // will not revert
        vm.prank(user);
        orb.bid{value: amount}(amount, price);
        assertEq(orb.leadingBid(), amount);
        assertEq(orb.price(), orb.workaround_maximumPrice());
    }

    event AuctionBid(address indexed bidder, uint256 indexed bid);

    function test_bidSetsCorrectState() public {
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
        uint256 funds = fundsRequiredToBidOneYear(amount);
        assertEq(orb.leadingBid(), 0 ether);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.fundsOf(user), 0);
        assertEq(address(orb).balance, 0);
        uint256 auctionEndTime = orb.auctionEndTime();

        vm.expectEmit(true, true, true, true);
        emit AuctionBid(user, amount);
        prankAndBid(user, amount);

        assertEq(orb.leadingBid(), amount);
        assertEq(orb.leadingBidder(), user);
        assertEq(orb.price(), amount);
        assertEq(orb.fundsOf(user), funds);
        assertEq(address(orb).balance, funds);
        assertEq(orb.auctionEndTime(), auctionEndTime);
    }

    mapping(address => uint256) internal fundsOfUser;

    event AuctionFinalization(address indexed winner, uint256 indexed winningBid);

    function testFuzz_bidSetsCorrectState(address[16] memory bidders, uint128[16] memory amounts) public {
        orb.startAuction();
        uint256 contractBalance;
        for (uint256 i = 1; i < 16; i++) {
            uint256 upperBound = orb.workaround_minimumBid() + 1_000_000_000;
            uint256 amount = bound(amounts[i], orb.workaround_minimumBid(), upperBound);
            address bidder = bidders[i];
            vm.assume(bidder != address(0) && bidder != address(orb) && bidder != beneficiary);

            uint256 funds = fundsRequiredToBidOneYear(amount);

            fundsOfUser[bidder] += funds;

            vm.expectEmit(true, true, true, true);
            emit AuctionBid(bidder, amount);
            prankAndBid(bidder, amount);
            contractBalance += funds;

            assertEq(orb.leadingBid(), amount);
            assertEq(orb.leadingBidder(), bidder);
            assertEq(orb.price(), amount);
            assertEq(orb.fundsOf(bidder), fundsOfUser[bidder]);
            assertEq(address(orb).balance, contractBalance);
        }
        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(orb.leadingBidder(), orb.leadingBid());
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
    }

    event AuctionExtension(uint256 indexed newAuctionEndTime);

    function test_bidExtendsAuction() public {
        assertEq(orb.auctionEndTime(), 0);
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
        // auctionEndTime = block.timestamp + auctionMinimumDuration
        uint256 auctionEndTime = orb.auctionEndTime();
        // set block.timestamp to auctionEndTime - auctionBidExtension
        vm.warp(auctionEndTime - orb.auctionBidExtension());
        prankAndBid(user, amount);
        // didn't change because block.timestamp + auctionBidExtension = auctionEndTime
        assertEq(orb.auctionEndTime(), auctionEndTime);

        vm.warp(auctionEndTime - orb.auctionBidExtension() + 50);
        amount = orb.workaround_minimumBid();
        vm.expectEmit(true, true, true, true);
        emit AuctionExtension(auctionEndTime + 50);
        prankAndBid(user, amount);
        // change because block.timestamp + auctionBidExtension + 50 >  auctionEndTime
        assertEq(orb.auctionEndTime(), auctionEndTime + 50);
    }
}

contract FinalizeAuctionTest is OrbTestBase {
    event AuctionFinalization(address indexed winner, uint256 indexed winningBid);

    function test_finalizeAuctionRevertsDuringAuction() public {
        orb.startAuction();
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.finalizeAuction();

        vm.warp(orb.auctionEndTime() + 1);
        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(address(0), 0);
        orb.finalizeAuction();
    }

    function test_finalizeAuctionRevertsIfAuctionNotStarted() public {
        vm.expectRevert(IOrb.AuctionNotStarted.selector);
        orb.finalizeAuction();
        orb.startAuction();
        // auctionEndTime != 0
        assertEq(orb.auctionEndTime(), block.timestamp + orb.auctionMinimumDuration());
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.finalizeAuction();
    }

    function test_finalizeAuctionWithoutWinner() public {
        orb.startAuction();
        vm.warp(orb.auctionEndTime() + 1);
        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(address(0), 0);
        orb.finalizeAuction();
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), 0);
    }

    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);

    function test_finalizeAuctionWithWinner() public {
        orb.startAuction();
        uint256 amount = orb.workaround_minimumBid();
        uint256 funds = fundsRequiredToBidOneYear(amount);
        // Bid `amount` and transfer `funds` to the contract
        prankAndBid(user, amount);
        vm.warp(orb.auctionEndTime() + 1);

        // Assert storage before
        assertEq(orb.leadingBidder(), user);
        assertEq(orb.leadingBid(), amount);
        assertEq(orb.price(), amount);
        assertEq(orb.fundsOf(user), funds);
        assertEq(orb.fundsOf(address(orb)), 0);

        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(user, amount);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(0, amount);

        orb.finalizeAuction();

        // Assert storage after
        // storage that is reset
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), amount);

        // storage that persists
        assertEq(address(orb).balance, funds);
        assertEq(orb.fundsOf(beneficiary), amount);
        assertEq(orb.keeper(), user);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.lastInvocationTime(), block.timestamp - orb.cooldown());
        assertEq(orb.fundsOf(user), funds - amount);
        assertEq(orb.price(), amount);
    }

    function test_finalizeAuctionWithBeneficiary() public {
        makeKeeperAndWarp(user, 1 ether);
        assertEq(orb.auctionBeneficiary(), beneficiary);
        vm.prank(user);
        orb.relinquish(true);
        uint256 contractBalance = address(orb).balance;
        assertEq(orb.auctionBeneficiary(), user);

        uint256 amount = orb.workaround_minimumBid();
        uint256 funds = fundsRequiredToBidOneYear(amount);
        // Bid `amount` and transfer `funds` to the contract
        prankAndBid(user2, amount);
        vm.warp(orb.auctionEndTime() + 1);

        // Assert storage before
        assertEq(orb.leadingBidder(), user2);
        assertEq(orb.leadingBid(), amount);
        assertEq(orb.price(), amount);
        assertEq(orb.fundsOf(user2), funds);
        assertEq(orb.fundsOf(address(orb)), 0);

        uint256 beneficiaryRoyalty = (amount * orb.royaltyNumerator()) / orb.feeDenominator();
        uint256 auctionBeneficiaryShare = amount - beneficiaryRoyalty;
        uint256 userFunds = orb.fundsOf(user);
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);

        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(user2, amount);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(0, amount);

        orb.finalizeAuction();

        // Assert storage after
        // storage that is reset
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), amount);

        // storage that persists
        assertEq(address(orb).balance, contractBalance + funds);
        assertEq(orb.fundsOf(beneficiary), beneficiaryFunds + beneficiaryRoyalty);
        assertEq(orb.keeper(), user2);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.lastInvocationTime(), block.timestamp - orb.cooldown());
        assertEq(orb.fundsOf(user2), funds - amount);
        assertEq(orb.fundsOf(user), userFunds + auctionBeneficiaryShare);
    }

    function test_finalizeAuctionWithBeneficiaryLowRoyalties() public {
        orb.setFees(100_00, 0);
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish(true);
        uint256 amount = orb.workaround_minimumBid();
        // Bid `amount` and transfer `funds` to the contract
        prankAndBid(user2, amount);
        vm.warp(orb.auctionEndTime() + 1);
        uint256 minBeneficiaryNumerator =
            orb.keeperTaxNumerator() * orb.auctionKeeperMinimumDuration() / orb.keeperTaxPeriod();
        assertTrue(minBeneficiaryNumerator > orb.royaltyNumerator());
        uint256 minBeneficiaryRoyalty = (amount * minBeneficiaryNumerator) / orb.feeDenominator();
        uint256 auctionBeneficiaryShare = amount - minBeneficiaryRoyalty;
        uint256 userFunds = orb.fundsOf(user);
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        orb.finalizeAuction();
        assertEq(orb.fundsOf(beneficiary), beneficiaryFunds + minBeneficiaryRoyalty);
        assertEq(orb.fundsOf(user), userFunds + auctionBeneficiaryShare);
    }

    function test_finalizeAuctionWithBeneficiaryWithoutWinner() public {
        makeKeeperAndWarp(user, 1 ether);
        assertEq(orb.auctionBeneficiary(), beneficiary);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.auctionBeneficiary(), user);
        vm.warp(orb.auctionEndTime() + 1);

        vm.expectEmit(true, true, true, true);
        emit AuctionFinalization(address(0), 0);
        orb.finalizeAuction();

        // Assert storage after
        assertEq(orb.auctionBeneficiary(), user);
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), 0);

        orb.startAuction();
        assertEq(orb.auctionBeneficiary(), beneficiary);
    }
}

contract ListingTest is OrbTestBase {
    function test_revertsIfHeldByUser() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.expectRevert(IOrb.ContractDoesNotHoldOrb.selector);
        orb.listWithPrice(1 ether);
    }

    function test_revertsIfAlreadyHeldByCreator() public {
        makeKeeperAndWarp(owner, 1 ether);
        vm.expectRevert(IOrb.ContractDoesNotHoldOrb.selector);
        orb.listWithPrice(1 ether);
    }

    function test_revertsIfAuctionStarted() public {
        orb.startAuction();
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.listWithPrice(1 ether);

        vm.warp(orb.auctionEndTime() + 1);
        assertFalse(orb.workaround_auctionRunning());
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.listWithPrice(1 ether);
    }

    function test_revertsIfCalledByUser() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        orb.listWithPrice(1 ether);
    }

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);

    function test_succeedsCorrectly() public {
        uint256 listingPrice = 1 ether;
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(orb), owner, 1);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(0, listingPrice);
        orb.listWithPrice(listingPrice);
        assertEq(orb.price(), listingPrice);
        assertEq(orb.keeper(), owner);
    }
}

contract EffectiveFundsOfTest is OrbTestBase {
    function test_effectiveFundsCorrectCalculation() public {
        uint256 amount1 = 1 ether;
        uint256 amount2 = 0.5 ether;
        uint256 funds1 = fundsRequiredToBidOneYear(amount1);
        uint256 funds2 = fundsRequiredToBidOneYear(amount2);
        orb.startAuction();
        prankAndBid(user2, amount2);
        prankAndBid(user, amount1);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 1 days);

        // One day has passed since the Orb keeper got the orb
        // for bid = 1 ether. That means that the price of the
        // Orb is now 1 ether. Thus the Orb beneficiary is owed the tax
        // for 1 day.

        // The user actually transfered `funds1` and `funds2` respectively
        // ether to the contract
        uint256 owed = orb.workaround_owedSinceLastSettlement();
        assertEq(effectiveFundsOf(beneficiary), owed + amount1);
        // The user that won the auction and is holding the orb
        // has the funds they deposited, minus the tax and minus the bid
        // amount
        assertEq(effectiveFundsOf(user), funds1 - owed - amount1);
        // The user that didn't won the auction, has the funds they
        // deposited
        assertEq(effectiveFundsOf(user2), funds2);
    }

    function testFuzz_effectiveFundsCorrectCalculation(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1 ether, orb.workaround_maximumPrice());
        amount2 = bound(amount2, orb.auctionStartingPrice(), amount1 - orb.auctionMinimumBidStep());
        uint256 funds1 = fundsRequiredToBidOneYear(amount1);
        uint256 funds2 = fundsRequiredToBidOneYear(amount2);
        orb.startAuction();
        prankAndBid(user2, amount2);
        prankAndBid(user, amount1);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 1 days);

        // One day has passed since the Orb keeper got the Orb
        // for bid = 1 ether. That means that the price of the
        // Orb is now 1 ether. Thus the Orb beneficiary is owed the tax
        // for 1 day.

        // The user actually transfered `funds1` and `funds2` respectively
        // ether to the contract
        uint256 owed = orb.workaround_owedSinceLastSettlement();
        assertEq(effectiveFundsOf(beneficiary), owed + amount1);
        // The user that won the auction and is holding the Orb
        // has the funds they deposited, minus the tax and minus the bid
        // amount
        assertEq(effectiveFundsOf(user), funds1 - owed - amount1);
        // The user that didn't won the auction, has the funds they
        // deposited
        assertEq(effectiveFundsOf(user2), funds2);
    }
}

contract DepositTest is OrbTestBase {
    event Deposit(address indexed depositor, uint256 indexed amount);

    function test_depositRandomUser() public {
        assertEq(orb.fundsOf(user), 0);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, 1 ether);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user), 1 ether);
    }

    function testFuzz_depositRandomUser(uint256 amount) public {
        assertEq(orb.fundsOf(user), 0);
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, amount);
        vm.deal(user, amount);
        vm.prank(user);
        orb.deposit{value: amount}();
        assertEq(orb.fundsOf(user), amount);
    }

    function test_depositKeeperSolvent() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        uint256 depositAmount = 2 ether;
        makeKeeperAndWarp(user, bidAmount);
        // User bids 1 ether, but deposit enough funds
        // to cover the tax for a year, according to
        // fundsRequiredToBidOneYear(bidAmount)
        uint256 funds = orb.fundsOf(user);
        vm.expectEmit(true, true, true, true);
        // deposit 1 ether
        emit Deposit(user, depositAmount);
        vm.prank(user);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), funds + depositAmount);
    }

    function testFuzz_depositKeeperSolvent(uint256 bidAmount, uint256 depositAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, 0.1 ether, orb.workaround_maximumPrice());
        depositAmount = bound(depositAmount, 0.1 ether, orb.workaround_maximumPrice());
        makeKeeperAndWarp(user, bidAmount);
        // User bids 1 ether, but deposit enough funds
        // to cover the tax for a year, according to
        // fundsRequiredToBidOneYear(bidAmount)
        uint256 funds = orb.fundsOf(user);
        vm.expectEmit(true, true, true, true);
        // deposit 1 ether
        emit Deposit(user, depositAmount);
        vm.prank(user);
        vm.deal(user, depositAmount);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), funds + depositAmount);
    }

    function test_depositRevertsifKeeperInsolvent() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        makeKeeperAndWarp(user, bidAmount);

        // let's make the user insolvent
        // fundsRequiredToBidOneYear(bidAmount) ensures enough
        // ether for 1 year, not two
        vm.warp(block.timestamp + 731 days);

        // if a random user deposits, it should work fine
        vm.prank(user2);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user2), 1 ether);

        // if the insolvent keeper deposits, it should not work
        vm.expectRevert(IOrb.KeeperInsolvent.selector);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
    }
}

contract WithdrawTest is OrbTestBase {
    event Withdrawal(address indexed recipient, uint256 indexed amount);

    function test_withdrawRevertsIfLeadingBidder() public {
        uint256 bidAmount = 1 ether;
        orb.startAuction();
        prankAndBid(user, bidAmount);
        vm.expectRevert(IOrb.NotPermittedForLeadingBidder.selector);
        vm.prank(user);
        orb.withdraw(1);

        vm.expectRevert(IOrb.NotPermittedForLeadingBidder.selector);
        vm.prank(user);
        orb.withdrawAll();

        // user is no longer the leadingBidder
        prankAndBid(user2, 2 ether);

        // user can withdraw
        uint256 fundsBefore = orb.fundsOf(user);
        vm.startPrank(user);
        assertEq(user.balance, startingBalance);
        orb.withdraw(100);
        assertEq(user.balance, startingBalance + 100);
        assertEq(orb.fundsOf(user), fundsBefore - 100);
        orb.withdrawAll();
        assertEq(orb.fundsOf(user), 0);
        assertEq(user.balance, startingBalance + fundsBefore);
    }

    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);

    function test_withdrawSettlesFirstIfKeeper() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 10 ether;
        uint256 smallBidAmount = 0.5 ether;
        uint256 withdrawAmount = 0.1 ether;

        orb.startAuction();
        // user2 bids
        prankAndBid(user2, smallBidAmount);
        // user1 bids and becomes the leading bidder
        prankAndBid(user, bidAmount);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();

        vm.warp(block.timestamp + 30 days);

        // beneficiaryEffective = beneficiaryFunds + transferableToBeneficiary
        // userEffective = userFunds - transferableToBeneficiary
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 transferableToBeneficiary = beneficiaryEffective - beneficiaryFunds;
        uint256 initialBalance = user.balance;

        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);

        vm.prank(user);
        orb.withdraw(withdrawAmount);

        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + withdrawAmount);

        // move ahead 10 days;
        vm.warp(block.timestamp + 10 days);

        // not keeper
        vm.prank(user2);
        initialBalance = user2.balance;
        orb.withdraw(withdrawAmount);
        assertEq(orb.fundsOf(user2), fundsRequiredToBidOneYear(smallBidAmount) - withdrawAmount);
        assertEq(user2.balance, initialBalance + withdrawAmount);
    }

    function test_withdrawAllForBeneficiarySettlesAndWithdraws() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 10 ether;
        uint256 smallBidAmount = 0.5 ether;

        orb.startAuction();
        // user2 bids
        prankAndBid(user2, smallBidAmount);
        // user1 bids and becomes the leading bidder
        prankAndBid(user, bidAmount);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();

        vm.warp(block.timestamp + 30 days);

        // beneficiaryEffective = beneficiaryFunds + transferableToBeneficiary
        // userEffective = userFunds - transferableToBeneficiary
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 transferableToBeneficiary = beneficiaryEffective - beneficiaryFunds;
        uint256 initialBalance = beneficiary.balance;

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);

        vm.expectEmit(true, true, true, true);
        emit Withdrawal(beneficiary, beneficiaryFunds + transferableToBeneficiary);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(user), userEffective);
        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(beneficiary.balance, initialBalance + beneficiaryEffective);
    }

    function test_withdrawAllForBeneficiaryWhenContractOwned() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish(false);

        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 initialBalance = beneficiary.balance;
        uint256 settlementTime = block.timestamp;

        vm.warp(block.timestamp + 30 days);

        // expectNotEmit Settlement
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(beneficiary, beneficiaryFunds);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), settlementTime);
        assertEq(beneficiary.balance, initialBalance + beneficiaryFunds);
    }

    function test_withdrawAllForBeneficiaryWhenCreatorOwned() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish(false);
        vm.prank(owner);
        orb.listWithPrice(1 ether);

        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 initialBalance = beneficiary.balance;

        vm.warp(block.timestamp + 30 days);

        vm.expectEmit(true, true, true, true);
        emit Withdrawal(beneficiary, beneficiaryFunds);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(beneficiary.balance, initialBalance + beneficiaryFunds);
    }

    function testFuzz_withdrawSettlesFirstIfKeeper(uint256 bidAmount, uint256 withdrawAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, orb.auctionStartingPrice(), orb.workaround_maximumPrice());
        makeKeeperAndWarp(user, bidAmount);

        // beneficiaryEffective = beneficiaryFunds + transferableToBeneficiary
        // userEffective = userFunds - transferableToBeneficiary
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 transferableToBeneficiary = beneficiaryEffective - beneficiaryFunds;
        uint256 initialBalance = user.balance;

        vm.expectEmit(true, true, true, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);

        vm.prank(user);
        withdrawAmount = bound(withdrawAmount, 0, userEffective - 1);
        orb.withdraw(withdrawAmount);
        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + withdrawAmount);

        vm.prank(user);
        orb.withdrawAll();
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + userEffective);
    }

    function test_withdrawRevertsIfInsufficientFunds() public {
        vm.startPrank(user);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientFunds.selector, 1 ether, 1 ether + 1));
        orb.withdraw(1 ether + 1);
        assertEq(orb.fundsOf(user), 1 ether);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(user, 1 ether);
        orb.withdraw(1 ether);
        assertEq(orb.fundsOf(user), 0);
    }
}

contract SettleTest is OrbTestBase {
    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);

    function test_settleOnlyIfKeeperHeld() public {
        vm.expectRevert(IOrb.ContractHoldsOrb.selector);
        orb.settle();
        assertEq(orb.lastSettlementTime(), 0);
        makeKeeperAndWarp(user, 1 ether);
        orb.settle();
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function testFuzz_settleCorrect(uint96 bid, uint96 time) public {
        uint256 amount = bound(bid, orb.auctionStartingPrice(), orb.workaround_maximumPrice());
        // warp ahead a random amount of time
        // remain under 1 year in total, so solvent
        uint256 timeOffset = bound(time, 0, 300 days);
        vm.warp(block.timestamp + timeOffset);
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), 0);
        // it warps 30 days by default
        makeKeeperAndWarp(user, amount);

        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 initialBalance = user.balance;

        orb.settle();
        assertEq(orb.fundsOf(user), userEffective);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance);

        timeOffset = bound(time, block.timestamp + 340 days, type(uint96).max);
        vm.warp(timeOffset);

        // user is no longer solvent
        // the user can't pay the full owed feeds, so they
        // pay what they can
        uint256 transferable = orb.fundsOf(user);
        orb.settle();
        assertEq(orb.fundsOf(user), 0);
        // beneficiaryEffective is from the last time it settled
        assertEq(orb.fundsOf(beneficiary), transferable + beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance);
    }

    function test_settleReturnsIfOwner() public {
        orb.listWithPrice(1 ether);
        vm.warp(30 days);
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        orb.workaround_settle();
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.fundsOf(beneficiary), beneficiaryFunds);
    }
}

contract KeeperSolventTest is OrbTestBase {
    function test_keeperSolventCorrectIfNotOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.lastSettlementTime(), 0);
        // it warps 30 days by default
        makeKeeperAndWarp(user, 1 ether);
        assert(orb.keeperSolvent());
        vm.warp(block.timestamp + 700 days);
        assertFalse(orb.keeperSolvent());
    }

    function test_keeperSolventCorrectIfOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.lastSettlementTime(), 0);
        assert(orb.keeperSolvent());
        vm.warp(block.timestamp + 4885828483 days);
        assert(orb.keeperSolvent());
    }
}

contract OwedSinceLastSettlementTest is OrbTestBase {
    function test_owedSinceLastSettlementCorrectMath() public {
        // _lastSettlementTime = 0
        // secondsSinceLastSettlement = block.timestamp - _lastSettlementTime
        // KEEPER_TAX_NUMERATOR = 1_000
        // feeDenominator = 10_000
        // keeperTaxPeriod  = 365 days = 31_536_000 seconds
        // owed = _price * KEEPER_TAX_NUMERATOR * secondsSinceLastSettlement)
        // / (keeperTaxPeriod * feeDenominator);
        // Scenario:
        // _price = 17 ether = 17_000_000_000_000_000_000 wei
        // block.timestamp = 167710711
        // owed = 90.407.219.961.314.053.779,8072044647
        orb.workaround_setPrice(17 ether);
        vm.warp(167710711);
        // calculation done off-solidity to verify precision with another environment
        assertEq(orb.workaround_owedSinceLastSettlement(), 9_040_721_990_740_740_740);
    }
}

contract SetPriceTest is OrbTestBase {
    function test_setPriceRevertsIfNotKeeper() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.NotKeeper.selector);
        vm.prank(user2);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 10 ether);

        vm.prank(user);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 1 ether);
    }

    function test_setPriceRevertsIfKeeperInsolvent() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 600 days);
        vm.startPrank(user);
        vm.expectRevert(IOrb.KeeperInsolvent.selector);
        orb.setPrice(1 ether);

        // As the user can't deposit funds to become solvent again
        // we modify a variable to trick the contract
        orb.workaround_setLastSettlementTime(block.timestamp);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
    }

    function test_setPriceSettlesBefore() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.prank(user);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);

    function test_setPriceRevertsIfMaxPrice() public {
        uint256 maxPrice = orb.workaround_maximumPrice();
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InvalidNewPrice.selector, maxPrice + 1));
        orb.setPrice(maxPrice + 1);

        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(10 ether, maxPrice);
        orb.setPrice(maxPrice);
    }
}

contract PurchaseTest is OrbTestBase {
    function test_revertsIfHeldByContract() public {
        vm.prank(user);
        vm.expectRevert(IOrb.ContractHoldsOrb.selector);
        orb.purchase(100, 0, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfKeeperInsolvent() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user2);
        vm.expectRevert(IOrb.KeeperInsolvent.selector);
        orb.purchase(100, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_purchaseSettlesFirst() public {
        makeKeeperAndWarp(user, 1 ether);
        // after making `user` the current keeper of the Orb, `makeKeeperAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user2);
        orb.purchase{value: 1.1 ether}(2 ether, 1 ether, 10_00, 10_00, 7 days, 280);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function test_revertsIfBeneficiary() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.deal(beneficiary, 1.1 ether);
        vm.prank(beneficiary);
        vm.expectRevert(abi.encodeWithSelector(IOrb.BeneficiaryDisallowed.selector));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);

        // does not revert
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user2);
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function test_revertsIfWrongCurrentPrice() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IOrb.CurrentValueIncorrect.selector, 2 ether, 1 ether));
        orb.purchase{value: 1.1 ether}(3 ether, 2 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfWrongCurrentValues() public {
        orb.listWithPrice(1 ether);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrb.CurrentValueIncorrect.selector, 20_00, 10_00));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 20_00, 10_00, 7 days, 280);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrb.CurrentValueIncorrect.selector, 30_00, 10_00));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 30_00, 7 days, 280);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrb.CurrentValueIncorrect.selector, 8 days, 7 days));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 8 days, 280);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrb.CurrentValueIncorrect.selector, 140, 280));
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 140);

        vm.prank(user);
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfIfAlreadyKeeper() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.expectRevert(IOrb.AlreadyKeeper.selector);
        vm.prank(user);
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfInsufficientFunds() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientFunds.selector, 1 ether - 1, 1 ether));
        vm.prank(user2);
        orb.purchase{value: 1 ether - 1}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfPurchasingAfterSetPrice() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.setPrice(0);
        vm.expectRevert(abi.encodeWithSelector(IOrb.PurchasingNotPermitted.selector));
        vm.prank(user2);
        orb.purchase(1 ether, 0, 10_00, 10_00, 7 days, 280);
    }

    event Purchase(address indexed seller, address indexed buyer, uint256 indexed price);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);
    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);

    function test_beneficiaryAllProceedsIfOwnerSells() public {
        uint256 bidAmount = 1 ether;
        uint256 newPrice = 3 ether;
        uint256 purchaseAmount = bidAmount / 2;
        uint256 depositAmount = bidAmount / 2;
        // bidAmount will be the `_price` of the Orb
        makeKeeperAndWarp(owner, bidAmount);
        orb.settle();
        vm.warp(block.timestamp + 1 days);
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        vm.startPrank(user);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), userBefore + depositAmount);
        vm.expectEmit(true, true, true, true);
        emit Purchase(owner, user, bidAmount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(owner, user, 1);
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        orb.purchase{value: purchaseAmount + 1}(newPrice, bidAmount, 10_00, 10_00, 7 days, 280);
        uint256 beneficiaryRoyalty = bidAmount;
        assertEq(orb.fundsOf(beneficiary), beneficiaryBefore + beneficiaryRoyalty);
        assertEq(orb.fundsOf(owner), ownerBefore);
        // The price of the Orb was 1 ether and user2 transfered 1 ether + 1 to buy it
        assertEq(orb.fundsOf(user), 1);
        assertEq(orb.price(), newPrice);
        assertEq(orb.lastInvocationTime(), block.timestamp - orb.cooldown());
        assertEq(orb.keeperSolvent(), true);
    }

    function test_succeedsCorrectly() public {
        uint256 bidAmount = 1 ether;
        uint256 newPrice = 3 ether;
        uint256 expectedSettlement = bidAmount * orb.royaltyNumerator() / orb.feeDenominator();
        uint256 purchaseAmount = bidAmount / 2;
        uint256 depositAmount = bidAmount / 2;
        // bidAmount will be the `_price` of the Orb
        makeKeeperAndWarp(user, bidAmount);
        orb.settle();
        vm.prank(user);
        orb.deposit{value: expectedSettlement}();
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        uint256 lastInvocationTimeBefore = orb.lastInvocationTime();
        vm.warp(block.timestamp + 365 days);
        vm.prank(user2);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user2), depositAmount);
        vm.expectEmit(true, true, true, true);
        // 1 year has passed since the last settlement
        emit Settlement(user, beneficiary, expectedSettlement);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(bidAmount, newPrice);
        vm.expectEmit(true, true, true, true);
        emit Purchase(user, user2, bidAmount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(user, user2, 1);
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        vm.prank(user2);
        orb.purchase{value: purchaseAmount + 1}(newPrice, bidAmount, 10_00, 10_00, 7 days, 280);
        uint256 beneficiaryRoyalty = ((bidAmount * orb.royaltyNumerator()) / orb.feeDenominator());
        assertEq(orb.fundsOf(beneficiary), beneficiaryBefore + beneficiaryRoyalty + expectedSettlement);
        assertEq(orb.fundsOf(user), userBefore + (bidAmount - beneficiaryRoyalty - expectedSettlement));
        assertEq(orb.fundsOf(owner), ownerBefore);
        // The price of the Orb was 1 ether and user2 transfered 1 ether + 1 to buy it
        assertEq(orb.fundsOf(user2), 1);
        assertEq(orb.price(), newPrice);
        assertEq(orb.lastInvocationTime(), lastInvocationTimeBefore);
    }

    function testFuzz_succeedsCorrectly(uint256 bidAmount, uint256 newPrice, uint256 buyPrice, uint256 diff) public {
        bidAmount = bound(bidAmount, 0.1 ether, orb.workaround_maximumPrice() - 1);
        newPrice = bound(newPrice, 1, orb.workaround_maximumPrice());
        buyPrice = bound(buyPrice, bidAmount + 1, orb.workaround_maximumPrice());
        diff = bound(diff, 1, buyPrice);
        uint256 expectedSettlement = bidAmount * orb.royaltyNumerator() / orb.feeDenominator();
        vm.deal(user2, buyPrice);
        /// Break up the amount between depositing and purchasing to test more scenarios
        uint256 purchaseAmount = buyPrice - diff;
        uint256 depositAmount = diff;
        // bidAmount will be the `_price` of the Orb
        makeKeeperAndWarp(user, bidAmount);
        vm.deal(user, bidAmount + expectedSettlement);
        orb.settle();
        vm.startPrank(user);
        orb.deposit{value: expectedSettlement}();
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days);
        vm.prank(user2);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user2), depositAmount);
        vm.expectEmit(true, true, true, true);
        // 1 year has passed since the last settlement
        emit Settlement(user, beneficiary, expectedSettlement);
        vm.expectEmit(true, true, true, true);
        emit PriceUpdate(bidAmount, newPrice);
        vm.expectEmit(true, true, true, true);
        emit Purchase(user, user2, bidAmount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(user, user2, 1);
        // The Orb is purchased with purchaseAmount
        // It uses both the existing funds of the user and the funds
        // that the user transfers when calling `purchase()`
        // We bound the purchaseAmount to be higher than the current price (bidAmount)
        vm.prank(user2);
        orb.purchase{value: purchaseAmount}(newPrice, bidAmount, 10_00, 10_00, 7 days, 280);
        uint256 beneficiaryRoyalty = ((bidAmount * orb.royaltyNumerator()) / orb.feeDenominator());
        assertEq(orb.fundsOf(beneficiary), beneficiaryBefore + beneficiaryRoyalty + expectedSettlement);
        assertEq(orb.fundsOf(user), userBefore + (bidAmount - beneficiaryRoyalty - expectedSettlement));
        assertEq(orb.fundsOf(owner), ownerBefore);
        // User2 transfered buyPrice to the contract
        // User2 paid bidAmount
        assertEq(orb.fundsOf(user2), buyPrice - bidAmount);
        assertEq(orb.price(), newPrice);
    }
}

contract RelinquishmentTest is OrbTestBase {
    function test_revertsIfNotKeeper() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.NotKeeper.selector);
        vm.prank(user2);
        orb.relinquish(false);

        vm.prank(user);
        orb.relinquish(false);
        assertEq(orb.keeper(), address(orb));
    }

    function test_revertsIfKeeperInsolvent() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user);
        vm.expectRevert(IOrb.KeeperInsolvent.selector);
        orb.relinquish(false);
        vm.warp(block.timestamp - 1300 days);
        vm.prank(user);
        orb.relinquish(false);
        assertEq(orb.keeper(), address(orb));
    }

    function test_settlesFirst() public {
        makeKeeperAndWarp(user, 1 ether);
        // after making `user` the current keeper of the Orb, `makeKeeperAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user);
        orb.relinquish(false);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event Relinquishment(address indexed formerKeeper);
    event Withdrawal(address indexed recipient, uint256 indexed amount);

    function test_succeedsCorrectly() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        assertEq(orb.keeper(), user);
        vm.expectEmit(true, true, true, true);
        emit Relinquishment(user);
        vm.expectEmit(true, true, true, true);
        uint256 effectiveFunds = effectiveFundsOf(user);
        emit Withdrawal(user, effectiveFunds);
        vm.prank(user);
        orb.relinquish(false);
        assertEq(orb.keeper(), address(orb));
        assertEq(orb.price(), 0);
    }
}

contract RelinquishmentWithAuctionTest is OrbTestBase {
    function test_revertsIfNotKeeper() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.NotKeeper.selector);
        vm.prank(user2);
        orb.relinquish(true);

        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.keeper(), address(orb));
    }

    function test_revertsIfKeeperInsolvent() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user);
        vm.expectRevert(IOrb.KeeperInsolvent.selector);
        orb.relinquish(true);
        vm.warp(block.timestamp - 1300 days);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.keeper(), address(orb));
    }

    function test_revertsIfCreator() public {
        orb.listWithPrice(1 ether);
        vm.expectRevert(IOrb.NotPermittedForCreator.selector);
        orb.relinquish(true);
    }

    function test_noAuctionIfKeeperDurationZero() public {
        orb.setAuctionParameters(0, 1, 1 days, 0, 5 minutes);
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.auctionEndTime(), 0);
    }

    function test_settlesFirst() public {
        makeKeeperAndWarp(user, 1 ether);
        // after making `user` the current keeper of the Orb, `makeKeeperAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event Relinquishment(address indexed formerKeeper);
    event AuctionStart(
        uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
    );
    event Withdrawal(address indexed recipient, uint256 indexed amount);

    function test_succeedsCorrectly() public {
        makeKeeperAndWarp(user, 1 ether);
        vm.prank(user);
        assertEq(orb.keeper(), user);
        assertEq(orb.price(), 1 ether);
        assertEq(orb.auctionBeneficiary(), beneficiary);
        assertEq(orb.auctionEndTime(), 0);
        uint256 effectiveFunds = effectiveFundsOf(user);
        vm.expectEmit(true, true, true, true);
        emit Relinquishment(user);
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionKeeperMinimumDuration(), user);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(user, effectiveFunds);
        vm.prank(user);
        orb.relinquish(true);
        assertEq(orb.keeper(), address(orb));
        assertEq(orb.price(), 0);
        assertEq(orb.auctionBeneficiary(), user);
        assertEq(orb.auctionEndTime(), block.timestamp + orb.auctionKeeperMinimumDuration());
    }
}

contract ForecloseTest is OrbTestBase {
    function test_revertsIfNotKeeperHeld() public {
        vm.expectRevert(IOrb.ContractHoldsOrb.selector);
        vm.prank(user2);
        orb.foreclose();

        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 100000 days);
        vm.prank(user2);
        orb.foreclose();
        assertEq(orb.keeper(), address(orb));
    }

    event Foreclosure(address indexed formerKeeper);
    event AuctionStart(
        uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
    );

    function test_revertsifKeeperSolvent() public {
        uint256 leadingBid = 10 ether;
        makeKeeperAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.KeeperSolvent.selector);
        orb.foreclose();
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, true, true, true);
        emit Foreclosure(user);
        orb.foreclose();
    }

    function test_noAuctionIfKeeperDurationZero() public {
        orb.setAuctionParameters(0, 1, 1 days, 0, 5 minutes);
        makeKeeperAndWarp(user, 10 ether);
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, true, true, true);
        emit Foreclosure(user);
        assertEq(orb.keeper(), user);
        orb.foreclose();
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.keeper(), address(orb));
        assertEq(orb.price(), 0);
    }

    function test_succeeds() public {
        makeKeeperAndWarp(user, 10 ether);
        vm.warp(block.timestamp + 10000 days);
        uint256 exepectedEndTime = block.timestamp + orb.auctionKeeperMinimumDuration();
        vm.expectEmit(true, true, true, true);
        emit Foreclosure(user);
        vm.expectEmit(true, true, true, true);
        emit AuctionStart(block.timestamp, exepectedEndTime, user);
        assertEq(orb.keeper(), user);
        orb.foreclose();
        assertEq(orb.auctionBeneficiary(), user);
        assertEq(orb.auctionEndTime(), exepectedEndTime);
        assertEq(orb.keeper(), address(orb));
        assertEq(orb.price(), 0);
    }
}
