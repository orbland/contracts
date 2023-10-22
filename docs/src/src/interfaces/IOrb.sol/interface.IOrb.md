# IOrb
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/interfaces/IOrb.sol)

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

