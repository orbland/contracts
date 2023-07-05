# OrbInvocationRegistry
[Git Source](https://github.com/orbland/orb/blob/ef217489df43f420a76112a53516d27603cf94a8/src/OrbInvocationRegistry.sol)

**Inherits:**
Initializable, [IOrbInvocationRegistry](/src/IOrbInvocationRegistry.sol/interface.IOrbInvocationRegistry.md), ERC165Upgradeable, OwnableUpgradeable, [UUPSUpgradeable](/src/CustomUUPSUpgradeable.sol/abstract.UUPSUpgradeable.md)

**Author:**
Jonas Lekevicius

The Orb Invocation Registry is used to track invocations and responses for any Orb.

*`Orb`s using an `OrbInvocationRegistry` must implement `IOrb` interface. Uses `Ownable`'s `owner()` to
guard upgrading.*


## State Variables
### _VERSION
Orb Invocation Registry version. Value: 1.


```solidity
uint256 private constant _VERSION = 1;
```


### invocations
Mapping for invocations: invocationId to InvocationData struct. InvocationId starts at 1.


```solidity
mapping(address orb => mapping(uint256 invocationId => InvocationData invocationData)) public invocations;
```


### invocationCount
Count of invocations made: used to calculate invocationId of the next invocation.


```solidity
mapping(address orb => uint256 count) public invocationCount;
```


### responses
Mapping for responses (answers to invocations): matching invocationId to ResponseData struct.


```solidity
mapping(address orb => mapping(uint256 invocationId => ResponseData responseData)) public responses;
```


### responseFlagged
Mapping for flagged (reported) responses. Used by the keeper not satisfied with a response.


```solidity
mapping(address orb => mapping(uint256 invocationId => bool isFlagged)) public responseFlagged;
```


### flaggedResponsesCount
Flagged responses count is a convencience count of total flagged responses. Not used by the contract itself.


```solidity
mapping(address orb => uint256 count) public flaggedResponsesCount;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize

*Initializes the contract.*


```solidity
function initialize() public initializer;
```

### supportsInterface

*ERC-165 supportsInterface. Orb contract supports ERC-721 and IOrb interfaces.*


```solidity
function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC165Upgradeable, IERC165Upgradeable)
    returns (bool isInterfaceSupported);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`interfaceId`|`bytes4`|          Interface id to check for support.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isInterfaceSupported`|`bool`| If interface with given 4 bytes id is supported.|


### onlyKeeper

*Ensures that the caller owns the Orb. Should only be used in conjuction with `onlyKeeperHeld` or on
external functions, otherwise does not make sense.*


```solidity
modifier onlyKeeper(address orb) virtual;
```

### onlyKeeperHeld

*Ensures that the Orb belongs to someone, not the contract itself.*


```solidity
modifier onlyKeeperHeld(address orb) virtual;
```

### onlyKeeperSolvent

*Ensures that the current Orb keeper has enough funds to cover Harberger tax until now.*


```solidity
modifier onlyKeeperSolvent(address orb) virtual;
```

### onlyCreator

*Ensures that the caller is the creator of the Orb.*


```solidity
modifier onlyCreator(address orb) virtual;
```

### invokeWithCleartext

Invokes the Orb. Allows the keeper to submit cleartext.

*Cleartext is hashed and passed to `invokeWithHash()`. Emits `CleartextRecording`.*


```solidity
function invokeWithCleartext(address orb, string memory cleartext) external virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`||
|`cleartext`|`string`| Invocation cleartext.|


### invokeWithHash

Invokes the Orb. Allows the keeper to submit content hash, that represents a question to the Orb
creator. Puts the Orb on cooldown. The Orb can only be invoked by solvent keepers.

*Content hash is keccak256 of the cleartext. `invocationCount` is used to track the id of the next
invocation. Invocation ids start from 1. Emits `Invocation`.*


```solidity
function invokeWithHash(address orb, bytes32 contentHash)
    public
    virtual
    onlyKeeper(orb)
    onlyKeeperHeld(orb)
    onlyKeeperSolvent(orb);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`||
|`contentHash`|`bytes32`| Required keccak256 hash of the cleartext.|


### respond

The Orb creator can use this function to respond to any existing invocation, no matter how long ago
it was made. A response to an invocation can only be written once. There is no way to record response
cleartext on-chain.

*Emits `Response`.*


```solidity
function respond(address orb, uint256 invocationId, bytes32 contentHash) external virtual onlyCreator(orb);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`||
|`invocationId`|`uint256`| Id of an invocation to which the response is being made.|
|`contentHash`|`bytes32`|  keccak256 hash of the response text.|


### flagResponse

Orb keeper can flag a response during Response Flagging Period, counting from when the response is
made. Flag indicates a "report", that the Orb keeper was not satisfied with the response provided.
This is meant to act as a social signal to future Orb keepers. It also increments
`flaggedResponsesCount`, allowing anyone to quickly look up how many responses were flagged.

*Only existing responses (with non-zero timestamps) can be flagged. Responses can only be flagged by
solvent keepers to keep it consistent with `invokeWithHash()` or `invokeWithCleartext()`. Also, the
keeper must have received the Orb after the response was made; this is to prevent keepers from
flagging responses that were made in response to others' invocations. Emits `ResponseFlagging`.*


```solidity
function flagResponse(address orb, uint256 invocationId) external virtual onlyKeeper(orb) onlyKeeperSolvent(orb);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`||
|`invocationId`|`uint256`| Id of an invocation to which the response is being flagged.|


### _responseExists

*Returns if a response to an invocation exists, based on the timestamp of the response being non-zero.*


```solidity
function _responseExists(address orb, uint256 invocationId_) internal view virtual returns (bool isResponseFound);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orb`|`address`||
|`invocationId_`|`uint256`| Id of an invocation to which to check the existance of a response of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isResponseFound`|`bool`| If a response to an invocation exists or not.|


### version

Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.


```solidity
function version() public view virtual returns (uint256 orbInvocationRegistryVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbInvocationRegistryVersion`|`uint256`| Version of the Orb Invocation Registry contract.|


### _authorizeUpgrade

*Authorizes owner address to upgrade the contract.*


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyOwner;
```

## Structs
### InvocationData
Structs used to track invocation and response information: keccak256 content hash and block timestamp.
InvocationData is used to determine if the response can be flagged by the keeper.
Invocation timestamp and invoker address is tracked for the benefit of other contracts.


```solidity
struct InvocationData {
    address invoker;
    bytes32 contentHash;
    uint256 timestamp;
}
```

### ResponseData

```solidity
struct ResponseData {
    bytes32 contentHash;
    uint256 timestamp;
}
```

