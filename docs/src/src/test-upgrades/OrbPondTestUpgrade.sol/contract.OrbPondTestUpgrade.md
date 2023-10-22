# OrbPondTestUpgrade
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/test-upgrades/OrbPondTestUpgrade.sol)

**Inherits:**
[OrbPondV2](/src/OrbPondV2.sol/contract.OrbPondV2.md)

**Author:**
Jonas Lekevicius

Orbs come from a Pond. The Orb Pond is used to efficiently create new Orbs, and track “official” Orbs,
supported by the Orb Land system. The Orb Pond is also used to register allowed Orb upgrade
implementations, and keeps a reference to an Orb Invocation Registry used by all Orbs created with this
Orb Pond.

*Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator and for upgrades.
Test Upgrade allows anyone to create orbs, not just the owner, automatically splitting proceeds between the
creator and the Orb Land wallet.*


## State Variables
### _VERSION
Orb Pond version.


```solidity
uint256 private constant _VERSION = 100;
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

### initializeTestUpgrade

Re-initializes the contract after upgrade


```solidity
function initializeTestUpgrade(address orbLandWallet_) public reinitializer(100);
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

Returns the version of the Orb Pond. Internal constant `_VERSION` will be increased with each upgrade.


```solidity
function version() public view virtual override returns (uint256 orbPondVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbPondVersion`|`uint256`| Version of the Orb Pond contract.|


