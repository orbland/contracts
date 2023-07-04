# OrbPondV2
[Git Source](https://github.com/orbland/orb/blob/771f5939dfb0545391995a5aae65b8d31afb5d3e/src/OrbPondV2.sol)

**Inherits:**
[OrbPond](/src/OrbPond.sol/contract.OrbPond.md)

**Author:**
Jonas Lekevicius

Orbs come from a Pond. The Orb Pond is used to efficiently create new Orbs, and track “official” Orbs,
supported by the Orb Land system. The Orb Pond is also used to register allowed Orb upgrade
implementations, and keeps a reference to an Orb Invocation Registry used by all Orbs created with this
Orb Pond.

*Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator and for upgrades.
V2 allows anyone to create orbs, not just the owner, automatically splitting proceeds between the creator
and the Orb Land wallet.*


## State Variables
### _VERSION
Orb Pond version. Value: 2.


```solidity
uint256 private constant _VERSION = 2;
```


### orbLandWallet

```solidity
address public orbLandWallet;
```


## Functions
### constructor


```solidity
constructor();
```

### initializeV2

Re-initializes the contract after upgrade


```solidity
function initializeV2(address orbLandWallet_) public reinitializer(2);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orbLandWallet_`|`address`|  The address of the Orb Land wallet.|


### createOrb

Creates a new Orb, and emits an event with the Orb's address.


```solidity
function createOrb(string memory name, string memory symbol, string memory tokenURI) external virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|     Name of the Orb, used for display purposes. Suggestion: "NameOrb".|
|`symbol`|`string`|   Symbol of the Orb, used for display purposes. Suggestion: "ORB".|
|`tokenURI`|`string`| Initial tokenURI of the Orb, used as part of ERC-721 tokenURI.|


### version

Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.


```solidity
function version() public view virtual override returns (uint256 orbPondVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbPondVersion`|`uint256`| Version of the Orb Pond contract.|


