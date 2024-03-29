# OrbPond
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/OrbPond.sol)

**Inherits:**
OwnableUpgradeable, [UUPSUpgradeable](/src/CustomUUPSUpgradeable.sol/abstract.UUPSUpgradeable.md)

**Author:**
Jonas Lekevicius

Orbs come from a Pond. The Orb Pond is used to efficiently create new Orbs, and track “official” Orbs,
supported by the Orb Land system. The Orb Pond is also used to register allowed Orb upgrade
implementations, and keeps a reference to an Orb Invocation Registry used by all Orbs created with this
Orb Pond.

*Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator and for upgrades.*


## State Variables
### _VERSION
Orb Pond version. Value: 1.


```solidity
uint256 private constant _VERSION = 1;
```


### orbs
The mapping of Orb ids to Orbs. Increases monotonically.


```solidity
mapping(uint256 orbId => address orbAddress) public orbs;
```


### orbCount
The number of Orbs created so far, used to find the next Orb id.


```solidity
uint256 public orbCount;
```


### versions
The mapping of version numbers to implementation contract addresses. Looked up by Orbs to find implementation
contracts for upgrades.


```solidity
mapping(uint256 versionNumber => address implementation) public versions;
```


### upgradeCalldata
The mapping of version numbers to upgrade calldata. Looked up by Orbs to find initialization calldata for
upgrades.


```solidity
mapping(uint256 versionNumber => bytes upgradeCalldata) public upgradeCalldata;
```


### latestVersion
The highest version number so far. Could be used for new Orb creation.


```solidity
uint256 public latestVersion;
```


### registry
The address of the Orb Invocation Registry, used to register Orb invocations and responses.


```solidity
address public registry;
```


### paymentSplitterImplementation
The address of the PaymentSplitter implementation contract, used to create new PaymentSplitters.


```solidity
address public paymentSplitterImplementation;
```


### __gap
Gap used to prevent storage collisions.


```solidity
uint256[100] private __gap;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize

Initializes the contract, setting the `owner` and `registry` variables.


```solidity
function initialize(address registry_, address paymentSplitterImplementation_) public initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`registry_`|`address`|                       The address of the Orb Invocation Registry.|
|`paymentSplitterImplementation_`|`address`|  The address of the PaymentSplitter implementation contract.|


### createOrb

Creates a new Orb together with a PaymentSplitter, and emits an event with the Orb's address.


```solidity
function createOrb(
    address[] memory payees_,
    uint256[] memory shares_,
    string memory name,
    string memory symbol,
    string memory tokenURI
) external virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`payees_`|`address[]`|      Beneficiaries of the Orb's PaymentSplitter.|
|`shares_`|`uint256[]`|      Shares of the Orb's PaymentSplitter.|
|`name`|`string`|         Name of the Orb, used for display purposes. Suggestion: "NameOrb".|
|`symbol`|`string`|       Symbol of the Orb, used for display purposes. Suggestion: "ORB".|
|`tokenURI`|`string`|     Initial tokenURI of the Orb, used as part of ERC-721 tokenURI.|


### registerVersion

Registers a new version of the Orb implementation contract. The version number must be exactly one
higher than the previous version number, and the implementation address must be non-zero. Versions can
be un-registered by setting the implementation address to 0; only the latest version can be
un-registered.


```solidity
function registerVersion(uint256 version_, address implementation_, bytes calldata upgradeCalldata_)
    external
    virtual
    onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`version_`|`uint256`|         Version number of the new implementation contract.|
|`implementation_`|`address`|  Address of the new implementation contract.|
|`upgradeCalldata_`|`bytes`| Initialization calldata to be used for upgrading to the new implementation contract.|


### version

Returns the version of the Orb Pond. Internal constant `_VERSION` will be increased with each upgrade.


```solidity
function version() public view virtual returns (uint256 orbPondVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbPondVersion`|`uint256`| Version of the Orb Pond contract.|


### _authorizeUpgrade

*Authorizes `owner()` to upgrade this OrbPond contract.*


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyOwner;
```

## Events
### OrbCreation

```solidity
event OrbCreation(uint256 indexed orbId, address indexed orbAddress);
```

### VersionRegistration

```solidity
event VersionRegistration(uint256 indexed versionNumber, address indexed implementation);
```

## Errors
### InvalidVersion

```solidity
error InvalidVersion();
```

