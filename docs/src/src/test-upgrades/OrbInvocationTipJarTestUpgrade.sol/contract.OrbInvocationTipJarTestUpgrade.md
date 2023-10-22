# OrbInvocationTipJarTestUpgrade
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/test-upgrades/OrbInvocationTipJarTestUpgrade.sol)

**Inherits:**
[OrbInvocationTipJar](/src/OrbInvocationTipJar.sol/contract.OrbInvocationTipJar.md)

**Author:**
Jonas Lekevicius

This contract allows anyone to suggest an invocation to an Orb and optionally tip the Orb keeper
Test Upgrade requires all tips to be multiples of fixed amount of ETH.


## State Variables
### _VERSION
Orb Invocation Tip Jar version.


```solidity
uint256 private constant _VERSION = 100;
```


### tipModulo
An amount of ETH that is used as a tip modulo. All tips must be multiples of this amount.


```solidity
uint256 public tipModulo;
```


## Functions
### constructor


```solidity
constructor();
```

### initializeTestUpgrade

Re-initializes the contract after upgrade


```solidity
function initializeTestUpgrade(uint256 tipModulo_) public reinitializer(100);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tipModulo_`|`uint256`| An amount of ETH that is used as a tip modulo.|


### tipInvocation

Tips an orb keeper to invoke their orb with a specific content hash


```solidity
function tipInvocation(address orb, bytes32 invocationHash) public payable virtual override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`|            The address of the orb|
|`invocationHash`|`bytes32`| The invocation content hash|


### setTipModulo


```solidity
function setTipModulo(uint256 tipModulo_) public virtual onlyOwner;
```

### version

Returns the version of the Orb Invocation TipJar. Internal constant `_VERSION` will be increased with
each upgrade.


```solidity
function version() public view virtual override returns (uint256 orbInvocationTipJarVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbInvocationTipJarVersion`|`uint256`| Version of the Orb Invocation TipJar contract.|


## Events
### TipModuloUpdate

```solidity
event TipModuloUpdate(uint256 previousTipModulo, uint256 indexed newTipModulo);
```

## Errors
### TipNotAModuloMultiple

```solidity
error TipNotAModuloMultiple(uint256 tip, uint256 tipModulo);
```

### InvalidTipModulo

```solidity
error InvalidTipModulo();
```

