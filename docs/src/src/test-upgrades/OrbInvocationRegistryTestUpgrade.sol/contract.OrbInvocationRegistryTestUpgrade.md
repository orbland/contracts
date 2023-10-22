# OrbInvocationRegistryTestUpgrade
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/test-upgrades/OrbInvocationRegistryTestUpgrade.sol)

**Inherits:**
[OrbInvocationRegistry](/src/OrbInvocationRegistry.sol/contract.OrbInvocationRegistry.md)

**Author:**
Jonas Lekevicius

The Orb Invocation Registry is used to track invocations and responses for any Orb.

*`Orb`s using an `OrbInvocationRegistry` must implement `IOrb` interface. Uses `Ownable`'s `owner()` to
guard upgrading.
Test Upgrade records Late Response Receipts if the response is made after the response period. Together
with the `LateResponseDeposit` contract, it can allow Creators to compensate Keepers for late responses.*


## State Variables
### _VERSION
Orb Invocation Registry version.


```solidity
uint256 private constant _VERSION = 100;
```


### lateResponseFund
The address of the Late Response Deposit contract.


```solidity
address public lateResponseFund;
```


### lateResponseReceipts
Mapping for late response receipts. Used to track late response receipts for invocations that have not been


```solidity
mapping(address orb => mapping(uint256 invocationId => LateResponseReceipt receipt)) public lateResponseReceipts;
```


### lateResponseReceiptClaimed
Mapping for late response receipts. Used to track late response receipts for invocations that have not been


```solidity
mapping(address orb => mapping(uint256 invocationId => bool receiptClaimed)) public lateResponseReceiptClaimed;
```


## Functions
### constructor


```solidity
constructor();
```

### initializeTestUpgrade

Re-initializes the contract after upgrade


```solidity
function initializeTestUpgrade(address lateResponseFund_) public reinitializer(100);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`lateResponseFund_`|`address`| The address of the Late Response Compensation Fund.|


### respond

The Orb creator can use this function to respond to any existing invocation, no matter how long ago
it was made. A response to an invocation can only be written once. There is no way to record response
cleartext on-chain.

*Emits `Response`, and sometimes `LateResponse` if the response was made after the response period.*


```solidity
function respond(address orb, uint256 invocationId, bytes32 contentHash) external virtual override onlyCreator(orb);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`||
|`invocationId`|`uint256`| Id of an invocation to which the response is being made.|
|`contentHash`|`bytes32`|  keccak256 hash of the response text.|


### setLateResponseReceiptClaimed


```solidity
function setLateResponseReceiptClaimed(address orb, uint256 invocationId) external;
```

### version

Returns the version of the Orb Invocation Registry. Internal constant `_VERSION` will be increased with
each upgrade.


```solidity
function version() public view virtual override returns (uint256 orbInvocationRegistryVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbInvocationRegistryVersion`|`uint256`| Version of the Orb Invocation Registry contract.|


## Events
### LateResponse

```solidity
event LateResponse(address indexed orb, uint256 indexed invocationId, address indexed responder, uint256 lateDuration);
```

## Errors
### Unauthorized

```solidity
error Unauthorized();
```

### LateResponseReceiptClaimed

```solidity
error LateResponseReceiptClaimed(uint256 invocationId);
```

## Structs
### LateResponseReceipt

```solidity
struct LateResponseReceipt {
    uint256 lateDuration;
    uint256 price;
    uint256 keeperTaxNumerator;
}
```

