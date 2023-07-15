# IOrb
[Git Source](https://github.com/orbland/orb/blob/7955ccc3c983c925780d5ee46f888378f75efa47/src/IOrb.sol)

**Inherits:**
IERC165Upgradeable


## Functions
### auctionEndTime


```solidity
function auctionEndTime() external view returns (uint256);
```

### leadingBidder


```solidity
function leadingBidder() external view returns (address);
```

### leadingBid


```solidity
function leadingBid() external view returns (uint256);
```

### auctionBeneficiary


```solidity
function auctionBeneficiary() external view returns (address);
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

### auctionKeeperMinimumDuration


```solidity
function auctionKeeperMinimumDuration() external view returns (uint256);
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

### keeper


```solidity
function keeper() external view returns (address);
```

### keeperReceiveTime


```solidity
function keeperReceiveTime() external view returns (uint256);
```

### price


```solidity
function price() external view returns (uint256);
```

### royaltyNumerator


```solidity
function royaltyNumerator() external view returns (uint256);
```

### cooldown


```solidity
function cooldown() external view returns (uint256);
```

### flaggingPeriod


```solidity
function flaggingPeriod() external view returns (uint256);
```

### lastInvocationTime


```solidity
function lastInvocationTime() external view returns (uint256);
```

### cleartextMaximumLength


```solidity
function cleartextMaximumLength() external view returns (uint256);
```

### pond


```solidity
function pond() external view returns (address);
```

### creator


```solidity
function creator() external view returns (address);
```

### beneficiary


```solidity
function beneficiary() external view returns (address);
```

### honoredUntil


```solidity
function honoredUntil() external view returns (uint256);
```

### responsePeriod


```solidity
function responsePeriod() external view returns (uint256);
```

### version


```solidity
function version() external view returns (uint256);
```

### requestedUpgradeImplementation


```solidity
function requestedUpgradeImplementation() external view returns (address);
```

### initialize


```solidity
function initialize(address beneficiary_, string memory name_, string memory symbol_, string memory tokenURI_)
    external;
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
function relinquish(bool withAuction) external;
```

### foreclose


```solidity
function foreclose() external;
```

### setLastInvocationTime


```solidity
function setLastInvocationTime(uint256 timestamp) external;
```

### swearOath


```solidity
function swearOath(bytes32 oathHash, uint256 newHonoredUntil, uint256 newResponsePeriod) external;
```

### extendHonoredUntil


```solidity
function extendHonoredUntil(uint256 newHonoredUntil) external;
```

### setTokenURI


```solidity
function setTokenURI(string memory newTokenURI) external;
```

### setAuctionParameters


```solidity
function setAuctionParameters(
    uint256 newStartingPrice,
    uint256 newMinimumBidStep,
    uint256 newMinimumDuration,
    uint256 newKeeperMinimumDuration,
    uint256 newBidExtension
) external;
```

### setFees


```solidity
function setFees(uint256 newKeeperTaxNumerator, uint256 newRoyaltyNumerator) external;
```

### setCooldown


```solidity
function setCooldown(uint256 newCooldown, uint256 newFlaggingPeriod) external;
```

### setCleartextMaximumLength


```solidity
function setCleartextMaximumLength(uint256 newCleartextMaximumLength) external;
```

### requestUpgrade


```solidity
function requestUpgrade(address requestedImplementation) external;
```

### upgradeToNextVersion


```solidity
function upgradeToNextVersion() external;
```

## Events
### Creation

```solidity
event Creation();
```

### AuctionStart

```solidity
event AuctionStart(
    uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
);
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
    uint256 previousKeeperMinimumDuration,
    uint256 newKeeperMinimumDuration,
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
event CooldownUpdate(
    uint256 previousCooldown,
    uint256 indexed newCooldown,
    uint256 previousFlaggingPeriod,
    uint256 indexed newFlaggingPeriod
);
```

### CleartextMaximumLengthUpdate

```solidity
event CleartextMaximumLengthUpdate(uint256 previousCleartextMaximumLength, uint256 indexed newCleartextMaximumLength);
```

### UpgradeRequest

```solidity
event UpgradeRequest(address indexed requestedImplementation);
```

## Errors
### NotSupported

```solidity
error NotSupported();
```

### NotPermitted

```solidity
error NotPermitted();
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

### NoUpgradeRequested

```solidity
error NoUpgradeRequested();
```

### NotNextVersion

```solidity
error NotNextVersion();
```

