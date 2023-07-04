# PaymentSplitter
[Git Source](https://github.com/orbland/orb/blob/771f5939dfb0545391995a5aae65b8d31afb5d3e/src/CustomPaymentSplitter.sol)

**Inherits:**
PaymentSplitterUpgradeable

**Author:**
Jonas Lekevicius

*This is a non-abstract version of the OpenZeppelin Contract `PaymentSplitterUpgradeable` contract that does
implements an initializer, and has a constructor to disable the initializer on base deployment. Meant to be
used as an implementation to a EIP-1167 clone factory.*


## Functions
### constructor


```solidity
constructor();
```

### initialize

*Calls the initializer of the `PaymentSplitterUpgradeable` contract, with payees and their shares.*


```solidity
function initialize(address[] memory payees_, uint256[] memory shares_) public initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`payees_`|`address[]`|  Payees addresses.|
|`shares_`|`uint256[]`|  Payees shares.|


