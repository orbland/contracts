# Orb
[Git Source](https://github.com/orbland/orb/blob/7955ccc3c983c925780d5ee46f888378f75efa47/src/Orb.sol)

**Inherits:**
IERC721MetadataUpgradeable, [IOrb](/src/IOrb.sol/interface.IOrb.md), ERC165Upgradeable, OwnableUpgradeable, [UUPSUpgradeable](/src/CustomUUPSUpgradeable.sol/abstract.UUPSUpgradeable.md)

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
Orb upgrades and keeps a reference to an `OrbInvocationRegistry` used by this Orb.*


## State Variables
### _VERSION
Orb version. Value: 1.


```solidity
uint256 private constant _VERSION = 1;
```


### _FEE_DENOMINATOR
Fee Nominator: basis points (100.00%). Other fees are in relation to this, and formatted as such.


```solidity
uint256 internal constant _FEE_DENOMINATOR = 100_00;
```


### _KEEPER_TAX_PERIOD
Harberger tax period: for how long the tax rate applies. Value: 1 year.


```solidity
uint256 internal constant _KEEPER_TAX_PERIOD = 365 days;
```


### _COOLDOWN_MAXIMUM_DURATION
Maximum cooldown duration, to prevent potential underflows. Value: 10 years.


```solidity
uint256 internal constant _COOLDOWN_MAXIMUM_DURATION = 3650 days;
```


### _MAXIMUM_PRICE
Maximum Orb price, limited to prevent potential overflows.


```solidity
uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;
```


### _TOKEN_ID
Token ID of the Orb. Value: 1.


```solidity
uint256 internal constant _TOKEN_ID = 1;
```


### pond
Address of the `OrbPond` that deployed this Orb. Pond manages permitted upgrades and provides Orb Invocation
Registry address.


```solidity
address public pond;
```


### beneficiary
Beneficiary is another address that receives all Orb proceeds. It is set in the `initializer` as an immutable
value. Beneficiary is not allowed to bid in the auction or purchase the Orb. The intended use case for the
beneficiary is to set it to a revenue splitting contract. Proceeds that go to the beneficiary are:
- The auction winning bid amount;
- Royalties from Orb purchase when not purchased from the Orb creator;
- Full purchase price when purchased from the Orb creator;
- Harberger tax revenue.


```solidity
address public beneficiary;
```


### keeper
Address of the Orb keeper. The keeper is the address that owns the Orb and has the right to invoke the Orb and
receive a response. The keeper is also the address that pays the Harberger tax. Keeper address is tracked
directly, and ERC-721 compatibility uses this value for `ownerOf()` and `balanceOf()` calls.


```solidity
address public keeper;
```


### honoredUntil
Honored Until: timestamp until which the Orb Oath is honored for the keeper.


```solidity
uint256 public honoredUntil;
```


### responsePeriod
Response Period: time period in which the keeper promises to respond to an invocation.
There are no penalties for being late within this contract.


```solidity
uint256 public responsePeriod;
```


### name
ERC-721 token name. Just for display purposes on blockchain explorers.


```solidity
string public name;
```


### symbol
ERC-721 token symbol. Just for display purposes on blockchain explorers.


```solidity
string public symbol;
```


### _tokenURI
Token URI for tokenURI JSONs. Initially set in the `initializer` and setable with `setTokenURI()`.


```solidity
string internal _tokenURI;
```


### fundsOf
Funds tracker, per address. Modified by deposits, withdrawals and settlements. The value is without settlement.
It means effective user funds (withdrawable) would be different for keeper (subtracting
`_owedSinceLastSettlement()`) and beneficiary (adding `_owedSinceLastSettlement()`). If Orb is held by the
creator, funds are not subtracted, as Harberger tax does not apply to the creator.


```solidity
mapping(address => uint256) public fundsOf;
```


### keeperTaxNumerator
Harberger tax for holding. Initial value is 10.00%.


```solidity
uint256 public keeperTaxNumerator;
```


### royaltyNumerator
Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 10.00%.


```solidity
uint256 public royaltyNumerator;
```


### price
Price of the Orb. Also used during auction to store future purchase price. Has no meaning if the Orb is held by
the contract and the auction is not running.


```solidity
uint256 public price;
```


### lastSettlementTime
Last time Orb keeper's funds were settled. Used to calculate amount owed since last settlement. Has no meaning
if the Orb is held by the contract.


```solidity
uint256 public lastSettlementTime;
```


### auctionStartingPrice
Auction starting price. Initial value is 0 - allows any bid.


```solidity
uint256 public auctionStartingPrice;
```


### auctionMinimumBidStep
Auction minimum bid step: required increase between bids. Each bid has to increase over previous bid by at
least this much. If trying to set as zero, will be set to 1 (wei). Initial value is also 1 wei, to disallow
equal value bids.


```solidity
uint256 public auctionMinimumBidStep;
```


### auctionMinimumDuration
Auction minimum duration: the auction will run for at least this long. Initial value is 1 day, and this value
cannot be set to zero, as it would prevent any bids from being made.


```solidity
uint256 public auctionMinimumDuration;
```


### auctionKeeperMinimumDuration
Keeper's Auction minimum duration: auction started by the keeper via `relinquishWithAuction()` will run for at
least this long. Initial value is 1 day, and this value cannot be set to zero, as it would prevent any bids
from being made.


```solidity
uint256 public auctionKeeperMinimumDuration;
```


### auctionBidExtension
Auction bid extension: if auction remaining time is less than this after a bid is made, auction will continue
for at least this long. Can be set to zero, in which case the auction will always be `auctionMinimumDuration`
long. Initial value is 5 minutes.


```solidity
uint256 public auctionBidExtension;
```


### auctionEndTime
Auction end time: timestamp when the auction ends, can be extended by late bids. 0 not during the auction.


```solidity
uint256 public auctionEndTime;
```


### leadingBidder
Leading bidder: address that currently has the highest bid. 0 not during the auction and before first bid.


```solidity
address public leadingBidder;
```


### leadingBid
Leading bid: highest current bid. 0 not during the auction and before first bid.


```solidity
uint256 public leadingBid;
```


### auctionBeneficiary
Auction Beneficiary: address that receives most of the auction proceeds. Zero address if run by creator.


```solidity
address public auctionBeneficiary;
```


### cooldown
Cooldown: how often the Orb can be invoked.


```solidity
uint256 public cooldown;
```


### flaggingPeriod
Flagging Period: for how long after an invocation the keeper can flag the response.


```solidity
uint256 public flaggingPeriod;
```


### cleartextMaximumLength
Maximum length for invocation cleartext content.


```solidity
uint256 public cleartextMaximumLength;
```


### keeperReceiveTime
Keeper receive time: when the Orb was last transferred, except to this contract.


```solidity
uint256 public keeperReceiveTime;
```


### lastInvocationTime
Last invocation time: when the Orb was last invoked. Used together with `cooldown` constant.


```solidity
uint256 public lastInvocationTime;
```


### requestedUpgradeImplementation
Requested upgrade implementation address


```solidity
address public requestedUpgradeImplementation;
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

*When deployed, contract mints the only token that will ever exist, to itself.
This token represents the Orb and is called the Orb elsewhere in the contract.
`Ownable` sets the deployer to be the `owner()`, and also the creator in the Orb context.*


```solidity
function initialize(address beneficiary_, string memory name_, string memory symbol_, string memory tokenURI_)
    public
    initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`beneficiary_`|`address`|  Address to receive all Orb proceeds.|
|`name_`|`string`|         Orb name, used in ERC-721 metadata.|
|`symbol_`|`string`|       Orb symbol or ticker, used in ERC-721 metadata.|
|`tokenURI_`|`string`|     Initial value for tokenURI JSONs.|


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


### creator

*Function exposing creator address as part of IOrb interface.*


```solidity
function creator() public view virtual returns (address creatorAddress);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`creatorAddress`|`address`| Address of the Orb creator.|


### onlyKeeper

*Ensures that the caller owns the Orb. Should only be used in conjuction with `onlyKeeperHeld` or on
external functions, otherwise does not make sense.
Contract inherits `onlyOwner` modifier from `Ownable`.*


```solidity
modifier onlyKeeper() virtual;
```

### onlyKeeperHeld

*Ensures that the Orb belongs to someone, not the contract itself.*


```solidity
modifier onlyKeeperHeld() virtual;
```

### onlyCreatorControlled

*Ensures that the Orb belongs to the contract itself or the creator, and the auction hasn't been started.
Most setting-adjusting functions should use this modifier. It means that the Orb properties cannot be
modified while it is held by the keeper or users can bid on the Orb.*


```solidity
modifier onlyCreatorControlled() virtual;
```

### notDuringAuction

*Ensures that an auction is currently not running. Can be multiple states: auction not started, auction
over but not finalized, or auction finalized.*


```solidity
modifier notDuringAuction() virtual;
```

### onlyKeeperSolvent

*Ensures that the current Orb keeper has enough funds to cover Harberger tax until now.*


```solidity
modifier onlyKeeperSolvent() virtual;
```

### balanceOf

Since there is only one token (Orb), this function only returns one for the Keeper address.


```solidity
function balanceOf(address owner_) external view virtual returns (uint256 balance);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`owner_`|`address`| Address to check balance for.|


### ownerOf

Since there is only one token (Orb), this function only returns the Keeper address if the minted
token id is provided.


```solidity
function ownerOf(uint256 tokenId_) external view virtual returns (address owner);
```

### tokenURI

Returns a fixed URL for the Orb ERC-721 metadata. `tokenId` argument is accepted for compatibility
with the ERC-721 standard but does not affect the returned URL.


```solidity
function tokenURI(uint256) external view virtual returns (string memory);
```

### approve

ERC-721 `approve()` is not supported.


```solidity
function approve(address, uint256) external virtual;
```

### setApprovalForAll

ERC-721 `setApprovalForAll()` is not supported.


```solidity
function setApprovalForAll(address, bool) external virtual;
```

### getApproved

ERC-721 `getApproved()` is not supported.


```solidity
function getApproved(uint256) external view virtual returns (address);
```

### isApprovedForAll

ERC-721 `isApprovedForAll()` is not supported.


```solidity
function isApprovedForAll(address, address) external view virtual returns (bool);
```

### transferFrom

ERC-721 `transferFrom()` is not supported.


```solidity
function transferFrom(address, address, uint256) external virtual;
```

### safeTransferFrom

ERC-721 `safeTransferFrom()` is not supported.


```solidity
function safeTransferFrom(address, address, uint256) external virtual;
```

### safeTransferFrom

ERC-721 `safeTransferFrom()` is not supported.


```solidity
function safeTransferFrom(address, address, uint256, bytes memory) external virtual;
```

### _transferOrb

*Transfers the ERC-721 token to the new address. If the new owner is not this contract (an actual user),
updates `keeperReceiveTime`. `keeperReceiveTime` is used to limit response flagging duration.*


```solidity
function _transferOrb(address from_, address to_) internal virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`from_`|`address`| Address to transfer the Orb from.|
|`to_`|`address`|   Address to transfer the Orb to.|


### swearOath

Allows re-swearing of the Orb Oath and set a new `honoredUntil` date. This function can only be called
by the Orb creator when the Orb is in their control. With `swearOath()`, `honoredUntil` date can be
decreased, unlike with the `extendHonoredUntil()` function.

*Emits `OathSwearing`.*


```solidity
function swearOath(bytes32 oathHash, uint256 newHonoredUntil, uint256 newResponsePeriod)
    external
    virtual
    onlyOwner
    onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oathHash`|`bytes32`|          Hash of the Oath taken to create the Orb.|
|`newHonoredUntil`|`uint256`|   Date until which the Orb creator will honor the Oath for the Orb keeper.|
|`newResponsePeriod`|`uint256`| Duration within which the Orb creator promises to respond to an invocation.|


### extendHonoredUntil

Allows the Orb creator to extend the `honoredUntil` date. This function can be called by the Orb
creator anytime and only allows extending the `honoredUntil` date.

*Emits `HonoredUntilUpdate`.*


```solidity
function extendHonoredUntil(uint256 newHonoredUntil) external virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newHonoredUntil`|`uint256`| Date until which the Orb creator will honor the Oath for the Orb keeper. Must be greater than the current `honoredUntil` date.|


### setTokenURI

Allows the Orb creator to replace the `baseURI`. This function can be called by the Orb creator
anytime and is meant for when the current `baseURI` has to be updated.


```solidity
function setTokenURI(string memory newTokenURI) external virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newTokenURI`|`string`| New `baseURI`, will be concatenated with the token id in `tokenURI()`.|


### setAuctionParameters

Allows the Orb creator to set the auction parameters. This function can only be called by the Orb
creator when the Orb is in their control.

*Emits `AuctionParametersUpdate`.*


```solidity
function setAuctionParameters(
    uint256 newStartingPrice,
    uint256 newMinimumBidStep,
    uint256 newMinimumDuration,
    uint256 newKeeperMinimumDuration,
    uint256 newBidExtension
) external virtual onlyOwner onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newStartingPrice`|`uint256`|         New starting price for the auction. Can be 0.|
|`newMinimumBidStep`|`uint256`|        New minimum bid step for the auction. Will always be set to at least 1.|
|`newMinimumDuration`|`uint256`|       New minimum duration for the auction. Must be > 0.|
|`newKeeperMinimumDuration`|`uint256`| New minimum duration for the auction is started by the keeper via `relinquishWithAuction()`. Setting to 0 effectively disables keeper auctions.|
|`newBidExtension`|`uint256`|          New bid extension for the auction. Can be 0.|


### setFees

Allows the Orb creator to set the new keeper tax and royalty. This function can only be called by the
Orb creator when the Orb is in their control.

*Emits `FeesUpdate`.*


```solidity
function setFees(uint256 newKeeperTaxNumerator, uint256 newRoyaltyNumerator)
    external
    virtual
    onlyOwner
    onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newKeeperTaxNumerator`|`uint256`| New keeper tax numerator, in relation to `feeDenominator()`.|
|`newRoyaltyNumerator`|`uint256`|   New royalty numerator, in relation to `feeDenominator()`. Cannot be larger than `feeDenominator()`.|


### setCooldown

Allows the Orb creator to set the new cooldown duration and flagging period - duration for how long
Orb keeper may flag a response. This function can only be called by the Orb creator when the Orb is in
their control.

*Emits `CooldownUpdate`.*


```solidity
function setCooldown(uint256 newCooldown, uint256 newFlaggingPeriod) external virtual onlyOwner onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCooldown`|`uint256`|       New cooldown in seconds. Cannot be longer than `COOLDOWN_MAXIMUM_DURATION`.|
|`newFlaggingPeriod`|`uint256`| New flagging period in seconds.|


### setCleartextMaximumLength

Allows the Orb creator to set the new cleartext maximum length. This function can only be called by
the Orb creator when the Orb is in their control.

*Emits `CleartextMaximumLengthUpdate`.*


```solidity
function setCleartextMaximumLength(uint256 newCleartextMaximumLength)
    external
    virtual
    onlyOwner
    onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCleartextMaximumLength`|`uint256`| New cleartext maximum length. Cannot be 0.|


### _auctionRunning

*Returns if the auction is currently running. Use `auctionEndTime()` to check when it ends.*


```solidity
function _auctionRunning() internal view virtual returns (bool isAuctionRunning);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isAuctionRunning`|`bool`| If the auction is running.|


### _minimumBid

*Minimum bid that would currently be accepted by `bid()`. `auctionStartingPrice` if no bids were made,
otherwise the leading bid increased by `auctionMinimumBidStep`.*


```solidity
function _minimumBid() internal view virtual returns (uint256 auctionMinimumBid);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`auctionMinimumBid`|`uint256`| Minimum bid required for `bid()`.|


### startAuction

Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.

*Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
after auction is finalized. Emits `AuctionStart`.*


```solidity
function startAuction() external virtual onlyOwner notDuringAuction;
```

### bid

Bids the provided amount, if there's enough funds across funds on contract and transaction value.
Might extend the auction if bidding close to auction end. Important: the leading bidder will not be
able to withdraw any funds until someone outbids them or the auction is finalized.

*Emits `AuctionBid`.*


```solidity
function bid(uint256 amount, uint256 priceIfWon) external payable virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|     The value to bid.|
|`priceIfWon`|`uint256`| Price if the bid wins. Must be less than `MAXIMUM_PRICE`.|


### finalizeAuction

Finalizes the auction, transferring the winning bid to the beneficiary, and the Orb to the winner.
If the auction was started by previous Keeper with `relinquishWithAuction()`, then most of the auction
proceeds (minus the royalty) will be sent to the previous Keeper. Sets `lastInvocationTime` so that
the Orb could be invoked immediately. The price has been set when bidding, now becomes relevant. If no
bids were made, resets the state to allow the auction to be started again later.

*Critical state transition function. Called after `auctionEndTime`, but only if it's not 0. Can be
called by anyone, although probably will be called by the creator or the winner. Emits `PriceUpdate`
and `AuctionFinalization`.*


```solidity
function finalizeAuction() external virtual notDuringAuction;
```

### deposit

Allows depositing funds on the contract. Not allowed for insolvent keepers.

*Deposits are not allowed for insolvent keepers to prevent cheating via front-running. If the user
becomes insolvent, the Orb will always be returned to the contract as the next step. Emits `Deposit`.*


```solidity
function deposit() external payable virtual;
```

### withdrawAll

Function to withdraw all funds on the contract. Not recommended for current Orb keepers if the price
is not zero, as they will become immediately foreclosable. To give up the Orb, call `relinquish()`.

*Not allowed for the leading auction bidder.*


```solidity
function withdrawAll() external virtual;
```

### withdraw

Function to withdraw given amount from the contract. For current Orb keepers, reduces the time until
foreclosure.

*Not allowed for the leading auction bidder.*


```solidity
function withdraw(uint256 amount) external virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`| The amount to withdraw.|


### withdrawAllForBeneficiary

Function to withdraw all beneficiary funds on the contract. Settles if possible.

*Allowed for anyone at any time, does not use `msg.sender` in its execution.*


```solidity
function withdrawAllForBeneficiary() external virtual;
```

### settle

Settlements transfer funds from Orb keeper to the beneficiary. Orb accounting minimizes required
transactions: Orb keeper's foreclosure time is only dependent on the price and available funds. Fund
transfers are not necessary unless these variables (price, keeper funds) are being changed. Settlement
transfers funds owed since the last settlement, and a new period of virtual accounting begins.

*See also `_settle()`.*


```solidity
function settle() external virtual onlyKeeperHeld;
```

### keeperSolvent

*Returns if the current Orb keeper has enough funds to cover Harberger tax until now. Always true if
creator holds the Orb.*


```solidity
function keeperSolvent() public view virtual returns (bool isKeeperSolvent);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`isKeeperSolvent`|`bool`| If the current keeper is solvent.|


### feeDenominator

*Returns the accounting base for Orb fees (Harberger tax rate and royalty).*


```solidity
function feeDenominator() external pure virtual returns (uint256 feeDenominatorValue);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`feeDenominatorValue`|`uint256`| The accounting base for Orb fees.|


### keeperTaxPeriod

*Returns the Harberger tax period base. Keeper tax is for each of this period.*


```solidity
function keeperTaxPeriod() external pure virtual returns (uint256 keeperTaxPeriodSeconds);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`keeperTaxPeriodSeconds`|`uint256`| How long is the Harberger tax period, in seconds.|


### _owedSinceLastSettlement

*Calculates how much money Orb keeper owes Orb beneficiary. This amount would be transferred between
accounts during settlement. **Owed amount can be higher than keeper's funds!** It's important to check
if keeper has enough funds before transferring.*


```solidity
function _owedSinceLastSettlement() internal view virtual returns (uint256 owedValue);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`owedValue`|`uint256`| Wei Orb keeper owes Orb beneficiary since the last settlement time.|


### _withdraw

*Executes the withdrawal for a given amount, does the actual value transfer from the contract to user's
wallet. The only function in the contract that sends value and has re-entrancy risk. Does not check if
the address is payable, as the Address library reverts if it is not. Emits `Withdrawal`.*


```solidity
function _withdraw(address recipient_, uint256 amount_) internal virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`recipient_`|`address`| The address to send the value to.|
|`amount_`|`uint256`|    The value in wei to withdraw from the contract.|


### _settle

*Keeper might owe more than they have funds available: it means that the keeper is foreclosable.
Settlement would transfer all keeper funds to the beneficiary, but not more. Does not transfer funds if
the creator holds the Orb, but always updates `lastSettlementTime`. Should never be called if Orb is
owned by the contract. Emits `Settlement`.*


```solidity
function _settle() internal virtual;
```

### setPrice

Sets the new purchase price for the Orb. Harberger tax means the asset is always for sale. The price
can be set to zero, making foreclosure time to be never. Can only be called by a solvent keeper.
Settles before adjusting the price, as the new price will change foreclosure time.

*Emits `Settlement` and `PriceUpdate`. See also `_setPrice()`.*


```solidity
function setPrice(uint256 newPrice) external virtual onlyKeeper onlyKeeperSolvent;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPrice`|`uint256`| New price for the Orb.|


### listWithPrice

Lists the Orb for sale at the given price to buy directly from the Orb creator. This is an alternative
to the auction mechanism, and can be used to simply have the Orb for sale at a fixed price, waiting
for the buyer. Listing is only allowed if the auction has not been started and the Orb is held by the
contract. When the Orb is purchased from the creator, all proceeds go to the beneficiary and the Orb
comes fully charged, with no cooldown.

*Emits `Transfer` and `PriceUpdate`.*


```solidity
function listWithPrice(uint256 listingPrice) external virtual onlyOwner;
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
royalty payments. Does not allow purchasing from yourself. Emits `PriceUpdate` and `Purchase`.*


```solidity
function purchase(
    uint256 newPrice,
    uint256 currentPrice,
    uint256 currentKeeperTaxNumerator,
    uint256 currentRoyaltyNumerator,
    uint256 currentCooldown,
    uint256 currentCleartextMaximumLength
) external payable virtual onlyKeeperHeld onlyKeeperSolvent;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPrice`|`uint256`|                      New price to use after the purchase.|
|`currentPrice`|`uint256`|                  Current price, to prevent front-running.|
|`currentKeeperTaxNumerator`|`uint256`|     Current keeper tax numerator, to prevent front-running.|
|`currentRoyaltyNumerator`|`uint256`|       Current royalty numerator, to prevent front-running.|
|`currentCooldown`|`uint256`|               Current cooldown, to prevent front-running.|
|`currentCleartextMaximumLength`|`uint256`| Current cleartext maximum length, to prevent front-running.|


### _splitProceeds

*Assigns proceeds to beneficiary and primary receiver, accounting for royalty. Used by `purchase()` and
`finalizeAuction()`. Fund deducation should happen before calling this function. Receiver might be
beneficiary if no split is needed.*


```solidity
function _splitProceeds(uint256 proceeds_, address receiver_, uint256 royalty_) internal virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`proceeds_`|`uint256`| Total proceeds to split between beneficiary and receiver.|
|`receiver_`|`address`| Address of the receiver of the proceeds minus royalty.|
|`royalty_`|`uint256`|  Beneficiary royalty numerator to use for the split.|


### _setPrice

*Does not check if the new price differs from the previous price: no risk. Limits the price to
MAXIMUM_PRICE to prevent potential overflows in math. Emits `PriceUpdate`.*


```solidity
function _setPrice(uint256 newPrice_) internal virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPrice_`|`uint256`| New price for the Orb.|


### relinquish

Relinquishment is a voluntary giving up of the Orb. It's a combination of withdrawing all funds not
owed to the beneficiary since last settlement and transferring the Orb to the contract. Keepers giving
up the Orb may start an auction for it for their own benefit. Once auction is finalized, most of the
proceeds (minus the royalty) go to the relinquishing Keeper. Alternatives to relinquisment are setting
the price to zero or withdrawing all funds. Orb creator cannot start the keeper auction via this
function, and must call `relinquish(false)` and `startAuction()` separately to run the creator
auction.

*Calls `_withdraw()`, which does value transfer from the contract. Emits `Relinquishment`,
`Withdrawal`, and optionally `AuctionStart`.*


```solidity
function relinquish(bool withAuction) external virtual onlyKeeper onlyKeeperSolvent;
```

### foreclose

Foreclose can be called by anyone after the Orb keeper runs out of funds to cover the Harberger tax.
It returns the Orb to the contract and starts a auction to find the next keeper. Most of the proceeds
(minus the royalty) go to the previous keeper.

*Emits `Foreclosure`, and optionally `AuctionStart`.*


```solidity
function foreclose() external virtual onlyKeeperHeld;
```

### setLastInvocationTime

*Allows Orb Invocation Registry to update lastInvocationTime of the Orb. It is the only Orb state
variable that can be written by the Orb Invocation Registry. The Only Orb Invocation Registry that can
update this variable is the one specified in the Orb Pond that created this Orb.*


```solidity
function setLastInvocationTime(uint256 timestamp) external virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`timestamp`|`uint256`| New value for lastInvocationTime.|


### version

Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.


```solidity
function version() public view virtual returns (uint256 orbVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`orbVersion`|`uint256`| Version of the Orb.|


### requestUpgrade

Allows the creator to request an upgrade to the next version of the Orb. Requires that the new version
is registered with the Orb Pond. The upgrade will be performed with `upgradeToNextVersion()` by the
keeper (if there is one), or the creator if the Orb is in their control. The upgrade can be cancelled
by calling this function with `address(0)` as the argument.

*Emits `UpgradeRequest`.*


```solidity
function requestUpgrade(address requestedImplementation) external virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`requestedImplementation`|`address`| Address of the new version of the Orb, or `address(0)` to cancel.|


### upgradeToNextVersion

Allows the keeper (if exists) or the creator (if in their control) to upgrade the Orb to the next
version, if the creator requested an upgrade (by calling `requestUpgrade()`) and it still matches with
the next version stored on the Orb Pond contract. Also calls the next version initializer using fixed
calldata stored on the Orb Pond contract.

*Emits `UpgradeCompletion`. Can only be called via an active proxy.*


```solidity
function upgradeToNextVersion() external virtual onlyProxy;
```

