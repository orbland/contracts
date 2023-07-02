# OrbInvocationRegistryV2
[Git Source](https://github.com/orbland/orb/blob/5cb9d2d45418f2f4d5e123695311a6c3bddbfea2/src/OrbInvocationRegistryV2.sol)

**Inherits:**
[OrbInvocationRegistry](/src/OrbInvocationRegistry.sol/contract.OrbInvocationRegistry.md)

**Author:**
Jonas Lekevicius

The Orb Invocation Registry is used to track invocations and responses for any Orb.

*`Orb`s using an `OrbInvocationRegistry` must implement `IOrb` interface. Uses `Ownable`'s `owner()` to
guard upgrading.
V2 records Late Response Receipts if the response is made after the response period. Together with the
`LateResponseDeposit` contract, it can allow Creators to compensate Keepers for late responses.*


## State Variables
### _VERSION
Orb Invocation Registry version. Value: 2.


```solidity
uint256 private constant _VERSION = 2;
```


### lateResponseDepositAddress
The address of the Late Response Deposit contract.


```solidity
address public lateResponseDepositAddress;
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

### initializeV2

Re-initializes the contract after upgrade


```solidity
function initializeV2(address lateResponseDepositAddress_) public reinitializer(2);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`lateResponseDepositAddress_`|`address`| The address of the Orb Land wallet.|


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

Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.


```solidity
function version() public virtual override returns (uint256 orbInvocationRegistryVersion);
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

