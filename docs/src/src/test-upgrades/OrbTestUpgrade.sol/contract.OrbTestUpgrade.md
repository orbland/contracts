# OrbTestUpgrade
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/test-upgrades/OrbTestUpgrade.sol)

**Inherits:**
[OrbV2](/src/OrbV2.sol/contract.OrbV2.md)

**Authors:**
Jonas Lekevicius, Eric Wall

The Orb is issued by a Creator: the user who swore an Orb Oath together with a date until which the Oath
will be honored. The Creator can list the Orb for sale at a fixed price, or run an auction for it. The user
acquiring the Orb is known as the Keeper. The Keeper always has an Orb sale price set and is paying
Harberger tax based on their set price and a tax rate set by the Creator. This tax is accounted for per
second, and the Keeper must have enough funds on this contract to cover their ownership; otherwise the Orb
is re-auctioned, delivering most of the auction proceeds to the previous Keeper. The Orb also has a
cooldown that allows the Keeper to invoke the Orb — ask the Creator a question and receive their response,
based on conditions set in the Orb Oath. Invocation and response hashes and timestamps are tracked in an
Orb Invocation Registry.

*Supports ERC-721 interface, including metadata, but reverts on all transfers and approvals. Uses
`Ownable`'s `owner()` to identify the Creator of the Orb. Uses a custom `UUPSUpgradeable` implementation to
allow upgrades, if they are requested by the Creator and executed by the Keeper. The Orb is created as an
ERC-1967 proxy to an `Orb` implementation by the `OrbPond` contract, which is also used to track allowed
Orb upgrades and keeps a reference to an `OrbInvocationRegistry` used by this Orb.
Test Upgrade adds a new storage variable `number`, settable with `setNumber`, changes Orb name and symbol,
and allows the Creator to set the cleartext maximum length to zero. FOR TESTING ONLY!*


## State Variables
### _VERSION
Orb version.


```solidity
uint256 private constant _VERSION = 100;
```


### number
Testing new storage variable in upgrade. It's a number!


```solidity
uint256 public number;
```


## Functions
### initializeTestUpgrade

Re-initializes the contract after upgrade, sets initial number value


```solidity
function initializeTestUpgrade(string memory newName_, string memory newSymbol_) public reinitializer(100);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newName_`|`string`|   New name of the Orb|
|`newSymbol_`|`string`| New symbol of the Orb|


### setNumber

Allows anyone to record a number!


```solidity
function setNumber(uint256 newNumber) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newNumber`|`uint256`| New number value!|


### version

Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.


```solidity
function version() public view virtual override returns (uint256 orbVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbVersion`|`uint256`| Version of the Orb.|


