# OrbPondV2
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/OrbPondV2.sol)

**Inherits:**
[OrbPond](/src/OrbPond.sol/contract.OrbPond.md)

**Author:**
Jonas Lekevicius

Orbs come from a Pond. The Orb Pond is used to efficiently create new Orbs, and track “official” Orbs,
supported by the Orb Land system. The Orb Pond is also used to register allowed Orb upgrade
implementations, and keeps a reference to an Orb Invocation Registry used by all Orbs created with this
Orb Pond.

*Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator and for upgrades.
V2 adds these changes:
- `orbInitialVersion` field for new Orb creation and `setOrbInitialVersion()` function to set it. This
allows to specify which version of the Orb implementation to use for new Orbs.
- `beneficiaryWithdrawalAddresses` mapping to authorize addresses to be used as
`beneficiaryWithdrawalAddress` on Orbs, `authorizeWithdrawalAddress()` function to set it, and
`beneficiaryWithdrawalAddressPermitted()` function to check if address is authorized.*


## State Variables
### _VERSION
Orb Pond version. Value: 2.


```solidity
uint256 private constant _VERSION = 2;
```


### orbInitialVersion
New Orb version


```solidity
uint256 public orbInitialVersion;
```


### beneficiaryWithdrawalAddresses
Addresses authorized to be used as beneficiaryWithdrawal address


```solidity
mapping(address withdrawalAddress => bool isPermitted) public beneficiaryWithdrawalAddresses;
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

### initializeV2

Reinitializes the contract with provided initial value for `orbInitialVersion`.


```solidity
function initializeV2(uint256 orbInitialVersion_) public reinitializer(2);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orbInitialVersion_`|`uint256`| Registered Orb implementation version to be used for new Orbs.|


### createOrb

Creates a new Orb together with a PaymentSplitter, and emits an event with the Orb's address.


```solidity
function createOrb(
    address[] memory payees_,
    uint256[] memory shares_,
    string memory name,
    string memory symbol,
    string memory tokenURI
) external virtual override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`payees_`|`address[]`|      Beneficiaries of the Orb's PaymentSplitter.|
|`shares_`|`uint256[]`|      Shares of the Orb's PaymentSplitter.|
|`name`|`string`|         Name of the Orb, used for display purposes. Suggestion: "NameOrb".|
|`symbol`|`string`|       Symbol of the Orb, used for display purposes. Suggestion: "ORB".|
|`tokenURI`|`string`|     Initial tokenURI of the Orb, used as part of ERC-721 tokenURI.|


### setOrbInitialVersion

Sets the registered Orb implementation version to be used for new Orbs.


```solidity
function setOrbInitialVersion(uint256 orbInitialVersion_) external virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`orbInitialVersion_`|`uint256`| Registered Orb implementation version number to be used for new Orbs.|


### version

Returns the version of the Orb Pond. Internal constant `_VERSION` will be increased with each upgrade.


```solidity
function version() public view virtual override returns (uint256 orbPondVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbPondVersion`|`uint256`| Version of the Orb Pond contract.|


### beneficiaryWithdrawalAddressPermitted

Returns if address can be used as beneficiary withdrawal address on Orbs.


```solidity
function beneficiaryWithdrawalAddressPermitted(address beneficiaryWithdrawalAddress)
    external
    virtual
    returns (bool isBeneficiaryWithdrawalAddressPermitted);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`beneficiaryWithdrawalAddress`|`address`|Address to check. Zero address is always permitted.|


### authorizeWithdrawalAddress

Allows the owner to authorize permitted beneficiary withdrawal addresses.


```solidity
function authorizeWithdrawalAddress(address addressToAuthorize, bool authorizationValue) external virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`addressToAuthorize`|`address`| Address to authorize (likely contract).|
|`authorizationValue`|`bool`| Boolean value to set the authorization to.|


## Events
### OrbInitialVersionUpdate

```solidity
event OrbInitialVersionUpdate(uint256 previousInitialVersion, uint256 indexed newInitialVersion);
```

### WithdrawalAddressAuthorization

```solidity
event WithdrawalAddressAuthorization(address indexed withdrawalAddress, bool indexed authorized);
```

