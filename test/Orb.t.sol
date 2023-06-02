// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {OrbHarness} from "./harness/OrbHarness.sol";
import {Orb} from "src/Orb.sol";
import {IOrb} from "src/IOrb.sol";

/* solhint-disable func-name-mixedcase,private-vars-leading-underscore */
contract OrbTestBase is Test {
    OrbHarness internal orb;

    address internal user;
    address internal user2;
    address internal beneficiary;
    address internal owner;

    uint256 internal startingBalance;

    event Creation(bytes32 oathHash, uint256 honoredUntil);

    function setUp() public {
        vm.expectEmit(false, false, false, true);
        // keccak hash of "test oath"
        emit Creation(0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc, 100);
        orb = new OrbHarness();
        orb.setAuctionParameters(0.1 ether, 0.1 ether, 1 days, 5 minutes);
        user = address(0xBEEF);
        user2 = address(0xFEEEEEB);
        beneficiary = address(0xC0FFEE);
        startingBalance = 10000 ether;
        vm.deal(user, startingBalance);
        vm.deal(user2, startingBalance);
        owner = orb.owner();
    }

    function prankAndBid(address bidder, uint256 bidAmount) internal {
        uint256 finalAmount = fundsRequiredToBidOneYear(bidAmount);
        vm.deal(bidder, startingBalance + finalAmount);
        vm.prank(bidder);
        orb.bid{value: finalAmount}(bidAmount, bidAmount);
    }

    function makeHolderAndWarp(address newHolder, uint256 bid) public {
        orb.startAuction();
        prankAndBid(newHolder, bid);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);
    }

    function fundsRequiredToBidOneYear(uint256 amount) public view returns (uint256) {
        return amount + (amount * orb.holderTaxNumerator()) / orb.feeDenominator();
    }

    function effectiveFundsOf(address user_) public view returns (uint256) {
        uint256 unadjustedFunds = orb.fundsOf(user_);
        address holder = orb.ownerOf(orb.tokenId());

        if (user_ == orb.owner()) {
            return unadjustedFunds;
        }

        if (user_ == beneficiary || user_ == holder) {
            uint256 owedFunds = orb.workaround_owedSinceLastSettlement();
            uint256 holderFunds = orb.fundsOf(holder);
            uint256 transferableToBeneficiary = holderFunds <= owedFunds ? holderFunds : owedFunds;

            if (user_ == beneficiary) {
                return unadjustedFunds + transferableToBeneficiary;
            }
            if (user_ == holder) {
                return unadjustedFunds - transferableToBeneficiary;
            }
        }

        return unadjustedFunds;
    }
}

contract InitialStateTest is OrbTestBase {
    // Test that the initial state is correct
    function test_initialState() public {
        assertEq(address(orb), orb.ownerOf(orb.tokenId()));
        assertFalse(orb.auctionRunning());
        assertEq(orb.owner(), address(this));
        assertEq(orb.beneficiary(), address(0xC0FFEE));
        assertEq(orb.honoredUntil(), 100); // 1_700_000_000

        assertEq(orb.workaround_baseURI(), "https://static.orb.land/orb/");

        assertEq(orb.cleartextMaximumLength(), 280);

        assertEq(orb.price(), 0);
        assertEq(orb.holderTaxNumerator(), 1_000);
        assertEq(orb.royaltyNumerator(), 1_000);
        assertEq(orb.lastInvocationTime(), 0);
        assertEq(orb.invocationCount(), 0);

        assertEq(orb.flaggedResponsesCount(), 0);

        assertEq(orb.auctionStartingPrice(), 0.1 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.1 ether);
        assertEq(orb.auctionMinimumDuration(), 1 days);
        assertEq(orb.auctionBidExtension(), 5 minutes);

        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.leadingBid(), 0);

        assertEq(orb.lastSettlementTime(), 0);
        assertEq(orb.holderReceiveTime(), 0);
    }

    function test_constants() public {
        assertEq(orb.feeDenominator(), 10000);
        assertEq(orb.holderTaxPeriod(), 365 days);

        assertEq(orb.tokenId(), 69);
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
        assert(orb.supportsInterface(0xa46de429)); // ERC165 Interface ID for Orb
    }
}

contract TransfersRevertTest is OrbTestBase {
    function test_transfersRevert() public {
        address newOwner = address(0xBEEF);
        uint256 id = orb.tokenId();
        vm.expectRevert(IOrb.TransferringNotSupported.selector);
        orb.transferFrom(address(this), newOwner, id);
        vm.expectRevert(IOrb.TransferringNotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, id);
        vm.expectRevert(IOrb.TransferringNotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, id, bytes(""));
    }
}

contract SwearOathTest is OrbTestBase {
    event OathSwearing(bytes32 oathHash, uint256 honoredUntil);

    function test_swearOathOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(IOrb.CreatorDoesNotControlOrb.selector);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100);
    }

    function test_swearOathCorrectly() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        // keccak hash of "test oath"
        emit OathSwearing(0xa0a79538f3c69ab225db00333ba71e9265d3835a715fd7e15ada45dc746608bc, 100);
        orb.swearOath(keccak256(abi.encodePacked("test oath")), 100);
        assertEq(orb.honoredUntil(), 100);
    }
}

contract ExtendHonoredUntilTest is OrbTestBase {
    event HonoredUntilUpdate(uint256 previousHonoredUntil, uint256 newHonoredUntil);

    function test_extendHonoredUntilOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.extendHonoredUntil(101);

        makeHolderAndWarp(user, 1 ether);
        vm.prank(owner);
        orb.extendHonoredUntil(101);
    }

    function test_extendHonoredUntilNotDecrease() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(owner);
        vm.expectRevert(IOrb.HonoredUntilNotDecreasable.selector);
        orb.extendHonoredUntil(99);
    }

    function test_extendHonoredUntilCorrectly() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit HonoredUntilUpdate(100, 101);
        orb.extendHonoredUntil(101);
    }
}

contract SettingBaseURITest is OrbTestBase {
    function test_baseURIrevertsIfUser() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setBaseURI("https://static.orb.land/new/");
    }

    function test_baseURISetsCorrectState() public {
        vm.prank(owner);
        orb.setBaseURI("https://static.orb.land/new/");
        assertEq(orb.workaround_baseURI(), "https://static.orb.land/new/");
    }
}

contract SettingAuctionParametersTest is OrbTestBase {
    event AuctionParametersUpdate(
        uint256 previousStartingPrice,
        uint256 newStartingPrice,
        uint256 previousMinimumBidStep,
        uint256 newMinimumBidStep,
        uint256 previousMinimumDuration,
        uint256 newMinimumDuration,
        uint256 previousBidExtension,
        uint256 newBidExtension
    );

    function test_setAuctionParametersOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 10 minutes);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 10 minutes);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(IOrb.CreatorDoesNotControlOrb.selector);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 10 minutes);
    }

    function test_revertIfAuctionDurationZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InvalidAuctionDuration.selector, 0));
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 0, 10 minutes);
    }

    function test_boundMinBidStepToAbove0() public {
        assertEq(orb.auctionStartingPrice(), 0.1 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.1 ether);
        vm.prank(owner);
        orb.setAuctionParameters(0, 0, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0);
        assertEq(orb.auctionMinimumBidStep(), 1);

        vm.prank(owner);
        orb.setAuctionParameters(0, 2, 1 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0);
        assertEq(orb.auctionMinimumBidStep(), 2);
    }

    function test_setAuctionParametersSucceedsCorrectly() public {
        assertEq(orb.auctionStartingPrice(), 0.1 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.1 ether);
        assertEq(orb.auctionMinimumDuration(), 1 days);
        assertEq(orb.auctionBidExtension(), 5 minutes);
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit AuctionParametersUpdate(0.1 ether, 0.2 ether, 0.1 ether, 0.2 ether, 1 days, 2 days, 5 minutes, 10 minutes);
        orb.setAuctionParameters(0.2 ether, 0.2 ether, 2 days, 10 minutes);
        assertEq(orb.auctionStartingPrice(), 0.2 ether);
        assertEq(orb.auctionMinimumBidStep(), 0.2 ether);
        assertEq(orb.auctionMinimumDuration(), 2 days);
        assertEq(orb.auctionBidExtension(), 10 minutes);
    }
}

contract SettingFeesTest is OrbTestBase {
    event FeesUpdate(
        uint256 previousHolderTaxNumerator,
        uint256 newHolderTaxNumerator,
        uint256 previousRoyaltyNumerator,
        uint256 newRoyaltyNumerator
    );

    function test_setFeesOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setFees(10_000, 10_000);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.setFees(10_000, 10_000);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(IOrb.CreatorDoesNotControlOrb.selector);
        orb.setFees(10_000, 10_000);
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

        assertEq(orb.holderTaxNumerator(), largeNumerator);
        assertEq(orb.royaltyNumerator(), orb.feeDenominator());
    }

    function test_setFeesSucceedsCorrectly() public {
        assertEq(orb.holderTaxNumerator(), 1000);
        assertEq(orb.royaltyNumerator(), 1000);
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit FeesUpdate(1000, 10_000, 1000, 10_000);
        orb.setFees(10_000, 10_000);
        assertEq(orb.holderTaxNumerator(), 10_000);
        assertEq(orb.royaltyNumerator(), 10_000);
    }
}

contract SettingCooldownTest is OrbTestBase {
    event CooldownUpdate(uint256 previousCooldown, uint256 newCooldown);

    function test_setCooldownOnlyOwnerControlled() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        orb.setCooldown(1 days);

        vm.prank(owner);
        orb.startAuction();

        vm.prank(owner);
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.setCooldown(1 days);

        prankAndBid(user, 1 ether);
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
        vm.warp(block.timestamp + 30 days);

        vm.prank(owner);
        vm.expectRevert(IOrb.CreatorDoesNotControlOrb.selector);
        orb.setCooldown(1 days);
    }

    function test_revertsWhenCooldownTooLong() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrb.CooldownExceedsMaximumDuration.selector, 3651 days, 3650 days));
        orb.setCooldown(3651 days);
    }

    function test_setCooldownSucceedsCorrectly() public {
        assertEq(orb.cooldown(), 7 days);
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit CooldownUpdate(7 days, 1 days);
        orb.setCooldown(1 days);
        assertEq(orb.cooldown(), 1 days);
    }
}

contract SettingCleartextMaximumLengthTest is OrbTestBase {
    event CleartextMaximumLengthUpdate(uint256 previousCleartextMaximumLength, uint256 newCleartextMaximumLength);

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
        vm.expectEmit(false, false, false, true);
        emit CleartextMaximumLengthUpdate(280, 1);
        orb.setCleartextMaximumLength(1);
        assertEq(orb.cleartextMaximumLength(), 1);
    }
}

contract MinimumBidTest is OrbTestBase {
    function test_minimumBidReturnsCorrectValues() public {
        uint256 bidAmount = 0.6 ether;
        orb.startAuction();
        assertEq(orb.minimumBid(), orb.auctionStartingPrice());
        prankAndBid(user, bidAmount);
        assertEq(orb.minimumBid(), bidAmount + orb.auctionMinimumBidStep());
    }
}

contract StartAuctionTest is OrbTestBase {
    function test_startAuctionOnlyOrbCreator() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("Ownable: caller is not the owner");
        orb.startAuction();
        orb.startAuction();
    }

    event AuctionStart(uint256 auctionStartTime, uint256 auctionEndTime);

    function test_startAuctionCorrectly() public {
        vm.expectEmit(true, true, false, false);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration());
        orb.startAuction();
        assertEq(orb.auctionEndTime(), block.timestamp + orb.auctionMinimumDuration());
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
    }

    function test_startAuctionOnlyContractHeld() public {
        orb.workaround_setOrbHolder(address(0xBEEF));
        vm.expectRevert(IOrb.ContractDoesNotHoldOrb.selector);
        orb.startAuction();
        orb.workaround_setOrbHolder(address(orb));
        vm.expectEmit(true, true, false, false);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration());
        orb.startAuction();
    }

    function test_startAuctionNotDuringAuction() public {
        assertEq(orb.auctionEndTime(), 0);
        vm.expectEmit(true, true, false, false);
        emit AuctionStart(block.timestamp, block.timestamp + orb.auctionMinimumDuration());
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
        uint256 amount = orb.minimumBid();
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
        uint256 amount = orb.minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientBid.selector, amount, orb.minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);

        // Add back + 1 to amount
        amount++;
        // will not revert
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);
        assertEq(orb.leadingBid(), amount);

        // minimum bid will be the leading bid + MINIMUM_BID_STEP
        amount = orb.minimumBid() - 1;
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientBid.selector, amount, orb.minimumBid()));
        vm.prank(user);
        orb.bid{value: amount}(amount, amount);
    }

    function test_bidRevertsIfLtFundsRequired() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
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
        uint256 amount = orb.minimumBid();
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

    event AuctionBid(address indexed bidder, uint256 bid);

    function test_bidSetsCorrectState() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        uint256 funds = fundsRequiredToBidOneYear(amount);
        assertEq(orb.leadingBid(), 0 ether);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.fundsOf(user), 0);
        assertEq(address(orb).balance, 0);
        uint256 auctionEndTime = orb.auctionEndTime();

        vm.expectEmit(true, false, false, true);
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

    event AuctionFinalization(address indexed winner, uint256 winningBid);

    function testFuzz_bidSetsCorrectState(address[16] memory bidders, uint128[16] memory amounts) public {
        orb.startAuction();
        uint256 contractBalance;
        for (uint256 i = 1; i < 16; i++) {
            uint256 amount = bound(amounts[i], orb.minimumBid(), orb.minimumBid() + 1_000_000_000);
            address bidder = bidders[i];
            vm.assume(bidder != address(0) && bidder != address(orb) && bidder != beneficiary);

            uint256 funds = fundsRequiredToBidOneYear(amount);

            fundsOfUser[bidder] += funds;

            vm.expectEmit(true, false, false, true);
            emit AuctionBid(bidder, amount);
            prankAndBid(bidder, amount);
            contractBalance += funds;

            assertEq(orb.leadingBid(), amount);
            assertEq(orb.leadingBidder(), bidder);
            assertEq(orb.price(), amount);
            assertEq(orb.fundsOf(bidder), fundsOfUser[bidder]);
            assertEq(address(orb).balance, contractBalance);
        }
        vm.expectEmit(true, false, false, true);
        emit AuctionFinalization(orb.leadingBidder(), orb.leadingBid());
        vm.warp(orb.auctionEndTime() + 1);
        orb.finalizeAuction();
    }

    function test_bidExtendsAuction() public {
        assertEq(orb.auctionEndTime(), 0);
        orb.startAuction();
        uint256 amount = orb.minimumBid();
        // auctionEndTime = block.timestamp + auctionMinimumDuration
        uint256 auctionEndTime = orb.auctionEndTime();
        // set block.timestamp to auctionEndTime - auctionBidExtension
        vm.warp(auctionEndTime - orb.auctionBidExtension());
        prankAndBid(user, amount);
        // didn't change because block.timestamp + auctionBidExtension = auctionEndTime
        assertEq(orb.auctionEndTime(), auctionEndTime);

        vm.warp(auctionEndTime - orb.auctionBidExtension() + 50);
        amount = orb.minimumBid();
        prankAndBid(user, amount);
        // change because block.timestamp + auctionBidExtension + 50 >  auctionEndTime
        assertEq(orb.auctionEndTime(), auctionEndTime + 50);
    }
}

contract FinalizeAuctionTest is OrbTestBase {
    event AuctionFinalization(address indexed winner, uint256 winningBid);

    function test_finalizeAuctionRevertsDuringAuction() public {
        orb.startAuction();
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.finalizeAuction();

        vm.warp(orb.auctionEndTime() + 1);
        vm.expectEmit(true, false, false, true);
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
        vm.expectEmit(true, false, false, true);
        emit AuctionFinalization(address(0), 0);
        orb.finalizeAuction();
        assertEq(orb.auctionEndTime(), 0);
        assertEq(orb.leadingBid(), 0);
        assertEq(orb.leadingBidder(), address(0));
        assertEq(orb.price(), 0);
    }

    event PriceUpdate(uint256 previousPrice, uint256 newPrice);

    function test_finalizeAuctionWithWinner() public {
        orb.startAuction();
        uint256 amount = orb.minimumBid();
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

        vm.expectEmit(true, false, false, true);
        emit AuctionFinalization(user, amount);
        vm.expectEmit(false, false, false, true);
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
        assertEq(orb.ownerOf(orb.tokenId()), user);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(orb.lastInvocationTime(), block.timestamp - orb.cooldown());
        assertEq(orb.fundsOf(user), funds - amount);
        assertEq(orb.price(), amount);
    }
}

contract ListingTest is OrbTestBase {
    function test_revertsIfHeldByUser() public {
        makeHolderAndWarp(user, 1 ether);
        vm.expectRevert(IOrb.ContractDoesNotHoldOrb.selector);
        orb.listWithPrice(1 ether);
    }

    function test_revertsIfAlreadyHeldByCreator() public {
        makeHolderAndWarp(owner, 1 ether);
        vm.expectRevert(IOrb.ContractDoesNotHoldOrb.selector);
        orb.listWithPrice(1 ether);
    }

    function test_revertsIfAuctionStarted() public {
        orb.startAuction();
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.listWithPrice(1 ether);

        vm.warp(orb.auctionEndTime() + 1);
        assertFalse(orb.auctionRunning());
        vm.expectRevert(IOrb.AuctionRunning.selector);
        orb.listWithPrice(1 ether);
    }

    function test_revertsIfCalledByUser() public {
        makeHolderAndWarp(user, 1 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(user);
        orb.listWithPrice(1 ether);
    }

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event PriceUpdate(uint256 previousPrice, uint256 newPrice);

    function test_succeedsCorrectly() public {
        uint256 listingPrice = 1 ether;
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(orb), owner, orb.tokenId());
        vm.expectEmit(false, false, false, true);
        emit PriceUpdate(0, listingPrice);
        orb.listWithPrice(listingPrice);
        assertEq(orb.price(), listingPrice);
        assertEq(orb.ownerOf(orb.tokenId()), owner);
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

        // One day has passed since the Orb holder got the orb
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

        // One day has passed since the Orb holder got the Orb
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
    event Deposit(address indexed depositor, uint256 amount);

    function test_depositRandomUser() public {
        assertEq(orb.fundsOf(user), 0);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user, 1 ether);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user), 1 ether);
    }

    function testFuzz_depositRandomUser(uint256 amount) public {
        assertEq(orb.fundsOf(user), 0);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user, amount);
        vm.deal(user, amount);
        vm.prank(user);
        orb.deposit{value: amount}();
        assertEq(orb.fundsOf(user), amount);
    }

    function test_depositHolderSolvent() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        uint256 depositAmount = 2 ether;
        makeHolderAndWarp(user, bidAmount);
        // User bids 1 ether, but deposit enough funds
        // to cover the tax for a year, according to
        // fundsRequiredToBidOneYear(bidAmount)
        uint256 funds = orb.fundsOf(user);
        vm.expectEmit(true, false, false, true);
        // deposit 1 ether
        emit Deposit(user, depositAmount);
        vm.prank(user);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), funds + depositAmount);
    }

    function testFuzz_depositHolderSolvent(uint256 bidAmount, uint256 depositAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, 0.1 ether, orb.workaround_maximumPrice());
        depositAmount = bound(depositAmount, 0.1 ether, orb.workaround_maximumPrice());
        makeHolderAndWarp(user, bidAmount);
        // User bids 1 ether, but deposit enough funds
        // to cover the tax for a year, according to
        // fundsRequiredToBidOneYear(bidAmount)
        uint256 funds = orb.fundsOf(user);
        vm.expectEmit(true, false, false, true);
        // deposit 1 ether
        emit Deposit(user, depositAmount);
        vm.prank(user);
        vm.deal(user, depositAmount);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), funds + depositAmount);
    }

    function test_depositRevertsifHolderInsolvent() public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        uint256 bidAmount = 1 ether;
        makeHolderAndWarp(user, bidAmount);

        // let's make the user insolvent
        // fundsRequiredToBidOneYear(bidAmount) ensures enough
        // ether for 1 year, not two
        vm.warp(block.timestamp + 731 days);

        // if a random user deposits, it should work fine
        vm.prank(user2);
        orb.deposit{value: 1 ether}();
        assertEq(orb.fundsOf(user2), 1 ether);

        // if the insolvent holder deposits, it should not work
        vm.expectRevert(IOrb.HolderInsolvent.selector);
        vm.prank(user);
        orb.deposit{value: 1 ether}();
    }
}

contract WithdrawTest is OrbTestBase {
    event Withdrawal(address indexed recipient, uint256 amount);

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

    event Settlement(address indexed holder, address indexed beneficiary, uint256 amount);

    function test_withdrawSettlesFirstIfHolder() public {
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

        vm.expectEmit(true, true, false, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);

        vm.prank(user);
        orb.withdraw(withdrawAmount);

        assertEq(orb.fundsOf(user), userEffective - withdrawAmount);
        assertEq(orb.fundsOf(beneficiary), beneficiaryEffective);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(user.balance, initialBalance + withdrawAmount);

        // move ahead 10 days;
        vm.warp(block.timestamp + 10 days);

        // not holder
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
        vm.expectEmit(true, true, false, true);
        emit Settlement(user, beneficiary, transferableToBeneficiary);

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(beneficiary, beneficiaryFunds + transferableToBeneficiary);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(user), userEffective);
        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(beneficiary.balance, initialBalance + beneficiaryEffective);
    }

    function test_withdrawAllForBeneficiaryWhenContractOwned() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish();

        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 initialBalance = beneficiary.balance;
        uint256 settlementTime = block.timestamp;

        vm.warp(block.timestamp + 30 days);

        // expectNotEmit Settlement
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(beneficiary, beneficiaryFunds);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), settlementTime);
        assertEq(beneficiary.balance, initialBalance + beneficiaryFunds);
    }

    function test_withdrawAllForBeneficiaryWhenCreatorOwned() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(user);
        orb.relinquish();
        vm.prank(owner);
        orb.listWithPrice(1 ether);

        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 initialBalance = beneficiary.balance;

        vm.warp(block.timestamp + 30 days);

        vm.expectEmit(true, false, false, true);
        emit Withdrawal(beneficiary, beneficiaryFunds);
        orb.withdrawAllForBeneficiary();

        assertEq(orb.fundsOf(beneficiary), 0);
        assertEq(orb.lastSettlementTime(), block.timestamp);
        assertEq(beneficiary.balance, initialBalance + beneficiaryFunds);
    }

    function testFuzz_withdrawSettlesFirstIfHolder(uint256 bidAmount, uint256 withdrawAmount) public {
        assertEq(orb.fundsOf(user), 0);
        // winning bid  = 1 ether
        bidAmount = bound(bidAmount, orb.auctionStartingPrice(), orb.workaround_maximumPrice());
        makeHolderAndWarp(user, bidAmount);

        // beneficiaryEffective = beneficiaryFunds + transferableToBeneficiary
        // userEffective = userFunds - transferableToBeneficiary
        uint256 beneficiaryFunds = orb.fundsOf(beneficiary);
        uint256 userEffective = effectiveFundsOf(user);
        uint256 beneficiaryEffective = effectiveFundsOf(beneficiary);
        uint256 transferableToBeneficiary = beneficiaryEffective - beneficiaryFunds;
        uint256 initialBalance = user.balance;

        vm.expectEmit(true, true, false, true);
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
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(user, 1 ether);
        orb.withdraw(1 ether);
        assertEq(orb.fundsOf(user), 0);
    }
}

contract SettleTest is OrbTestBase {
    event Settlement(address indexed holder, address indexed beneficiary, uint256 amount);

    function test_settleOnlyIfHolderHeld() public {
        vm.expectRevert(IOrb.ContractHoldsOrb.selector);
        orb.settle();
        assertEq(orb.lastSettlementTime(), 0);
        makeHolderAndWarp(user, 1 ether);
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
        makeHolderAndWarp(user, amount);

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

contract HolderSolventTest is OrbTestBase {
    function test_holderSolventCorrectIfNotOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.lastSettlementTime(), 0);
        // it warps 30 days by default
        makeHolderAndWarp(user, 1 ether);
        assert(orb.holderSolvent());
        vm.warp(block.timestamp + 700 days);
        assertFalse(orb.holderSolvent());
    }

    function test_holderSolventCorrectIfOwner() public {
        assertEq(orb.fundsOf(user), 0);
        assertEq(orb.fundsOf(owner), 0);
        assertEq(orb.lastSettlementTime(), 0);
        assert(orb.holderSolvent());
        vm.warp(block.timestamp + 4885828483 days);
        assert(orb.holderSolvent());
    }
}

contract OwedSinceLastSettlementTest is OrbTestBase {
    function test_owedSinceLastSettlementCorrectMath() public {
        // _lastSettlementTime = 0
        // secondsSinceLastSettlement = block.timestamp - _lastSettlementTime
        // HOLDER_TAX_NUMERATOR = 1_000
        // feeDenominator = 10_000
        // holderTaxPeriod  = 365 days = 31_536_000 seconds
        // owed = _price * HOLDER_TAX_NUMERATOR * secondsSinceLastSettlement)
        // / (holderTaxPeriod * feeDenominator);
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
    function test_setPriceRevertsIfNotHolder() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.NotHolder.selector);
        vm.prank(user2);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 10 ether);

        vm.prank(user);
        orb.setPrice(1 ether);
        assertEq(orb.price(), 1 ether);
    }

    function test_setPriceRevertsIfHolderInsolvent() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 600 days);
        vm.startPrank(user);
        vm.expectRevert(IOrb.HolderInsolvent.selector);
        orb.setPrice(1 ether);

        // As the user can't deposit funds to become solvent again
        // we modify a variable to trick the contract
        orb.workaround_setLastSettlementTime(block.timestamp);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
    }

    function test_setPriceSettlesBefore() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.prank(user);
        orb.setPrice(2 ether);
        assertEq(orb.price(), 2 ether);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event PriceUpdate(uint256 previousPrice, uint256 newPrice);

    function test_setPriceRevertsIfMaxPrice() public {
        uint256 maxPrice = orb.workaround_maximumPrice();
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InvalidNewPrice.selector, maxPrice + 1));
        orb.setPrice(maxPrice + 1);

        vm.expectEmit(false, false, false, true);
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

    function test_revertsIfHolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user2);
        vm.expectRevert(IOrb.HolderInsolvent.selector);
        orb.purchase(100, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_purchaseSettlesFirst() public {
        makeHolderAndWarp(user, 1 ether);
        // after making `user` the current holder of the Orb, `makeHolderAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user2);
        orb.purchase{value: 1.1 ether}(2 ether, 1 ether, 10_00, 10_00, 7 days, 280);
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    function test_revertsIfBeneficiary() public {
        makeHolderAndWarp(user, 1 ether);
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
        makeHolderAndWarp(user, 1 ether);
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

    function test_revertsIfIfAlreadyHolder() public {
        makeHolderAndWarp(user, 1 ether);
        vm.expectRevert(IOrb.AlreadyHolder.selector);
        vm.prank(user);
        orb.purchase{value: 1.1 ether}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfInsufficientFunds() public {
        makeHolderAndWarp(user, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InsufficientFunds.selector, 1 ether - 1, 1 ether));
        vm.prank(user2);
        orb.purchase{value: 1 ether - 1}(3 ether, 1 ether, 10_00, 10_00, 7 days, 280);
    }

    function test_revertsIfPurchasingAfterSetPrice() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(user);
        orb.setPrice(0);
        vm.expectRevert(abi.encodeWithSelector(IOrb.PurchasingNotPermitted.selector));
        vm.prank(user2);
        orb.purchase(1 ether, 0, 10_00, 10_00, 7 days, 280);
    }

    event Purchase(address indexed seller, address indexed buyer, uint256 price);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event PriceUpdate(uint256 previousPrice, uint256 newPrice);
    event Settlement(address indexed holder, address indexed beneficiary, uint256 amount);

    function test_beneficiaryAllProceedsIfOwnerSells() public {
        uint256 bidAmount = 1 ether;
        uint256 newPrice = 3 ether;
        uint256 purchaseAmount = bidAmount / 2;
        uint256 depositAmount = bidAmount / 2;
        // bidAmount will be the `_price` of the Orb
        makeHolderAndWarp(owner, bidAmount);
        orb.settle();
        vm.warp(block.timestamp + 1 days);
        uint256 ownerBefore = orb.fundsOf(owner);
        uint256 beneficiaryBefore = orb.fundsOf(beneficiary);
        uint256 userBefore = orb.fundsOf(user);
        vm.startPrank(user);
        orb.deposit{value: depositAmount}();
        assertEq(orb.fundsOf(user), userBefore + depositAmount);
        vm.expectEmit(true, true, false, false);
        emit Purchase(owner, user, bidAmount);
        vm.expectEmit(true, true, true, false);
        emit Transfer(owner, user, orb.tokenId());
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
        assertEq(orb.holderSolvent(), true);
    }

    function test_succeedsCorrectly() public {
        uint256 bidAmount = 1 ether;
        uint256 newPrice = 3 ether;
        uint256 expectedSettlement = bidAmount * orb.royaltyNumerator() / orb.feeDenominator();
        uint256 purchaseAmount = bidAmount / 2;
        uint256 depositAmount = bidAmount / 2;
        // bidAmount will be the `_price` of the Orb
        makeHolderAndWarp(user, bidAmount);
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
        vm.expectEmit(true, true, false, true);
        // 1 year has passed since the last settlement
        emit Settlement(user, beneficiary, expectedSettlement);
        vm.expectEmit(false, false, false, true);
        emit PriceUpdate(bidAmount, newPrice);
        vm.expectEmit(true, true, false, true);
        emit Purchase(user, user2, bidAmount);
        vm.expectEmit(true, true, true, false);
        emit Transfer(user, user2, orb.tokenId());
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
        makeHolderAndWarp(user, bidAmount);
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
        vm.expectEmit(true, true, false, true);
        // 1 year has passed since the last settlement
        emit Settlement(user, beneficiary, expectedSettlement);
        vm.expectEmit(false, false, false, true);
        emit PriceUpdate(bidAmount, newPrice);
        vm.expectEmit(true, true, false, true);
        emit Purchase(user, user2, bidAmount);
        vm.expectEmit(true, true, true, false);
        emit Transfer(user, user2, orb.tokenId());
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
    function test_revertsIfNotHolder() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.NotHolder.selector);
        vm.prank(user2);
        orb.relinquish();

        vm.prank(user);
        orb.relinquish();
        assertEq(orb.ownerOf(orb.tokenId()), address(orb));
    }

    function test_revertsIfHolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        vm.warp(block.timestamp + 1300 days);
        vm.prank(user);
        vm.expectRevert(IOrb.HolderInsolvent.selector);
        orb.relinquish();
        vm.warp(block.timestamp - 1300 days);
        vm.prank(user);
        orb.relinquish();
        assertEq(orb.ownerOf(orb.tokenId()), address(orb));
    }

    function test_settlesFirst() public {
        makeHolderAndWarp(user, 1 ether);
        // after making `user` the current holder of the Orb, `makeHolderAndWarp(user, )` warps 30 days into the future
        assertEq(orb.lastSettlementTime(), block.timestamp - 30 days);
        vm.prank(user);
        orb.relinquish();
        assertEq(orb.lastSettlementTime(), block.timestamp);
    }

    event Relinquishment(address indexed formerHolder);
    event Withdrawal(address indexed recipient, uint256 amount);

    function test_succeedsCorrectly() public {
        makeHolderAndWarp(user, 1 ether);
        vm.prank(user);
        assertEq(orb.ownerOf(orb.tokenId()), user);
        vm.expectEmit(true, false, false, false);
        emit Relinquishment(user);
        vm.expectEmit(true, false, false, true);
        uint256 effectiveFunds = effectiveFundsOf(user);
        emit Withdrawal(user, effectiveFunds);
        vm.prank(user);
        orb.relinquish();
        assertEq(orb.ownerOf(orb.tokenId()), address(orb));
        assertEq(orb.price(), 0);
    }
}

contract ForecloseTest is OrbTestBase {
    function test_revertsIfNotHolderHeld() public {
        vm.expectRevert(IOrb.ContractHoldsOrb.selector);
        vm.prank(user2);
        orb.foreclose();

        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 100000 days);
        vm.prank(user2);
        orb.foreclose();
        assertEq(orb.ownerOf(orb.tokenId()), address(orb));
    }

    event Foreclosure(address indexed formerHolder);

    function test_revertsifHolderSolvent() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.expectRevert(IOrb.HolderSolvent.selector);
        orb.foreclose();
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, false, false, false);
        emit Foreclosure(user);
        orb.foreclose();
    }

    function test_succeeds() public {
        uint256 leadingBid = 10 ether;
        makeHolderAndWarp(user, leadingBid);
        vm.warp(block.timestamp + 10000 days);
        vm.expectEmit(true, false, false, false);
        emit Foreclosure(user);
        assertEq(orb.ownerOf(orb.tokenId()), user);
        orb.foreclose();
        assertEq(orb.ownerOf(orb.tokenId()), address(orb));
        assertEq(orb.price(), 0);
    }
}

contract InvokeWithCleartextTest is OrbTestBase {
    event Invocation(address indexed invoker, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);
    event CleartextRecording(uint256 indexed invocationId, string cleartext);

    function test_revertsIfLongLength() public {
        uint256 max = orb.cleartextMaximumLength();
        string memory text =
            "asfsafsfsafsafasdfasfdsakfjdsakfjasdlkfajsdlfsdlfkasdfjdjasfhasdljhfdaslkfjsda;kfjasdklfjasdklfjasd;ladlkfjasdfad;flksadjf;lkasdjf;lsadsdlsdlkfjas;dlkfjas;dlkfjsad;lkfjsad;lda;lkfj;kasjf;klsadjf;lsadsdlkfjasd;lkfjsad;lfkajsd;flkasdjf;lsdkfjas;lfkasdflkasdf;laskfj;asldkfjsad;lfs;lf;flksajf;lk"; // solhint-disable-line
        uint256 length = bytes(text).length;
        vm.expectRevert(abi.encodeWithSelector(IOrb.CleartextTooLong.selector, length, max));
        orb.invokeWithCleartext(text);
    }

    function test_callsInvokeWithHashCorrectly() public {
        string memory text = "fjasdklfjasdklfjasdasdffakfjsad;lfs;lf;flksajf;lk";
        makeHolderAndWarp(user, 1 ether);
        vm.expectEmit(true, true, false, true);
        emit Invocation(user, 1, keccak256(abi.encodePacked(text)), block.timestamp);
        vm.expectEmit(true, false, false, true);
        emit CleartextRecording(1, text);
        vm.prank(user);
        orb.invokeWithCleartext(text);
    }
}

contract InvokeWthHashTest is OrbTestBase {
    event Invocation(address indexed invoker, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);

    function test_revertWhen_NotHolder() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.prank(user2);
        vm.expectRevert(IOrb.NotHolder.selector);
        orb.invokeWithHash(hash);

        vm.expectEmit(true, false, false, true);
        emit Invocation(user, 1, hash, block.timestamp);
        vm.prank(user);
        orb.invokeWithHash(hash);
    }

    function test_revertWhen_HolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(IOrb.HolderInsolvent.selector);
        orb.invokeWithHash(hash);
    }

    function test_revertWhen_CooldownIncomplete() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.startPrank(user);
        orb.invokeWithHash(hash);
        (bytes32 invocationHash1, uint256 invocationTimestamp1) = orb.invocations(1);
        assertEq(invocationHash1, hash);
        assertEq(invocationTimestamp1, block.timestamp);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrb.CooldownIncomplete.selector, block.timestamp - 1 days + orb.cooldown() - block.timestamp
            )
        );
        orb.invokeWithHash(hash);
        (bytes32 invocationHash2, uint256 invocationTimestamp2) = orb.invocations(2);
        assertEq(invocationHash2, bytes32(0));
        assertEq(invocationTimestamp2, 0);
        vm.warp(block.timestamp + orb.cooldown() - 1 days + 1);
        orb.invokeWithHash(hash);
        (bytes32 invocationHash3, uint256 invocationTimestamp3) = orb.invocations(2);
        assertEq(invocationHash3, hash);
        assertEq(invocationTimestamp3, block.timestamp);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        bytes32 hash = "asdfsaf";
        vm.startPrank(user);
        vm.expectEmit(true, true, false, true);
        emit Invocation(user, 1, hash, block.timestamp);
        orb.invokeWithHash(hash);
        (bytes32 invocationHash, uint256 invocationTimestamp) = orb.invocations(1);
        assertEq(invocationHash, hash);
        assertEq(invocationTimestamp, block.timestamp);
        assertEq(orb.lastInvocationTime(), block.timestamp);
        assertEq(orb.invocationCount(), 1);
    }
}

contract RespondTest is OrbTestBase {
    event Response(address indexed responder, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);

    function test_revertWhen_notOwner() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));

        vm.expectRevert("Ownable: caller is not the owner");
        orb.respond(1, response);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Response(owner, 1, response, block.timestamp);
        orb.respond(1, response);
    }

    function test_revertWhen_invocationIdIncorrect() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InvocationNotFound.selector, 2));
        orb.respond(2, response);

        vm.prank(owner);
        orb.respond(1, response);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IOrb.InvocationNotFound.selector, 0));
        orb.respond(0, response);
    }

    function test_revertWhen_responseAlreadyExists() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.stopPrank();

        vm.startPrank(owner);
        orb.respond(1, response);
        vm.expectRevert(abi.encodeWithSelector(IOrb.ResponseExists.selector, 1));
        orb.respond(1, response);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.startPrank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.stopPrank();

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Response(owner, 1, response, block.timestamp);
        orb.respond(1, response);
        (bytes32 hash, uint256 time) = orb.responses(1);
        assertEq(hash, response);
        assertEq(time, block.timestamp);
    }
}

contract FlagResponseTest is OrbTestBase {
    event ResponseFlagging(address indexed flagger, uint256 indexed invocationId);

    function test_revertWhen_NotHolder() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(1, response);
        vm.prank(user2);
        vm.expectRevert(IOrb.NotHolder.selector);
        orb.flagResponse(1);

        vm.prank(user);
        orb.flagResponse(1);
    }

    function test_revertWhen_HolderInsolvent() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(1, response);
        vm.warp(block.timestamp + 13130000 days);
        vm.prank(user);
        vm.expectRevert(IOrb.HolderInsolvent.selector);
        orb.flagResponse(1);

        vm.warp(block.timestamp - 13130000 days);
        vm.prank(user);
        orb.flagResponse(1);
    }

    function test_revertWhen_ResponseNotExist() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(1, response);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrb.ResponseNotFound.selector, 188));
        orb.flagResponse(188);

        orb.flagResponse(1);
    }

    function test_revertWhen_outsideFlaggingPeriod() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(1, response);

        vm.warp(block.timestamp + 100 days);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IOrb.FlaggingPeriodExpired.selector, 1, 100 days, orb.cooldown()));
        orb.flagResponse(1);

        vm.warp(block.timestamp - (100 days - orb.cooldown()));
        orb.flagResponse(1);
    }

    function test_revertWhen_flaggingTwice() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(1, response);

        vm.startPrank(user);
        orb.flagResponse(1);

        vm.expectRevert(abi.encodeWithSelector(IOrb.ResponseAlreadyFlagged.selector, 1));
        orb.flagResponse(1);
    }

    function test_revertWhen_responseToPreviousHolder() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(1, response);

        vm.startPrank(user2);
        orb.purchase{value: 3 ether}(2 ether, 1 ether, 10_00, 10_00, 7 days, 280);
        vm.expectRevert(
            abi.encodeWithSelector(IOrb.FlaggingPeriodExpired.selector, 1, orb.holderReceiveTime(), block.timestamp)
        );
        orb.flagResponse(1);

        vm.warp(block.timestamp + orb.cooldown());
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.stopPrank();
        vm.prank(owner);
        orb.respond(2, response);
        vm.prank(user2);
        orb.flagResponse(2);
    }

    function test_success() public {
        makeHolderAndWarp(user, 1 ether);
        string memory cleartext = "this is a cleartext";
        bytes32 response = "response hash";
        vm.prank(user);
        orb.invokeWithHash(keccak256(bytes(cleartext)));
        vm.prank(owner);
        orb.respond(1, response);
        vm.prank(user);
        assertEq(orb.responseFlagged(1), false);
        assertEq(orb.flaggedResponsesCount(), 0);
        vm.expectEmit(true, false, false, true);
        emit ResponseFlagging(user, 1);
        vm.prank(user);
        orb.flagResponse(1);
        assertEq(orb.responseFlagged(1), true);
        assertEq(orb.flaggedResponsesCount(), 1);
    }
}
