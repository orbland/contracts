# PaymentSplitter
[Git Source](https://github.com/orbland/orb/blob/2bc9cefc3aee952af3b4e1b5c06007779197cbaa/src/CustomPaymentSplitter.sol)

**Inherits:**
PaymentSplitterUpgradeable

**Author:**
Jonas Lekevicius

*This is a non-abstract version of the OpenZeppelin Contract `PaymentSplitterUpgradeable` contract that
implements an initializer, and has a constructor to disable the initializer on base deployment. Meant to be
used as an implementation to a EIP-1167 clone factory. This contract is not actually upgradeable despite
the name of the base contract.*


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

