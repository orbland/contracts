# UUPSUpgradeable
[Git Source](https://github.com/orbland/orb/blob/ef217489df43f420a76112a53516d27603cf94a8/src/CustomUUPSUpgradeable.sol)

**Inherits:**
Initializable, IERC1822ProxiableUpgradeable, ERC1967UpgradeUpgradeable

**Author:**
Jonas Lekevicius

*An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade
of an `ERC1967Proxy`, when this contract is set as the implementation behind such a proxy. This is a
modified version of the OpenZeppelin Contract `UUPSUpgradeable` contract that does not expose any public
functions, to allow custom upgradeability logic to be implemented in the `Orb` contract.
Also, replaces string errors with custom errors.*


## State Variables
### __self

```solidity
address private immutable __self = address(this);
```


### __gap
*This empty reserved space is put in place to allow future versions to add new variables without shifting
down storage in the inheritance chain.
See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps*


```solidity
uint256[50] private __gap;
```


## Functions
### __UUPSUpgradeable_init


```solidity
function __UUPSUpgradeable_init() internal onlyInitializing;
```

### __UUPSUpgradeable_init_unchained


```solidity
function __UUPSUpgradeable_init_unchained() internal onlyInitializing;
```

### onlyProxy

*Check that the execution is being performed through a delegatecall call and that the execution context is
a proxy contract with an implementation (as defined in ERC1967) pointing to self. This should only be the
case for UUPS and transparent proxies that are using the current contract as their implementation.
Execution of a function through ERC1167 minimal proxies (clones) would not normally pass this test, but is
not guaranteed to fail.*


```solidity
modifier onlyProxy();
```

### notDelegated

*Check that the execution is not being performed through a delegate call. This allows a function to be
on the implementing contract but not through proxies.*


```solidity
modifier notDelegated();
```

### proxiableUUID

*Implementation of the ERC1822 {proxiableUUID} function. This returns the storage slot used by the
implementation. It is used to validate the implementation's compatibility when performing an upgrade.
IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because
this risks bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is
critical that this function revert if invoked through a proxy. This is guaranteed by the `notDelegated`
modifier.*


```solidity
function proxiableUUID() external view virtual override notDelegated returns (bytes32);
```

## Errors
### RequiresCallViaDelegatecall

```solidity
error RequiresCallViaDelegatecall();
```

### RequiresCallViaActiveProxy

```solidity
error RequiresCallViaActiveProxy();
```

### CallViaDelegatecallDisallowed

```solidity
error CallViaDelegatecallDisallowed();
```

