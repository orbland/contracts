# OrbPond
[Git Source](https://github.com/orbland/orb/blob/1444163b9922788790de284c6d2d30eca3e6316e/src/OrbPond.sol)

**Inherits:**
Ownable

**Author:**
Jonas Lekevicius

Orbs come from a Pond. The Pond is used to efficiently create new Orbs, and track "official" Orbs, honered
by the Orb Land system. The Pond is also used to configure the Orbs and transfer ownership to the Orb
creator.

*Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator.*


## State Variables
### orbs
The mapping of Orb ids to Orbs. Increases monotonically.


```solidity
mapping(uint256 => Orb) public orbs;
```


### orbCount
The number of Orbs created so far, used to find the next Orb id.


```solidity
uint256 public orbCount;
```


## Functions
### createOrb

Creates a new Orb, and emits an event with the Orb's address.


```solidity
function createOrb(
    string memory name,
    string memory symbol,
    uint256 tokenId,
    address beneficiary,
    string memory baseURI
) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|         Name of the Orb, used for display purposes. Suggestion: "NameOrb".|
|`symbol`|`string`|       Symbol of the Orb, used for display purposes. Suggestion: "ORB".|
|`tokenId`|`uint256`|      TokenId of the Orb. Only one ERC-721 token will be minted, with this id.|
|`beneficiary`|`address`|  Address of the Orb's beneficiary. See `Orb` contract for more on beneficiary.|
|`baseURI`|`string`|      Initial baseURI of the Orb, used as part of ERC-721 tokenURI.|


### configureOrb

Configures most Orb's parameters in one transaction. Used to initially set up the Orb.


```solidity
function configureOrb(
    uint256 orbId,
    uint256 auctionStartingPrice,
    uint256 auctionMinimumBidStep,
    uint256 auctionMinimumDuration,
    uint256 auctionKeeperMinimumDuration,
    uint256 auctionBidExtension,
    uint256 keeperTaxNumerator,
    uint256 royaltyNumerator,
    uint256 cooldown,
    uint256 flaggingPeriod,
    uint256 cleartextMaximumLength
) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orbId`|`uint256`|                        Id of the Orb to configure.|
|`auctionStartingPrice`|`uint256`|         Starting price of the Orb's auction.|
|`auctionMinimumBidStep`|`uint256`|        Minimum difference between bids in the Orb's auction.|
|`auctionMinimumDuration`|`uint256`|       Minimum duration of the Orb's auction.|
|`auctionKeeperMinimumDuration`|`uint256`| Minimum duration of the Orb's auction.|
|`auctionBidExtension`|`uint256`|          Auction duration extension for late bids during the Orb auction.|
|`keeperTaxNumerator`|`uint256`|           Harberger tax numerator of the Orb, in basis points.|
|`royaltyNumerator`|`uint256`|             Royalty numerator of the Orb, in basis points.|
|`cooldown`|`uint256`|                     Cooldown of the Orb in seconds.|
|`flaggingPeriod`|`uint256`||
|`cleartextMaximumLength`|`uint256`|       Invocation cleartext maximum length for the Orb.|


### transferOrbOwnership

Transfers the ownership of an Orb to its creator. This contract will no longer be able to configure
the Orb afterwards.


```solidity
function transferOrbOwnership(uint256 orbId, address creatorAddress) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orbId`|`uint256`|          Id of the Orb to transfer.|
|`creatorAddress`|`address`| Address of the Orb's creator, they will have full control over the Orb.|


## Events
### OrbCreation

```solidity
event OrbCreation(uint256 indexed orbId, address indexed orbAddress);
```

