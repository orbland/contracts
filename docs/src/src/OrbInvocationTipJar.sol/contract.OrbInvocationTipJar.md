# OrbInvocationTipJar
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/OrbInvocationTipJar.sol)

**Inherits:**
OwnableUpgradeable, [UUPSUpgradeable](/src/CustomUUPSUpgradeable.sol/abstract.UUPSUpgradeable.md)

**Authors:**
Jonas Lekevicius, Oren Yomtov

This contract allows anyone to suggest an invocation to an Orb and optionally tip the Orb keeper.


## State Variables
### _VERSION
Orb Invocation Tip Jar version


```solidity
uint256 private constant _VERSION = 1;
```


### _FEE_DENOMINATOR
Fee Nominator: basis points (100.00%). Platform fee is in relation to this.


```solidity
uint256 internal constant _FEE_DENOMINATOR = 100_00;
```


### totalTips
The sum of all tips for a given invocation


```solidity
mapping(address orb => mapping(bytes32 invocationHash => uint256 tippedAmount)) public totalTips;
```


### tipperTips
The sum of all tips for a given invocation by a given tipper


```solidity
mapping(address orb => mapping(address tipper => mapping(bytes32 invocationHash => uint256 tippedAmount))) public
    tipperTips;
```


### claimedInvocations
Whether a certain invocation's tips have been claimed: invocationId starts from 1


```solidity
mapping(address orb => mapping(bytes32 invocationHash => uint256 invocationId)) public claimedInvocations;
```


### minimumTips
The minimum tip value for a given Orb


```solidity
mapping(address orb => uint256 minimumTip) public minimumTips;
```


### platformAddress
Orb Land revenue address. Set during contract initialization to Orb Land Revenue multisig. While there is no
function to change this address, it can be changed by upgrading the contract.


```solidity
address public platformAddress;
```


### platformFee
Orb Land revenue fee numerator. Set during contract initialization. While there is no function to change this
value, it can be changed by upgrading the contract. The fee is in relation to `_FEE_DENOMINATOR`.
Note: contract upgradability poses risks! Orb Land may upgrade this contract and set the fee to _FEE_DENOMINATOR
(100.00%), taking away all future tips. This is a risk that Orb keepers must be aware of, until upgradability
is removed or modified.


```solidity
uint256 public platformFee;
```


### platformFunds
Funds allocated for the Orb Land platform, withdrawable to `platformAddress`


```solidity
uint256 public platformFunds;
```


### __gap
Gap used to prevent storage collisions


```solidity
uint256[100] private __gap;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize

*Initializes the contract.*


```solidity
function initialize(address platformAddress_, uint256 platformFee_) public initializer;
```

### tipInvocation

Tips a specific invocation content hash on an Orb. Any Keeper can invoke the tipped invocation and
claim the tips.


```solidity
function tipInvocation(address orb, bytes32 invocationHash) external payable virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`|            The address of the orb|
|`invocationHash`|`bytes32`| The invocation content hash|


### claimTipsForInvocation

Claims all tips for a given suggested invocation. Meant to be called together with the invocation
itself, using `invokeWith*AndCall` functions on OrbInvocationRegistry.


```solidity
function claimTipsForInvocation(address orb, uint256 invocationIndex, uint256 minimumTipTotal) external virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`|             The address of the Orb|
|`invocationIndex`|`uint256`| The invocation id to check|
|`minimumTipTotal`|`uint256`| The minimum tip value to claim (reverts if the total tips are less than this value)|


### withdrawTip

Withdraws a tip from a given invocation. Not possible if invocation has been claimed.


```solidity
function withdrawTip(address orb, bytes32 invocationHash) public virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`|            The address of the orb|
|`invocationHash`|`bytes32`| The invocation content hash|


### withdrawTips

Withdraws all tips from a given list of Orbs and invocations. Will revert if any given invocation has
been claimed.


```solidity
function withdrawTips(address[] memory orbs, bytes32[] memory invocationHashes) external virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orbs`|`address[]`|             Array of orb addresse|
|`invocationHashes`|`bytes32[]`| Array of invocation content hashes|


### withdrawPlatformFunds

Withdraws all funds set aside as the platform fee. Can be called by anyone.


```solidity
function withdrawPlatformFunds() external virtual;
```

### setMinimumTip

Sets the minimum tip value for a given Orb.


```solidity
function setMinimumTip(address orb, uint256 minimumTipValue) external virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`|             The address of the Orb|
|`minimumTipValue`|`uint256`| The minimum tip value|


### version

Returns the version of the Orb Invocation Tip Jar. Internal constant `_VERSION` will be increased with
each upgrade.


```solidity
function version() public view virtual returns (uint256 orbInvocationTipJarVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbInvocationTipJarVersion`|`uint256`| Version of the Orb Invocation Tip Jar contract.|


### _authorizeUpgrade

*Authorizes owner address to upgrade the contract.*


```solidity
function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner;
```

## Events
### TipDeposit

```solidity
event TipDeposit(address indexed orb, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);
```

### TipWithdrawal

```solidity
event TipWithdrawal(address indexed orb, bytes32 indexed invocationHash, address indexed tipper, uint256 tipValue);
```

### TipsClaim

```solidity
event TipsClaim(address indexed orb, bytes32 indexed invocationHash, address indexed invoker, uint256 tipsValue);
```

### MinimumTipUpdate

```solidity
event MinimumTipUpdate(address indexed orb, uint256 previousMinimumTip, uint256 indexed newMinimumTip);
```

## Errors
### PlatformAddressInvalid

```solidity
error PlatformAddressInvalid();
```

### PlatformFeeInvalid

```solidity
error PlatformFeeInvalid();
```

### InsufficientTip

```solidity
error InsufficientTip(uint256 tipValue, uint256 minimumTip);
```

### InvocationNotInvoked

```solidity
error InvocationNotInvoked();
```

### InvocationAlreadyClaimed

```solidity
error InvocationAlreadyClaimed();
```

### InsufficientTips

```solidity
error InsufficientTips(uint256 minimumTipTotal, uint256 totalClaimableTips);
```

### TipNotFound

```solidity
error TipNotFound();
```

### UnevenArrayLengths

```solidity
error UnevenArrayLengths();
```

### NoFundsAvailable

```solidity
error NoFundsAvailable();
```

### NotKeeper

```solidity
error NotKeeper();
```

