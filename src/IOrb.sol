// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IOrb is IERC165 {
    event Creation(bytes32 oathHash, uint256 honoredUntil);

    // Auction Events
    event AuctionStart(uint256 auctionStartTime, uint256 auctionEndTime);
    event AuctionBid(address indexed bidder, uint256 bid);
    event AuctionExtension(uint256 newAuctionEndTime);
    event AuctionFinalization(address indexed winner, uint256 winningBid);

    // Fund Management, Holding and Purchasing Events
    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);
    event Settlement(address indexed holder, address indexed beneficiary, uint256 amount);
    event PriceUpdate(uint256 previousPrice, uint256 newPrice);
    event Purchase(address indexed seller, address indexed buyer, uint256 price);
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

    // ERC-721 Errors
    error TransferringNotSupported();

    // Authorization Errors
    error AlreadyHolder();
    error NotHolder();
    error ContractHoldsOrb();
    error ContractDoesNotHoldOrb();
    error CreatorDoesNotControlOrb();
    error BeneficiaryDisallowed();

    // Funds-Related Authorization Errors
    error HolderSolvent();
    error HolderInsolvent();
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);

    // Auction Errors
    error AuctionNotRunning();
    error AuctionRunning();
    error AuctionNotStarted();
    error NotPermittedForLeadingBidder();
    error InsufficientBid(uint256 bidProvided, uint256 bidRequired);

    // Purchasing Errors
    error CurrentPriceIncorrect(uint256 priceProvided, uint256 currentPrice);
    error PurchasingNotPermitted();
    error InvalidNewPrice(uint256 priceProvided);

    // Invoking and Responding Errors
    error CooldownIncomplete(uint256 timeRemaining);
    error CleartextTooLong(uint256 cleartextLength, uint256 cleartextMaximumLength);
    error CleartextHashMismatch(bytes32 cleartextHash, bytes32 recordedContentHash);
    error CleartextRecordingNotPermitted(uint256 invocationId);
    error InvocationNotFound(uint256 invocationId);
    error ResponseNotFound(uint256 invocationId);
    error ResponseExists(uint256 invocationId);
    error FlaggingPeriodExpired(uint256 invocationId, uint256 currentTimeValue, uint256 timeValueLimit);
    error ResponseAlreadyFlagged(uint256 invocationId);

    // Orb Parameter Errors
    error HonoredUntilNotDecreasable();
    error InvalidAuctionDuration(uint256 auctionDuration);
    error RoyaltyNumeratorExceedsDenominator(uint256 royaltyNumerator, uint256 feeDenominator);
    error InvalidCleartextMaximumLength(uint256 cleartextMaximumLength);

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

    // Auction Functions
    function startAuction() external;
    function bid(uint256 amount, uint256 priceIfWon) external payable;
    function finalizeAuction() external;
    function auctionRunning() external view returns (bool);
    function minimumBid() external view returns (uint256);

    // Fund Management Functions
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function withdrawAll() external;
    function withdrawAllForBeneficiary() external;
    function settle() external;
    function holderSolvent() external view returns (bool);

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
    function recordInvocationCleartext(uint256 invocationId, string memory cleartext) external;
    function respond(uint256 invocationId, bytes32 contentHash) external;
    function flagResponse(uint256 invocationId) external;
}
