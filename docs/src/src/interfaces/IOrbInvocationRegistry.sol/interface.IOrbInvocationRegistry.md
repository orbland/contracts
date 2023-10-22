# IOrbInvocationRegistry
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/interfaces/IOrbInvocationRegistry.sol)

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

