# IOrbInvocationRegistry
[Git Source](https://github.com/orbland/orb/blob/7955ccc3c983c925780d5ee46f888378f75efa47/src/IOrbInvocationRegistry.sol)

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

### authorizedContracts


```solidity
function authorizedContracts(address contractAddress) external view returns (bool);
```

### version


```solidity
function version() external view returns (uint256);
```

### invokeWithCleartext


```solidity
function invokeWithCleartext(address orb, string memory cleartext) external;
```

### invokeWithCleartextAndCall


```solidity
function invokeWithCleartextAndCall(
    address orb,
    string memory cleartext,
    address addressToCall,
    bytes memory dataToCall
) external;
```

### invokeWithHash


```solidity
function invokeWithHash(address orb, bytes32 contentHash) external;
```

### invokeWithHashAndCall


```solidity
function invokeWithHashAndCall(address orb, bytes32 contentHash, address addressToCall, bytes memory dataToCall)
    external;
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

### ContractAuthorization

```solidity
event ContractAuthorization(address indexed contractAddress, bool indexed authorized);
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

### ContractNotAuthorized

```solidity
error ContractNotAuthorized(address externalContract);
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

