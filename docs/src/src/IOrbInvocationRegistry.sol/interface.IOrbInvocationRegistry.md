# IOrbInvocationRegistry
[Git Source](https://github.com/orbland/orb/blob/771f5939dfb0545391995a5aae65b8d31afb5d3e/src/IOrbInvocationRegistry.sol)

**Inherits:**
IERC165Upgradeable


## Functions
### invocations


```solidity
function invocations(address orb, uint256 invocationId)
    external
    view
    returns (address invoker, bytes32 contentHash, uint256 timestamp);
```

### invocationCount


```solidity
function invocationCount(address orb) external view returns (uint256);
```

### responses


```solidity
function responses(address orb, uint256 invocationId) external view returns (bytes32 contentHash, uint256 timestamp);
```

### responseFlagged


```solidity
function responseFlagged(address orb, uint256 invocationId) external view returns (bool);
```

### flaggedResponsesCount


```solidity
function flaggedResponsesCount(address orb) external view returns (uint256);
```

### version


```solidity
function version() external view returns (uint256);
```

### invokeWithCleartext


```solidity
function invokeWithCleartext(address orb, string memory cleartext) external;
```

### invokeWithHash


```solidity
function invokeWithHash(address orb, bytes32 contentHash) external;
```

### respond


```solidity
function respond(address orb, uint256 invocationId, bytes32 contentHash) external;
```

### flagResponse


```solidity
function flagResponse(address orb, uint256 invocationId) external;
```

## Events
### Invocation

```solidity
event Invocation(
    address indexed orb, uint256 indexed invocationId, address indexed invoker, uint256 timestamp, bytes32 contentHash
);
```

### Response

```solidity
event Response(
    address indexed orb, uint256 indexed invocationId, address indexed responder, uint256 timestamp, bytes32 contentHash
);
```

### CleartextRecording

```solidity
event CleartextRecording(address indexed orb, uint256 indexed invocationId, string cleartext);
```

### ResponseFlagging

```solidity
event ResponseFlagging(address indexed orb, uint256 indexed invocationId, address indexed flagger);
```

## Errors
### NotKeeper

```solidity
error NotKeeper();
```

### NotCreator

```solidity
error NotCreator();
```

### ContractHoldsOrb

```solidity
error ContractHoldsOrb();
```

### KeeperInsolvent

```solidity
error KeeperInsolvent();
```

### CooldownIncomplete

```solidity
error CooldownIncomplete(uint256 timeRemaining);
```

### CleartextTooLong

```solidity
error CleartextTooLong(uint256 cleartextLength, uint256 cleartextMaximumLength);
```

### InvocationNotFound

```solidity
error InvocationNotFound(address orb, uint256 invocationId);
```

### ResponseNotFound

```solidity
error ResponseNotFound(address orb, uint256 invocationId);
```

### ResponseExists

```solidity
error ResponseExists(address orb, uint256 invocationId);
```

### FlaggingPeriodExpired

```solidity
error FlaggingPeriodExpired(address orb, uint256 invocationId, uint256 currentTimeValue, uint256 timeValueLimit);
```

### ResponseAlreadyFlagged

```solidity
error ResponseAlreadyFlagged(address orb, uint256 invocationId);
```

