// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165Upgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol";

interface IOrb is IERC165Upgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event Creation();

    // Auction Events
    event AuctionStart(
        uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
    );
    event AuctionBid(address indexed bidder, uint256 indexed bid);
    event AuctionExtension(uint256 indexed newAuctionEndTime);
    event AuctionFinalization(address indexed winner, uint256 indexed winningBid);

    // Funding Events
    event Deposit(address indexed depositor, uint256 indexed amount);
    event Withdrawal(address indexed recipient, uint256 indexed amount);
    event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);

    // Purchasing Events
    event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);
    event Purchase(address indexed seller, address indexed buyer, uint256 indexed price);

    // Orb Ownership Events
    event Foreclosure(address indexed formerKeeper);
    event Relinquishment(address indexed formerKeeper);

    // Orb Parameter Events
    event OathSwearing(bytes32 indexed oathHash, uint256 indexed honoredUntil, uint256 indexed responsePeriod);
    event HonoredUntilUpdate(uint256 previousHonoredUntil, uint256 indexed newHonoredUntil);
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
    event FeesUpdate(
        uint256 previousKeeperTaxNumerator,
        uint256 indexed newKeeperTaxNumerator,
        uint256 previousRoyaltyNumerator,
        uint256 indexed newRoyaltyNumerator
    );
    event CooldownUpdate(
        uint256 previousCooldown,
        uint256 indexed newCooldown,
        uint256 previousFlaggingPeriod,
        uint256 indexed newFlaggingPeriod
    );
    event CleartextMaximumLengthUpdate(
        uint256 previousCleartextMaximumLength, uint256 indexed newCleartextMaximumLength
    );

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // ERC-721 Errors
    error NotSupported();
    error NotPermitted();

    // Authorization Errors
    error AlreadyKeeper();
    error NotKeeper();
    error ContractHoldsOrb();
    error ContractDoesNotHoldOrb();
    error CreatorDoesNotControlOrb();
    error NotPermittedForCreator();
    error BeneficiaryDisallowed();

    // Auction Errors
    error AuctionNotRunning();
    error AuctionRunning();
    error AuctionNotStarted();
    error NotPermittedForLeadingBidder();
    error InsufficientBid(uint256 bidProvided, uint256 bidRequired);

    // Funding Errors
    error KeeperSolvent();
    error KeeperInsolvent();
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);

    // Purchasing Errors
    error CurrentValueIncorrect(uint256 valueProvided, uint256 currentValue);
    error PurchasingNotPermitted();
    error InvalidNewPrice(uint256 priceProvided);

    // Orb Parameter Errors
    error HonoredUntilNotDecreasable();
    error InvalidAuctionDuration(uint256 auctionDuration);
    error RoyaltyNumeratorExceedsDenominator(uint256 royaltyNumerator, uint256 feeDenominator);
    error CooldownExceedsMaximumDuration(uint256 cooldown, uint256 cooldownMaximumDuration);
    error InvalidCleartextMaximumLength(uint256 cleartextMaximumLength);

    // Upgradding Errors
    error NoUpgradeRequested();
    error NoNextVersion();

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Auction View Functions
    function auctionEndTime() external view returns (uint256);
    function leadingBidder() external view returns (address);
    function leadingBid() external view returns (uint256);
    function auctionBeneficiary() external view returns (address);

    function auctionStartingPrice() external view returns (uint256);
    function auctionMinimumBidStep() external view returns (uint256);
    function auctionMinimumDuration() external view returns (uint256);
    function auctionKeeperMinimumDuration() external view returns (uint256);
    function auctionBidExtension() external view returns (uint256);

    // Funding View Functions
    function fundsOf(address owner) external view returns (uint256);
    function lastSettlementTime() external view returns (uint256);
    function keeperSolvent() external view returns (bool);

    function keeperTaxNumerator() external view returns (uint256);
    function feeDenominator() external view returns (uint256);
    function keeperTaxPeriod() external view returns (uint256);

    // Purchasing View Functions
    function keeper() external view returns (address);
    function price() external view returns (uint256);
    function keeperReceiveTime() external view returns (uint256);

    function royaltyNumerator() external view returns (uint256);

    // Invoking and Responding View Functions
    function cooldown() external view returns (uint256);
    function flaggingPeriod() external view returns (uint256);
    function lastInvocationTime() external view returns (uint256);
    function setLastInvocationTime(uint256 timestamp) external;

    function cleartextMaximumLength() external view returns (uint256);

    // Orb Parameter View Functions
    function honoredUntil() external view returns (uint256);
    function responsePeriod() external view returns (uint256);
    function beneficiary() external view returns (address);

    // Upgrading View Functions
    function version() external returns (uint256);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function initialize(address beneficiary_, string memory name_, string memory symbol_, string memory tokenURI_)
        external;

    // Auction Functions
    function startAuction() external;
    function bid(uint256 amount, uint256 priceIfWon) external payable;
    function finalizeAuction() external;

    // Funding Functions
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function withdrawAll() external;
    function withdrawAllForBeneficiary() external;
    function settle() external;

    // Purchasing Functions
    function listWithPrice(uint256 listingPrice) external;
    function setPrice(uint256 newPrice) external;
    function purchase(
        uint256 newPrice,
        uint256 currentPrice,
        uint256 currentKeeperTaxNumerator,
        uint256 currentRoyaltyNumerator,
        uint256 currentCooldown,
        uint256 currentCleartextMaximumLength
    ) external payable;

    // Orb Ownership Functions
    function relinquish(bool withAuction) external;
    function foreclose() external;

    // Orb Parameter Functions
    function swearOath(bytes32 oathHash, uint256 newHonoredUntil, uint256 newResponsePeriod) external;
    function extendHonoredUntil(uint256 newHonoredUntil) external;
    function setTokenURI(string memory newBaseURI) external;
    function setAuctionParameters(
        uint256 newStartingPrice,
        uint256 newMinimumBidStep,
        uint256 newMinimumDuration,
        uint256 newKeeperMinimumDuration,
        uint256 newBidExtension
    ) external;
    function setFees(uint256 newKeeperTaxNumerator, uint256 newRoyaltyNumerator) external;
    function setCooldown(uint256 newCooldown, uint256 newFlaggingPeriod) external;
    function setCleartextMaximumLength(uint256 newCleartextMaximumLength) external;

    // Upgrading Functions
    function requestUpgrade() external;
    function upgradeToNextVersion() external;
}
