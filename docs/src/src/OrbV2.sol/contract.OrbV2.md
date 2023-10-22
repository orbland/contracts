# OrbV2
[Git Source](https://github.com/orbland/orb/blob/a97224f7f48993b3e85f6cac56cd5342ebaa9cd0/src/OrbV2.sol)

**Inherits:**
[Orb](/src/Orb.sol/contract.Orb.md)

**Authors:**
Jonas Lekevicius, Eric Wall

The Orb is issued by a Creator: the user who swore an Orb Oath together with a date until which the Oath
will be honored. The Creator can list the Orb for sale at a fixed price, or run an auction for it. The user
acquiring the Orb is known as the Keeper. The Keeper always has an Orb sale price set and is paying
Harberger tax based on their set price and a tax rate set by the Creator. This tax is accounted for per
second, and the Keeper must have enough funds on this contract to cover their ownership; otherwise the Orb
is re-auctioned, delivering most of the auction proceeds to the previous Keeper. The Orb also has a
cooldown that allows the Keeper to invoke the Orb — ask the Creator a question and receive their response,
based on conditions set in the Orb Oath. Invocation and response hashes and timestamps are tracked in an
Orb Invocation Registry.

*Supports ERC-721 interface, including metadata, but reverts on all transfers and approvals. Uses
`Ownable`'s `owner()` to identify the Creator of the Orb. Uses a custom `UUPSUpgradeable` implementation to
allow upgrades, if they are requested by the Creator and executed by the Keeper. The Orb is created as an
ERC-1967 proxy to an `Orb` implementation by the `OrbPond` contract, which is also used to track allowed
Orb upgrades and keeps a reference to an `OrbInvocationRegistry` used by this Orb.
V2 adds these changes:
- Fixes a bug with Keeper auctions changing `lastInvocationTime`. Now only creator auctions charge the Orb.
- Allows setting Keeper auction royalty as different from purchase royalty.
- Purchase function requires to provide Keeper auction royalty in addition to other parameters.
- Response period setting moved from `swearOath` to `setCooldown` and renamed to `setInvocationParameters`.
- Active Oath is now required to start Orb auction or list Orb for sale.
- Orb parameters can now be updated even during Keeper control, if Oath has expired.
- `beneficiaryWithdrawalAddress` can now be set by the Creator to withdraw funds to a different address, if
the address is authorized on the OrbPond.
- Overriden `initialize()` to allow using V2 as initial implementation, with new default values.
- Event changes: `OathSwearing` parameter change, `InvocationParametersUpdate` added (replaces
`CooldownUpdate` and `CleartextMaximumLengthUpdate`), `FeesUpdate` parameter change,
`BeneficiaryWithdrawalAddressUpdate` added.*


## State Variables
### _VERSION
Orb version. Value: 2.


```solidity
uint256 private constant _VERSION = 2;
```


### auctionRoyaltyNumerator
Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 10.00%.


```solidity
uint256 public auctionRoyaltyNumerator;
```


### beneficiaryWithdrawalAddress
Address to withdraw beneficiary funds. If zero address, `beneficiary` is used. Can be set by Creator at any
point using `setBeneficiaryWithdrawalAddress()`.


```solidity
address public beneficiaryWithdrawalAddress;
```


### __gap
Gap used to prevent storage collisions.


```solidity
uint256[100] private __gap;
```


## Functions
### initialize

*When deployed, contract mints the only token that will ever exist, to itself.
This token represents the Orb and is called the Orb elsewhere in the contract.
`Ownable` sets the deployer to be the `owner()`, and also the creator in the Orb context.
V2 changes initial values and sets `auctionKeeperMinimumDuration`.*


```solidity
function initialize(address beneficiary_, string memory name_, string memory symbol_, string memory tokenURI_)
    public
    virtual
    override
    initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`beneficiary_`|`address`|  Address to receive all Orb proceeds.|
|`name_`|`string`|         Orb name, used in ERC-721 metadata.|
|`symbol_`|`string`|       Orb symbol or ticker, used in ERC-721 metadata.|
|`tokenURI_`|`string`|     Initial value for tokenURI JSONs.|


### initializeV2

Re-initializes the contract after upgrade, sets initial `auctionRoyaltyNumerator` value and sets
`responsePeriod` to `cooldown` if it was not set before.


```solidity
function initializeV2() public reinitializer(2);
```

### version

Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.


```solidity
function version() public view virtual override returns (uint256 orbVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbVersion`|`uint256`| Version of the Orb.|


### onlyCreatorControlled

*Ensures that the Orb belongs to the contract itself or the creator, and the auction hasn't been started.
Most setting-adjusting functions should use this modifier. It means that the Orb properties cannot be
modified while it is held by the keeper or users can bid on the Orb.
V2 changes to allow setting parameters even during Keeper control, if Oath has expired.*


```solidity
modifier onlyCreatorControlled() virtual override;
```

### onlyHonored

*Ensures that the Orb Oath is still honored (`honoredUntil` is in the future). Used to enforce Oath
swearing before starting the auction or listing the Orb for sale.*


```solidity
modifier onlyHonored() virtual;
```

### swearOath

Allows re-swearing of the Orb Oath and set a new `honoredUntil` date. This function can only be called
by the Orb creator when the Orb is in their control. With `swearOath()`, `honoredUntil` date can be
decreased, unlike with the `extendHonoredUntil()` function.

*Emits `OathSwearing`.
V2 changes to allow re-swearing even during Keeper control, if Oath has expired, and moves
`responsePeriod` setting to `setInvocationParameters()`.*


```solidity
function swearOath(bytes32 oathHash, uint256 newHonoredUntil) external virtual onlyOwner onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oathHash`|`bytes32`|          Hash of the Oath taken to create the Orb.|
|`newHonoredUntil`|`uint256`|   Date until which the Orb creator will honor the Oath for the Orb keeper.|


### swearOath

*Previous `swearOath()` overriden to revert.*


```solidity
function swearOath(bytes32, uint256, uint256) external pure override;
```

### setFees

Allows the Orb creator to set the new keeper tax and royalty. This function can only be called by the
Orb creator when the Orb is in their control.

*Emits `FeesUpdate`.
V2 changes to allow setting Keeper auction royalty separately from purchase royalty, with releated
parameter and event changes.*


```solidity
function setFees(uint256 newKeeperTaxNumerator, uint256 newPurchaseRoyaltyNumerator, uint256 newAuctionRoyaltyNumerator)
    external
    virtual
    onlyOwner
    onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newKeeperTaxNumerator`|`uint256`|       New keeper tax numerator, in relation to `feeDenominator()`.|
|`newPurchaseRoyaltyNumerator`|`uint256`| New royalty numerator for royalties from `purchase()`, in relation to `feeDenominator()`. Cannot be larger than `feeDenominator()`.|
|`newAuctionRoyaltyNumerator`|`uint256`|  New royalty numerator for royalties from keeper auctions, in relation to `feeDenominator()`. Cannot be larger than `feeDenominator()`.|


### setFees

*Previous `setFees()` overriden to revert.*


```solidity
function setFees(uint256, uint256) external pure override;
```

### setInvocationParameters

Allows the Orb creator to set the new cooldown duration, response period, flagging period (duration for
how long Orb keeper may flag a response) and cleartext maximum length. This function can only be called
by the Orb creator when the Orb is in their control.

*Emits `InvocationParametersUpdate`.
V2 merges `setCooldown()` and `setCleartextMaximumLength()` into one function, and moves
`responsePeriod` setting here. Events `CooldownUpdate` and `CleartextMaximumLengthUpdate` are merged
into `InvocationParametersUpdate`.*


```solidity
function setInvocationParameters(
    uint256 newCooldown,
    uint256 newResponsePeriod,
    uint256 newFlaggingPeriod,
    uint256 newCleartextMaximumLength
) external virtual onlyOwner onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCooldown`|`uint256`|       New cooldown in seconds. Cannot be longer than `COOLDOWN_MAXIMUM_DURATION`.|
|`newResponsePeriod`|`uint256`| New flagging period in seconds.|
|`newFlaggingPeriod`|`uint256`| New flagging period in seconds.|
|`newCleartextMaximumLength`|`uint256`| New cleartext maximum length. Cannot be 0.|


### setCooldown

*Previous `setCooldown()` overriden to revert.*


```solidity
function setCooldown(uint256, uint256) external pure override;
```

### setCleartextMaximumLength

*Previous `setCleartextMaximumLength()` overriden to revert.*


```solidity
function setCleartextMaximumLength(uint256) external pure override;
```

### setBeneficiaryWithdrawalAddress

Allows the Orb creator to set the new beneficiary withdrawal address, which can be different from
`beneficiary`, allowing Payment Splitter to be changed to a new version. Only addresses authorized on
the OrbPond (or the zero address, to reset to `beneficiary` value) can be set as the new withdrawal
address. This function can only be called anytime by the Orb Creator.

*Emits `BeneficiaryWithdrawalAddressUpdate`.*


```solidity
function setBeneficiaryWithdrawalAddress(address newBeneficiaryWithdrawalAddress) external virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newBeneficiaryWithdrawalAddress`|`address`| New beneficiary withdrawal address.|


### startAuction

Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.

*Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
after auction is finalized. Emits `AuctionStart`.
V2 adds `onlyHonored` modifier to require active Oath to start auction.*


```solidity
function startAuction() external virtual override onlyOwner notDuringAuction onlyHonored;
```

### finalizeAuction

Finalizes the auction, transferring the winning bid to the beneficiary, and the Orb to the winner.
If the auction was started by previous Keeper with `relinquishWithAuction()`, then most of the auction
proceeds (minus the royalty) will be sent to the previous Keeper. Sets `lastInvocationTime` so that
the Orb could be invoked immediately. The price has been set when bidding, now becomes relevant. If no
bids were made, resets the state to allow the auction to be started again later.

*Critical state transition function. Called after `auctionEndTime`, but only if it's not 0. Can be
called by anyone, although probably will be called by the creator or the winner. Emits `PriceUpdate`
and `AuctionFinalization`.
V2 fixes a bug with Keeper auctions changing lastInvocationTime, and uses `auctionRoyaltyNumerator`
instead of `royaltyNumerator` for auction royalty (only relevant for Keeper auctions).*


```solidity
function finalizeAuction() external virtual override notDuringAuction;
```

### listWithPrice

Lists the Orb for sale at the given price to buy directly from the Orb creator. This is an alternative
to the auction mechanism, and can be used to simply have the Orb for sale at a fixed price, waiting
for the buyer. Listing is only allowed if the auction has not been started and the Orb is held by the
contract. When the Orb is purchased from the creator, all proceeds go to the beneficiary and the Orb
comes fully charged, with no cooldown.

*Emits `Transfer` and `PriceUpdate`.
V2 adds `onlyHonored` modifier to require active Oath to list Orb for sale.*


```solidity
function listWithPrice(uint256 listingPrice) external virtual override onlyOwner onlyHonored;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`listingPrice`|`uint256`| The price to buy the Orb from the creator.|


### purchase

Purchasing is the mechanism to take over the Orb. With Harberger tax, the Orb can always be purchased
from its keeper. Purchasing is only allowed while the keeper is solvent. If not, the Orb has to be
foreclosed and re-auctioned. This function does not require the purchaser to have more funds than
required, but purchasing without any reserve would leave the new owner immediately foreclosable.
Beneficiary receives either just the royalty, or full price if the Orb is purchased from the creator.

*Requires to provide key Orb parameters (current price, Harberger tax rate, royalty, cooldown and
cleartext maximum length) to prevent front-running: without these parameters Orb creator could
front-run purcaser and change Orb parameters before the purchase; and without current price anyone
could purchase the Orb ahead of the purchaser, set the price higher, and profit from the purchase.
Does not modify `lastInvocationTime` unless buying from the creator.
Does not allow settlement in the same block before `purchase()` to prevent transfers that avoid
royalty payments. Does not allow purchasing from yourself. Emits `PriceUpdate` and `Purchase`.
V2 changes to require providing Keeper auction royalty to prevent front-running.*


```solidity
function purchase(
    uint256 newPrice,
    uint256 currentPrice,
    uint256 currentKeeperTaxNumerator,
    uint256 currentRoyaltyNumerator,
    uint256 currentAuctionRoyaltyNumerator,
    uint256 currentCooldown,
    uint256 currentCleartextMaximumLength
) external payable virtual onlyKeeperHeld onlyKeeperSolvent;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPrice`|`uint256`|                       New price to use after the purchase.|
|`currentPrice`|`uint256`|                   Current price, to prevent front-running.|
|`currentKeeperTaxNumerator`|`uint256`|      Current keeper tax numerator, to prevent front-running.|
|`currentRoyaltyNumerator`|`uint256`|        Current royalty numerator, to prevent front-running.|
|`currentAuctionRoyaltyNumerator`|`uint256`| Current keeper auction royalty numerator, to prevent front-running.|
|`currentCooldown`|`uint256`|                Current cooldown, to prevent front-running.|
|`currentCleartextMaximumLength`|`uint256`|  Current cleartext maximum length, to prevent front-running.|


### purchase

*Previous `purchase()` overriden to revert.*


```solidity
function purchase(uint256, uint256, uint256, uint256, uint256, uint256) external payable virtual override;
```

### withdrawAllForBeneficiary

Function to withdraw all beneficiary funds on the contract. Settles if possible.

*Allowed for anyone at any time, does not use `msg.sender` in its execution.
Emits `Withdrawal`.
V2 changes to withdraw to `beneficiaryWithdrawalAddress` if set to a non-zero address, and copies
`_withdraw()` functionality to this function, as it modifies funds of a different address (always
`beneficiary`) than the withdrawal destination (potentially `beneficiaryWithdrawalAddress`).*


```solidity
function withdrawAllForBeneficiary() external virtual override;
```

## Events
### OathSwearing

```solidity
event OathSwearing(bytes32 indexed oathHash, uint256 indexed honoredUntil);
```

### FeesUpdate

```solidity
event FeesUpdate(
    uint256 previousKeeperTaxNumerator,
    uint256 indexed newKeeperTaxNumerator,
    uint256 previousPurchaseRoyaltyNumerator,
    uint256 indexed newPurchaseRoyaltyNumerator,
    uint256 previousAuctionRoyaltyNumerator,
    uint256 indexed newAuctionRoyaltyNumerator
);
```

### InvocationParametersUpdate

```solidity
event InvocationParametersUpdate(
    uint256 previousCooldown,
    uint256 indexed newCooldown,
    uint256 previousResponsePeriod,
    uint256 indexed newResponsePeriod,
    uint256 previousFlaggingPeriod,
    uint256 indexed newFlaggingPeriod,
    uint256 previousCleartextMaximumLength,
    uint256 newCleartextMaximumLength
);
```

### BeneficiaryWithdrawalAddressUpdate

```solidity
event BeneficiaryWithdrawalAddressUpdate(
    address previousBeneficiaryWithdrawalAddress, address indexed newBeneficiaryWithdrawalAddress
);
```

## Errors
### NotHonored

```solidity
error NotHonored();
```

### AddressNotPermitted

```solidity
error AddressNotPermitted(address unauthorizedAddress);
```

