// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IOrb is IERC165 {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event Creation(bytes32 oathHash, uint256 honoredUntil);

    // Auction Events
    event AuctionStart(uint256 auctionStartTime, uint256 auctionEndTime);
    event AuctionBid(address indexed bidder, uint256 bid);
    event AuctionExtension(uint256 newAuctionEndTime);
    event AuctionFinalization(address indexed winner, uint256 winningBid);

    // Funding Events
    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);
    event Settlement(address indexed holder, address indexed beneficiary, uint256 amount);

    // Purchasing Errors
    event PriceUpdate(uint256 previousPrice, uint256 newPrice);
    event Purchase(address indexed seller, address indexed buyer, uint256 price);

    // Orb Ownership Functions
    event Foreclosure(address indexed formerHolder);
    event Relinquishment(address indexed formerHolder);

    // Invoking and Responding Events
    event Invocation(address indexed invoker, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);
    event Response(address indexed responder, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);
    event CleartextRecording(uint256 indexed invocationId, string cleartext);
    event ResponseFlagging(address indexed flagger, uint256 indexed invocationId);

    // Orb Parameter Events
    event OathSwearing(bytes32 oathHash, uint256 honoredUntil);
    event HonoredUntilUpdate(uint256 previousHonoredUntil, uint256 newHonoredUntil);
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
    event FeesUpdate(
        uint256 previousHolderTaxNumerator,
        uint256 newHolderTaxNumerator,
        uint256 previousRoyaltyNumerator,
        uint256 newRoyaltyNumerator
    );
    event CooldownUpdate(uint256 previousCooldown, uint256 newCooldown);
    event CleartextMaximumLengthUpdate(uint256 previousCleartextMaximumLength, uint256 newCleartextMaximumLength);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // ERC-721 Errors
    error TransferringNotSupported();

    // Authorization Errors
    error AlreadyHolder();
    error NotHolder();
    error ContractHoldsOrb();
    error ContractDoesNotHoldOrb();
    error CreatorDoesNotControlOrb();
    error BeneficiaryDisallowed();

    // Auction Errors
    error AuctionNotRunning();
    error AuctionRunning();
    error AuctionNotStarted();
    error NotPermittedForLeadingBidder();
    error InsufficientBid(uint256 bidProvided, uint256 bidRequired);

    // Funding Errors
    error HolderSolvent();
    error HolderInsolvent();
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);

    // Purchasing Errors
    error CurrentPriceIncorrect(uint256 priceProvided, uint256 currentPrice);
    error PurchasingNotPermitted();
    error InvalidNewPrice(uint256 priceProvided);

    // Invoking and Responding Errors
    error CooldownIncomplete(uint256 timeRemaining);
    error CleartextTooLong(uint256 cleartextLength, uint256 cleartextMaximumLength);
    error InvocationNotFound(uint256 invocationId);
    error ResponseNotFound(uint256 invocationId);
    error ResponseExists(uint256 invocationId);
    error FlaggingPeriodExpired(uint256 invocationId, uint256 currentTimeValue, uint256 timeValueLimit);
    error ResponseAlreadyFlagged(uint256 invocationId);

    // Orb Parameter Errors
    error HonoredUntilNotDecreasable();
    error InvalidAuctionDuration(uint256 auctionDuration);
    error RoyaltyNumeratorExceedsDenominator(uint256 royaltyNumerator, uint256 feeDenominator);
    error CooldownExceedsMaximumDuration(uint256 cooldown, uint256 cooldownMaximumDuration);
    error InvalidCleartextMaximumLength(uint256 cleartextMaximumLength);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // ERC-721 View Functions
    function tokenId() external view returns (uint256);

    // Auction View Functions
    function auctionEndTime() external view returns (uint256);
    function auctionRunning() external view returns (bool);
    function leadingBidder() external view returns (address);
    function leadingBid() external view returns (uint256);
    function minimumBid() external view returns (uint256);

    function auctionStartingPrice() external view returns (uint256);
    function auctionMinimumBidStep() external view returns (uint256);
    function auctionMinimumDuration() external view returns (uint256);
    function auctionBidExtension() external view returns (uint256);

    // Funding View Functions
    function fundsOf(address owner) external view returns (uint256);
    function lastSettlementTime() external view returns (uint256);
    function holderSolvent() external view returns (bool);

    function holderTaxNumerator() external view returns (uint256);
    function feeDenominator() external view returns (uint256);
    function holderTaxPeriod() external view returns (uint256);

    // Purchasing View Functions
    function price() external view returns (uint256);
    function holderReceiveTime() external view returns (uint256);

    function royaltyNumerator() external view returns (uint256);

    // Invoking and Responding View Functions
    function invocations(uint256 invocationId) external view returns (bytes32 contentHash, uint256 timestamp);
    function invocationCount() external view returns (uint256);

    function responses(uint256 invocationId) external view returns (bytes32 contentHash, uint256 timestamp);
    function responseFlagged(uint256 invocationId) external view returns (bool);
    function flaggedResponsesCount() external view returns (uint256);

    function cooldown() external view returns (uint256);
    function lastInvocationTime() external view returns (uint256);

    function cleartextMaximumLength() external view returns (uint256);

    // Orb Parameter View Functions
    function honoredUntil() external view returns (uint256);
    function beneficiary() external view returns (address);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

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
    function purchase(uint256 currentPrice, uint256 newPrice) external payable;

    // Orb Ownership Functions
    function relinquish() external;
    function foreclose() external;

    // Invoking and Responding Functions
    function invokeWithCleartext(string memory cleartext) external;
    function invokeWithHash(bytes32 contentHash) external;
    function respond(uint256 invocationId, bytes32 contentHash) external;
    function flagResponse(uint256 invocationId) external;

    // Orb Parameter Functions
    function swearOath(bytes32 oathHash, uint256 newHonoredUntil) external;
    function extendHonoredUntil(uint256 newHonoredUntil) external;
    function setBaseURI(string memory newBaseURI) external;
    function setAuctionParameters(
        uint256 newStartingPrice,
        uint256 newMinimumBidStep,
        uint256 newMinimumDuration,
        uint256 newBidExtension
    ) external;
    function setFees(uint256 newHolderTaxNumerator, uint256 newRoyaltyNumerator) external;
    function setCooldown(uint256 newCooldown) external;
    function setCleartextMaximumLength(uint256 newCleartextMaximumLength) external;
}
