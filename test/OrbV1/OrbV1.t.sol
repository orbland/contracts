// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/* solhint-disable no-console */
import {console} from "../../lib/forge-std/src/console.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";
import {ERC1967Proxy} from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PaymentSplitter} from "../../src/CustomPaymentSplitter.sol";
import {OrbHarness} from "./OrbV1Harness.sol";
import {OrbPond} from "../../src/OrbPond.sol";
import {OrbInvocationRegistry} from "../../src/OrbInvocationRegistry.sol";
import {Orb} from "../../src/Orb.sol";
import {OrbTestUpgrade} from "../../src/test-upgrades/OrbTestUpgrade.sol";
import {Orb} from "../../src/Orb.sol";

/* solhint-disable func-name-mixedcase,private-vars-leading-underscore */
contract OrbTestBase is Test {
    PaymentSplitter internal paymentSplitterImplementation;

    OrbInvocationRegistry internal orbInvocationRegistryImplementation;
    OrbInvocationRegistry internal orbInvocationRegistry;

    OrbPond internal orbPondV1Implementation;
    OrbPond internal orbPond;

    OrbHarness internal orbV1Implementation;
    OrbTestUpgrade internal orbTestUpgradeImplementation;
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

        address[] memory beneficiaryPayees = new address[](2);
        uint256[] memory beneficiaryShares = new uint256[](2);
        beneficiaryPayees[0] = address(0xC0FFEE);
        beneficiaryPayees[1] = address(0xFACEB00C);
        beneficiaryShares[0] = 95;
        beneficiaryShares[1] = 5;

        startingBalance = 10_000 ether;
        vm.deal(user, startingBalance);
        vm.deal(user2, startingBalance);

        orbInvocationRegistryImplementation = new OrbInvocationRegistry();
        orbPondV1Implementation = new OrbPond();
        orbV1Implementation = new OrbHarness();
        orbTestUpgradeImplementation = new OrbTestUpgrade();
        paymentSplitterImplementation = new PaymentSplitter();

        ERC1967Proxy orbInvocationRegistryProxy = new ERC1967Proxy(
            address(orbInvocationRegistryImplementation),
            abi.encodeWithSelector(OrbInvocationRegistry.initialize.selector)
        );
        orbInvocationRegistry = OrbInvocationRegistry(address(orbInvocationRegistryProxy));

        ERC1967Proxy orbPondProxy = new ERC1967Proxy(
            address(orbPondV1Implementation),
            abi.encodeWithSelector(
                OrbPond.initialize.selector,
                address(orbInvocationRegistry),
                address(paymentSplitterImplementation)
            )
        );
        bytes memory orbInitializeCalldata = abi.encodeWithSelector(Orb.initialize.selector, address(0), "", "", "");
        OrbPond(address(orbPondProxy)).registerVersion(1, address(orbV1Implementation), orbInitializeCalldata);
        orbPond = OrbPond(address(orbPondProxy));

        vm.expectEmit(true, true, true, true);
        emit Creation();
        orbPond.createOrb(beneficiaryPayees, beneficiaryShares, "Orb", "ORB", "https://static.orb.land/orb/");

        orb = OrbHarness(orbPond.orbs(0));
        beneficiary = orb.beneficiary();

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
        // Note: needs to be updated with every new version
        assertEq(orb.version(), 1);
        assertEq(address(orb), orb.keeper());
        assertFalse(orb.workaround_auctionRunning());
        assertEq(orb.pond(), address(orbPond));
        assertEq(orb.owner(), address(this));
        assertEq(orb.honoredUntil(), 100); // 1_700_000_000
        assertEq(orb.responsePeriod(), 3600);

        assertEq(PaymentSplitter(payable(orb.beneficiary())).totalShares(), 100);
        assertEq(PaymentSplitter(payable(orb.beneficiary())).totalReleased(), 0);
        assertEq(PaymentSplitter(payable(orb.beneficiary())).shares(address(0xC0FFEE)), 95);
        assertEq(PaymentSplitter(payable(orb.beneficiary())).shares(address(0xFACEB00C)), 5);

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
        assertEq(orb.requestedUpgradeImplementation(), address(0));
    }

    function test_constants() public {
        assertEq(orb.feeDenominator(), 100_00);
        assertEq(orb.keeperTaxPeriod(), 365 days);

        assertEq(orb.workaround_maximumPrice(), 2 ** 128);
        assertEq(orb.workaround_cooldownMaximumDuration(), 3650 days);
    }

    function test_revertsInitializer() public {
        vm.expectRevert("Initializable: contract is already initialized");
        orb.initialize(address(0), "", "", "");
    }

    function test_initializerSuccess() public {
        ERC1967Proxy orbProxy = new ERC1967Proxy(
            address(orbV1Implementation), ""
        );
        Orb _orb = Orb(address(orbProxy));
        assertEq(_orb.owner(), address(0));
        _orb.initialize(address(0xC0FFEE), "name", "symbol", "tokenURI");
        assertEq(_orb.owner(), address(this));
    }
}

contract SupportsInterfaceTest is OrbTestBase {
    // Test that the initial state is correct
    function test_supportsInterface() public view {
        // console.logBytes4(type(Orb).interfaceId);
        assert(orb.supportsInterface(0x01ffc9a7)); // ERC165 Interface ID for ERC165
        assert(orb.supportsInterface(0x80ac58cd)); // ERC165 Interface ID for ERC721
        assert(orb.supportsInterface(0x5b5e139f)); // ERC165 Interface ID for ERC721Metadata
        assert(orb.supportsInterface(0x4645e06f)); // ERC165 Interface ID for Orb
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
        vm.expectRevert(Orb.NotSupported.selector);
        orb.approve(address(0), 1);
        vm.expectRevert(Orb.NotSupported.selector);
        orb.setApprovalForAll(address(0), true);
        vm.expectRevert(Orb.NotSupported.selector);
        orb.getApproved(0);
        vm.expectRevert(Orb.NotSupported.selector);
        orb.isApprovedForAll(address(0), owner);
    }

    function test_transfersRevert() public {
        address newOwner = address(0xBEEF);
        uint256 tokenId = 1;
        vm.expectRevert(Orb.NotSupported.selector);
        orb.transferFrom(address(this), newOwner, tokenId);
        vm.expectRevert(Orb.NotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, tokenId);
        vm.expectRevert(Orb.NotSupported.selector);
        orb.safeTransferFrom(address(this), newOwner, tokenId, bytes(""));
    }
}

contract OrbInvocationRegistrySupportTest is OrbTestBase {
    function test_setLastInvocationTime() public {
        assertEq(orb.lastInvocationTime(), 0);
        vm.expectRevert(Orb.NotPermitted.selector);
        orb.setLastInvocationTime(42);
        assertEq(orb.lastInvocationTime(), 0);

        vm.prank(address(orbInvocationRegistry));
        orb.setLastInvocationTime(42);
        assertEq(orb.lastInvocationTime(), 42);
    }
}
