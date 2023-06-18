# IOrb
[Git Source](https://github.com/orbland/orb/blob/b920ffa5c5298491a4db27902136f8424c03170e/src/IOrb.sol)

**Inherits:**
IERC165


## Functions
### tokenId


```solidity
function tokenId() external view returns (uint256);
```

### auctionEndTime


```solidity
function auctionEndTime() external view returns (uint256);
```

### auctionRunning


```solidity
function auctionRunning() external view returns (bool);
```

### leadingBidder


```solidity
function leadingBidder() external view returns (address);
```

### leadingBid


```solidity
function leadingBid() external view returns (uint256);
```

### minimumBid


```solidity
function minimumBid() external view returns (uint256);
```

### auctionStartingPrice


```solidity
function auctionStartingPrice() external view returns (uint256);
```

### auctionMinimumBidStep


```solidity
function auctionMinimumBidStep() external view returns (uint256);
```

### auctionMinimumDuration


```solidity
function auctionMinimumDuration() external view returns (uint256);
```

### auctionBidExtension


```solidity
function auctionBidExtension() external view returns (uint256);
```

### fundsOf


```solidity
function fundsOf(address owner) external view returns (uint256);
```

### lastSettlementTime


```solidity
function lastSettlementTime() external view returns (uint256);
```

### keeperSolvent


```solidity
function keeperSolvent() external view returns (bool);
```

### keeperTaxNumerator


```solidity
function keeperTaxNumerator() external view returns (uint256);
```

### feeDenominator


```solidity
function feeDenominator() external view returns (uint256);
```

### keeperTaxPeriod


```solidity
function keeperTaxPeriod() external view returns (uint256);
```

### price


```solidity
function price() external view returns (uint256);
```

### keeperReceiveTime


```solidity
function keeperReceiveTime() external view returns (uint256);
```

### royaltyNumerator


```solidity
function royaltyNumerator() external view returns (uint256);
```

### invocations


```solidity
function invocations(uint256 invocationId)
    external
    view
    returns (address invoker, bytes32 contentHash, uint256 timestamp);
```

### invocationCount


```solidity
function invocationCount() external view returns (uint256);
```

### responses


```solidity
function responses(uint256 invocationId) external view returns (bytes32 contentHash, uint256 timestamp);
```

### responseFlagged


```solidity
function responseFlagged(uint256 invocationId) external view returns (bool);
```

### flaggedResponsesCount


```solidity
function flaggedResponsesCount() external view returns (uint256);
```

### cooldown


```solidity
function cooldown() external view returns (uint256);
```

### lastInvocationTime


```solidity
function lastInvocationTime() external view returns (uint256);
```

### cleartextMaximumLength


```solidity
function cleartextMaximumLength() external view returns (uint256);
```

### honoredUntil


```solidity
function honoredUntil() external view returns (uint256);
```

### responsePeriod


```solidity
function responsePeriod() external view returns (uint256);
```

### beneficiary


```solidity
function beneficiary() external view returns (address);
```

### startAuction


```solidity
function startAuction() external;
```

### bid


```solidity
function bid(uint256 amount, uint256 priceIfWon) external payable;
```

### finalizeAuction


```solidity
function finalizeAuction() external;
```

### deposit


```solidity
function deposit() external payable;
```

### withdraw


```solidity
function withdraw(uint256 amount) external;
```

### withdrawAll


```solidity
function withdrawAll() external;
```

### withdrawAllForBeneficiary


```solidity
function withdrawAllForBeneficiary() external;
```

### settle


```solidity
function settle() external;
```

### listWithPrice


```solidity
function listWithPrice(uint256 listingPrice) external;
```

### setPrice


```solidity
function setPrice(uint256 newPrice) external;
```

### purchase


```solidity
function purchase(
    uint256 newPrice,
    uint256 currentPrice,
    uint256 currentKeeperTaxNumerator,
    uint256 currentRoyaltyNumerator,
    uint256 currentCooldown,
    uint256 currentCleartextMaximumLength
) external payable;
```

### relinquish


```solidity
function relinquish() external;
```

### foreclose


```solidity
function foreclose() external;
```

### invokeWithCleartext


```solidity
function invokeWithCleartext(string memory cleartext) external;
```

### invokeWithHash


```solidity
function invokeWithHash(bytes32 contentHash) external;
```

### respond


```solidity
function respond(uint256 invocationId, bytes32 contentHash) external;
```

### flagResponse


```solidity
function flagResponse(uint256 invocationId) external;
```

### swearOath


```solidity
function swearOath(bytes32 oathHash, uint256 newHonoredUntil, uint256 newResponsePeriod) external;
```

### extendHonoredUntil


```solidity
function extendHonoredUntil(uint256 newHonoredUntil) external;
```

### setBaseURI


```solidity
function setBaseURI(string memory newBaseURI) external;
```

### setAuctionParameters


```solidity
function setAuctionParameters(
    uint256 newStartingPrice,
    uint256 newMinimumBidStep,
    uint256 newMinimumDuration,
    uint256 newBidExtension
) external;
```

### setFees


```solidity
function setFees(uint256 newKeeperTaxNumerator, uint256 newRoyaltyNumerator) external;
```

### setCooldown


```solidity
function setCooldown(uint256 newCooldown) external;
```

### setCleartextMaximumLength


```solidity
function setCleartextMaximumLength(uint256 newCleartextMaximumLength) external;
```

## Events
### Creation

```solidity
event Creation();
```

### AuctionStart

```solidity
event AuctionStart(uint256 indexed auctionStartTime, uint256 indexed auctionEndTime);
```

### AuctionBid

```solidity
event AuctionBid(address indexed bidder, uint256 indexed bid);
```

### AuctionExtension

```solidity
event AuctionExtension(uint256 indexed newAuctionEndTime);
```

### AuctionFinalization

```solidity
event AuctionFinalization(address indexed winner, uint256 indexed winningBid);
```

### Deposit

```solidity
event Deposit(address indexed depositor, uint256 indexed amount);
```

### Withdrawal

```solidity
event Withdrawal(address indexed recipient, uint256 indexed amount);
```

### Settlement

```solidity
event Settlement(address indexed keeper, address indexed beneficiary, uint256 indexed amount);
```

### PriceUpdate

```solidity
event PriceUpdate(uint256 previousPrice, uint256 indexed newPrice);
```

### Purchase

```solidity
event Purchase(address indexed seller, address indexed buyer, uint256 indexed price);
```

### Foreclosure

```solidity
event Foreclosure(address indexed formerKeeper);
```

### Relinquishment

```solidity
event Relinquishment(address indexed formerKeeper);
```

### Invocation

```solidity
event Invocation(uint256 indexed invocationId, address indexed invoker, uint256 indexed timestamp, bytes32 contentHash);
```

### Response

```solidity
event Response(uint256 indexed invocationId, address indexed responder, uint256 indexed timestamp, bytes32 contentHash);
```

### CleartextRecording

```solidity
event CleartextRecording(uint256 indexed invocationId, string cleartext);
```

### ResponseFlagging

```solidity
event ResponseFlagging(uint256 indexed invocationId, address indexed flagger);
```

### OathSwearing

```solidity
event OathSwearing(bytes32 indexed oathHash, uint256 indexed honoredUntil, uint256 indexed responsePeriod);
```

### HonoredUntilUpdate

```solidity
event HonoredUntilUpdate(uint256 previousHonoredUntil, uint256 indexed newHonoredUntil);
```

### AuctionParametersUpdate

```solidity
event AuctionParametersUpdate(
    uint256 previousStartingPrice,
    uint256 indexed newStartingPrice,
    uint256 previousMinimumBidStep,
    uint256 indexed newMinimumBidStep,
    uint256 previousMinimumDuration,
    uint256 indexed newMinimumDuration,
    uint256 previousBidExtension,
    uint256 newBidExtension
);
```

### FeesUpdate

```solidity
event FeesUpdate(
    uint256 previousKeeperTaxNumerator,
    uint256 indexed newKeeperTaxNumerator,
    uint256 previousRoyaltyNumerator,
    uint256 indexed newRoyaltyNumerator
);
```

### CooldownUpdate

```solidity
event CooldownUpdate(uint256 previousCooldown, uint256 indexed newCooldown);
```

### CleartextMaximumLengthUpdate

```solidity
event CleartextMaximumLengthUpdate(uint256 previousCleartextMaximumLength, uint256 indexed newCleartextMaximumLength);
```

## Errors
### TransferringNotSupported

```solidity
error TransferringNotSupported();
```

### AlreadyKeeper

```solidity
error AlreadyKeeper();
```

### NotKeeper

```solidity
error NotKeeper();
```

### ContractHoldsOrb

```solidity
error ContractHoldsOrb();
```

### ContractDoesNotHoldOrb

```solidity
error ContractDoesNotHoldOrb();
```

### CreatorDoesNotControlOrb

```solidity
error CreatorDoesNotControlOrb();
```

### BeneficiaryDisallowed

```solidity
error BeneficiaryDisallowed();
```

### AuctionNotRunning

```solidity
error AuctionNotRunning();
```

### AuctionRunning

```solidity
error AuctionRunning();
```

### AuctionNotStarted

```solidity
error AuctionNotStarted();
```

### NotPermittedForLeadingBidder

```solidity
error NotPermittedForLeadingBidder();
```

### InsufficientBid

```solidity
error InsufficientBid(uint256 bidProvided, uint256 bidRequired);
```

### KeeperSolvent

```solidity
error KeeperSolvent();
```

### KeeperInsolvent

```solidity
error KeeperInsolvent();
```

### InsufficientFunds

```solidity
error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);
```

### CurrentValueIncorrect

```solidity
error CurrentValueIncorrect(uint256 valueProvided, uint256 currentValue);
```

### PurchasingNotPermitted

```solidity
error PurchasingNotPermitted();
```

### InvalidNewPrice

```solidity
error InvalidNewPrice(uint256 priceProvided);
```

### CooldownIncomplete

```solidity
error CooldownIncomplete(uint256 timeRemaining);
```

### CleartextTooLong

```solidity
error CleartextTooLong(uint256 cleartextLength, uint256 cleartextMaximumLength);
```

### InvocationNotFound

```solidity
error InvocationNotFound(uint256 invocationId);
```

### ResponseNotFound

```solidity
error ResponseNotFound(uint256 invocationId);
```

### ResponseExists

```solidity
error ResponseExists(uint256 invocationId);
```

### FlaggingPeriodExpired

```solidity
error FlaggingPeriodExpired(uint256 invocationId, uint256 currentTimeValue, uint256 timeValueLimit);
```

### ResponseAlreadyFlagged

```solidity
error ResponseAlreadyFlagged(uint256 invocationId);
```

### HonoredUntilNotDecreasable

```solidity
error HonoredUntilNotDecreasable();
```

### InvalidAuctionDuration

```solidity
error InvalidAuctionDuration(uint256 auctionDuration);
```

### RoyaltyNumeratorExceedsDenominator

```solidity
error RoyaltyNumeratorExceedsDenominator(uint256 royaltyNumerator, uint256 feeDenominator);
```

### CooldownExceedsMaximumDuration

```solidity
error CooldownExceedsMaximumDuration(uint256 cooldown, uint256 cooldownMaximumDuration);
```

### InvalidCleartextMaximumLength

```solidity
error InvalidCleartextMaximumLength(uint256 cleartextMaximumLength);
```

