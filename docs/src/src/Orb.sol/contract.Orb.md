# Orb
[Git Source](https://github.com/orbland/orb/blob/30160e6ff657045bbcb72ae4e8ff2292a72e5b2e/src/Orb.sol)

**Inherits:**
Ownable, ERC165, ERC721, [IOrb](/src/IOrb.sol/interface.IOrb.md)

**Authors:**
Jonas Lekevicius, Eric Wall

This is a basic Q&A-type Orb. The holder has the right to submit a text-based question to the
creator and the right to receive a text-based response. The question is limited in length but
responses may come in any length. Questions and answers are hash-committed to the Ethereum blockchain
so that the track record cannot be changed. The Orb has a cooldown.<br/>
The Orb uses Harberger Tax and is always on sale. This means that when you purchase the Orb, you must
also set a price which you’re willing to sell the Orb at. However, you must pay an amount base on tax rate
to the Orb smart contract per year in order to maintain the Orb ownership. This amount is accounted for
per second, and user funds need to be topped up before the foreclosure time to maintain ownership.

*Supports ERC-721 interface but reverts on all transfers.
Uses `Ownable`'s `owner()` to identify the creator of the Orb.
Uses `ERC721`'s `ownerOf(tokenId)` to identify the current holder of the Orb.*


## State Variables
### beneficiary
Beneficiary is another address that receives all Orb proceeds. It is set in the `constructor` as an immutable
value. Beneficiary is not allowed to bid in the auction or purchase the Orb. The intended use case for the
beneficiary is to set it to a revenue splitting contract. Proceeds that go to the beneficiary are:
- The auction winning bid amount
- Royalties from Orb purchase when not purchased from the Orb creator
- Full purchase price when purchased from the Orb creator
- Harberger tax revenue


```solidity
address public immutable beneficiary;
```


### FEE_DENOMINATOR

```solidity
uint256 internal constant FEE_DENOMINATOR = 10_000;
```


### HOLDER_TAX_PERIOD

```solidity
uint256 internal constant HOLDER_TAX_PERIOD = 365 days;
```


### tokenId

```solidity
uint256 public immutable tokenId;
```


### MAX_PRICE

```solidity
uint256 internal constant MAX_PRICE = 2 ** 128;
```


### honoredUntil

```solidity
uint256 public honoredUntil;
```


### baseURI

```solidity
string internal baseURI;
```


### fundsOf

```solidity
mapping(address => uint256) public fundsOf;
```


### holderTaxNumerator

```solidity
uint256 public holderTaxNumerator = 1_000;
```


### royaltyNumerator

```solidity
uint256 public royaltyNumerator = 1_000;
```


### price

```solidity
uint256 public price;
```


### lastSettlementTime

```solidity
uint256 public lastSettlementTime;
```


### auctionStartingPrice

```solidity
uint256 public auctionStartingPrice = 0;
```


### auctionMinimumBidStep

```solidity
uint256 public auctionMinimumBidStep = 0;
```


### auctionMinimumDuration

```solidity
uint256 public auctionMinimumDuration = 1 days;
```


### auctionBidExtension

```solidity
uint256 public auctionBidExtension = 5 minutes;
```


### auctionStartTime

```solidity
uint256 public auctionStartTime;
```


### auctionEndTime

```solidity
uint256 public auctionEndTime;
```


### leadingBidder

```solidity
address public leadingBidder;
```


### leadingBid

```solidity
uint256 public leadingBid;
```


### cooldown

```solidity
uint256 public cooldown = 7 days;
```


### cleartextMaximumLength

```solidity
uint256 public cleartextMaximumLength = 280;
```


### holderReceiveTime

```solidity
uint256 public holderReceiveTime;
```


### lastInvocationTime

```solidity
uint256 public lastInvocationTime;
```


### invocations

```solidity
mapping(uint256 => HashTime) public invocations;
```


### invocationCount

```solidity
uint256 public invocationCount = 0;
```


### responses

```solidity
mapping(uint256 => HashTime) public responses;
```


### responseFlagged

```solidity
mapping(uint256 => bool) public responseFlagged;
```


### flaggedResponsesCount

```solidity
uint256 public flaggedResponsesCount = 0;
```


## Functions
### constructor

*When deployed, contract mints the only token that will ever exist, to itself.
This token represents the Orb and is called the Orb elsewhere in the contract.
{Ownable} sets the deployer to be the owner, and also the creator in the Orb context.*


```solidity
constructor(
    string memory name_,
    string memory symbol_,
    uint256 tokenId_,
    address beneficiary_,
    bytes32 oathHash_,
    uint256 honoredUntil_,
    string memory baseURI_
) ERC721(name_, symbol_);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name_`|`string`|         Orb name, used in ERC-721 metadata.|
|`symbol_`|`string`|       Orb symbol or ticker, used in ERC-721 metadata.|
|`tokenId_`|`uint256`|      ERC-721 token ID of the Orb.|
|`beneficiary_`|`address`|  Beneficiary receives all Orb proceeds.|
|`oathHash_`|`bytes32`|     Hash of the Oath taken to create the Orb.|
|`honoredUntil_`|`uint256`| Date until which the Orb creator will honor the Oath for the Orb holder.|
|`baseURI_`|`string`||


### supportsInterface

*ERC-165 supportsInterface. Orb contract supports ERC-721 and IOrb interfaces.*


```solidity
function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC165, IERC165) returns (bool);
```

### onlyHolder

Contract inherits {onlyOwner} modifier from {Ownable}.

*Ensures that the caller owns the Orb.
Should only be used in conjuction with {onlyHolderHeld} or on external functions,
otherwise does not make sense.*


```solidity
modifier onlyHolder();
```

### onlyHolderHeld

*Ensures that the Orb belongs to someone, not the contract itself.*


```solidity
modifier onlyHolderHeld();
```

### onlyCreatorControlled

*Ensures that the Orb belongs to the contract itself or the creator.
All setting-adjusting functions should use this modifier.
It means that the Orb properties cannot be modified while it is held by the holder.*


```solidity
modifier onlyCreatorControlled();
```

### notDuringAuction

*Ensures that an auction is currently not running.
Can be multiple states: auction not started, auction over but not finalized, or auction finalized.*


```solidity
modifier notDuringAuction();
```

### onlyHolderSolvent

*Ensures that the current Orb holder has enough funds to cover Harberger tax until now.*


```solidity
modifier onlyHolderSolvent();
```

### _baseURI


```solidity
function _baseURI() internal view override returns (string memory);
```

### transferFrom

Transfers the Orb to another address. Not allowed, always reverts.

*Always reverts.*


```solidity
function transferFrom(address, address, uint256) public pure override;
```

### safeTransferFrom

*See {transferFrom()} above.*


```solidity
function safeTransferFrom(address, address, uint256) public pure override;
```

### safeTransferFrom

*See {transferFrom()} above.*


```solidity
function safeTransferFrom(address, address, uint256, bytes memory) public pure override;
```

### _transferOrb

Transfers the ERC-20 token to the new address.
If the new owner is not this contract (an actual user), updates holderReceiveTime.
holderReceiveTime is used to limit response flagging window.


```solidity
function _transferOrb(address from_, address to_) internal;
```

### swearOath

Allows re-swearing of the oath and set a new honoredUntil date.
This function can only be called by the Orb creator when the Orb is not held by anyone.
HonoredUntil date can be decreased, unlike with the {extendHonoredUntil()} function.

*Emits {OathSwearing} event.*


```solidity
function swearOath(bytes32 oathHash, uint256 newHonoredUntil) external onlyOwner onlyCreatorControlled;
```

### extendHonoredUntil

Allows the Orb creator to extend the honoredUntil date.
This function can be called by the Orb creator anytime and only allows extending
the honoredUntil date.

*Emits {HonoredUntilUpdate} event.*


```solidity
function extendHonoredUntil(uint256 newHonoredUntil) external onlyOwner;
```

### setBaseURI

Allows the Orb creator to replace the baseURI.
This function can be called by the Orb creator anytime and is meant for
when the current baseURI has to be updated.


```solidity
function setBaseURI(string memory newBaseURI) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newBaseURI`|`string`| New baseURI, will be concatenated with the token ID.|


### setAuctionParameters

Allows the Orb creator to set the auction parameters.
This function can only be called by the Orb creator when the Orb is not held by anyone.

*Emits {AuctionParametersUpdate} event.*


```solidity
function setAuctionParameters(
    uint256 newStartingPrice,
    uint256 newMinimumBidStep,
    uint256 newMinimumDuration,
    uint256 newBidExtension
) external onlyOwner onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newStartingPrice`|`uint256`|   New starting price for the auction. Can be 0.|
|`newMinimumBidStep`|`uint256`|  New minimum bid step for the auction. Can be 0.|
|`newMinimumDuration`|`uint256`| New minimum duration for the auction. Must be > 0.|
|`newBidExtension`|`uint256`|    New bid extension for the auction. Can be 0.|


### setFees

Allows the Orb creator to set the new holder tax and royalty.
This function can only be called by the Orb creator when the Orb is not held by anyone.

*Emits FeesUpdate() event.*


```solidity
function setFees(uint256 newHolderTaxNumerator, uint256 newRoyaltyNumerator) external onlyOwner onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newHolderTaxNumerator`|`uint256`| New holder tax numerator, in relation to FEE_DENOMINATOR.|
|`newRoyaltyNumerator`|`uint256`|   New royalty numerator, in relation to FEE_DENOMINATOR.|


### setCooldown

Allows the Orb creator to set the new cooldown duration.
This function can only be called by the Orb creator when the Orb is not held by anyone.

*Emits CooldownUpdate() event.*


```solidity
function setCooldown(uint256 newCooldown) external onlyOwner onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCooldown`|`uint256`| New cooldown in seconds.|


### setCleartextMaximumLength

Allows the Orb creator to set the new cleartext maximum length.
This function can only be called by the Orb creator when the Orb is not held by anyone.

*Emits CleartextMaximumLengthUpdate() event.*


```solidity
function setCleartextMaximumLength(uint256 newCleartextMaximumLength) external onlyOwner onlyCreatorControlled;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newCleartextMaximumLength`|`uint256`| New cleartext maximum length.|


### auctionRunning

Returns if the auction is currently running. Use auctionEndTime() to check when it ends.

*Start time will always be less than timestamp, as it resets to 0.
Start time is only updated for auction progress tracking, not critical functionality.*


```solidity
function auctionRunning() public view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool  If the auction is running.|


### minimumBid

Minimum bid that would currently be accepted by {bid()}.

*auctionStartingPrice if no bids were made, otherwise previous bid increased by auctionMinimumBidStep.*


```solidity
function minimumBid() public view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256  Minimum bid required for {bid()}.|


### startAuction

Allow the Orb creator to start the Orb Auction. Will run for at least auctionMinimumDuration.

*Prevents repeated starts by checking the auctionEndTime.
Important to set auctionEndTime to 0 after auction is finalized.
Also, resets leadingBidder and leadingBid.
Should not be necessary, as {finalizeAuction()} also does that.
Emits AuctionStart().*


```solidity
function startAuction() external onlyOwner notDuringAuction;
```

### bid

Bids the provided amount, if there's enough funds across funds on contract and transaction value.
Might extend the auction if the bid is near the end.
Important: the leading bidder will not be able to withdraw funds until someone outbids them.

*Emits AuctionBid().*


```solidity
function bid(uint256 amount, uint256 priceIfWon) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|     The value to bid.|
|`priceIfWon`|`uint256`| Price if the bid wins. Must be less than MAX_PRICE.|


### finalizeAuction

Finalizes the Auction, transferring the winning bid to the beneficiary, and the Orb to the winner.
Sets lastInvocationTime so that the Orb could be invoked immediately.
The price has been set when bidding, now becomes relevant.
If no bids were made, resets the state to allow the auction to be started again later.

*Critical state transition function. Called after auctionEndTime, but only if it's not 0.
Can be called by anyone, although probably will be called by the creator or the winner.
Emits PriceUpdate() and AuctionFinalization().*


```solidity
function finalizeAuction() external notDuringAuction;
```

### deposit

Allows depositing funds on the contract. Not allowed for insolvent holders.

*Deposits are not allowed for insolvent holders to prevent cheating via front-running.
If the user becomes insolvent, the Orb will always be returned to the contract as the next step.
Emits Deposit().*


```solidity
function deposit() external payable;
```

### withdrawAll

Function to withdraw all funds on the contract.
Not recommended for current Orb holders, they should call relinquish() to take out their funds.

*Not allowed for the leading auction bidder.*


```solidity
function withdrawAll() external;
```

### withdraw

Function to withdraw given amount from the contract.
For current Orb holders, reduces the time until foreclosure.

*Not allowed for the leading auction bidder.*


```solidity
function withdraw(uint256 amount) external;
```

### withdrawAllForBeneficiary

Function to withdraw all beneficiary funds on the contract.

*Allowed for anyone at any time, does not use msg.sender in its execution.*


```solidity
function withdrawAllForBeneficiary() external;
```

### settle

Settlements transfer funds from Orb holder to the beneficiary.
Orb accounting minimizes required transactions: Orb holder's foreclosure time is only
dependent on the price and available funds. Fund transfers are not necessary unless
these variables (price, holder funds) are being changed. Settlement transfers funds owed
since the last settlement, and a new period of virtual accounting begins.

*Holder might owe more than they have funds available: it means that the holder is foreclosable.
Settlement would transfer all holder funds to the beneficiary, but not more.
Does nothing if the creator holds the Orb. Reverts if contract holds the Orb.
Emits Settlement().*


```solidity
function settle() external onlyHolderHeld;
```

### holderSolvent

*Returns if the current Orb holder has enough funds to cover Harberger tax until now.
Always true is creator holds the Orb.*


```solidity
function holderSolvent() public view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool  If the current holder is solvent.|


### feeDenominator

*Returns the accounting base for Orb fees (Harberger tax rate and royalty).*


```solidity
function feeDenominator() external pure returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256  The accounting base for Orb fees.|


### holderTaxPeriod

*Returns the Harberger tax period base. Holder tax is for each of this period.*


```solidity
function holderTaxPeriod() external pure returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|uint256  How long is the Harberger tax period, in seconds.|


### _owedSinceLastSettlement

*Calculates how much money Orb holder owes Orb beneficiary. This amount would be transferred between
accounts during settlement.
Owed amount can be higher than hodler's funds! It's important to check if holder has enough funds
before transferring.*


```solidity
function _owedSinceLastSettlement() internal view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|bool  Wei Orb holder owes Orb beneficiary since the last settlement time.|


### _withdraw

*Executes the withdrawal for a given amount, does the actual value transfer from the contract
to user's wallet. The only function in the contract that sends value and has re-entrancy risk.
Does not check if the address is payable, as the Address library reverts if it is not.
Emits Withdrawal().*


```solidity
function _withdraw(address recipient_, uint256 amount_) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`recipient_`|`address`| The address to send the value to.|
|`amount_`|`uint256`|    The value in wei to withdraw from the contract.|


### _settle

*See {settle()}.*


```solidity
function _settle() internal;
```

### setPrice

Sets the new purchase price for the Orb. Harberger tax means the asset is always for sale.
The price can be set to zero, making foreclosure time to be never.

*Can only be called by a solvent holder.
Settles before adjusting the price, as the new price will change foreclosure time.
Does not check if the new price differs from the previous price: no risk.
Limits the price to MAX_PRICE to prevent potential overflows in math.
Emits PriceUpdate().*


```solidity
function setPrice(uint256 newPrice) external onlyHolder onlyHolderSolvent;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newPrice`|`uint256`| New price for the Orb.|


### listWithPrice

Lists the Orb for sale at the given price to buy directly from the Orb creator.
This is an alternative to the auction mechanism, and can be used to simply have the Orb for sale
at a fixed price, waiting for the buyer.
Listing is only allowed if the auction has not been started and the Orb is held by the contract.
When the Orb is purchased from the creator, all proceeds go to the beneficiary and the Orb comes
fully charged, with no cooldown.

*Emits Transfer() and PriceUpdate().*


```solidity
function listWithPrice(uint256 listingPrice) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`listingPrice`|`uint256`| The price to buy the Orb from the creator.|


### purchase

Purchasing is the mechanism to take over the Orb. With Harberger tax, the Orb can always be
purchased from its holder.
Purchasing is only allowed while the holder is solvent. If not, the Orb has to be foreclosed and
re-auctioned.
Purchaser is required to have more funds than the price itself, but the exact amount is left for the
user interface implementation to calculate and send along.
Purchasing sends sale royalty part to the beneficiary.

*Requires to provide the current price as the first parameter to prevent front-running: without current
price requirement someone could purchase the Orb ahead of someone else, set the price higher, and
profit from the purchase.
Does not modify last invocation time, unlike buying from the auction.
Does not allow purchasing from yourself.
Emits PriceUpdate() and Purchase().*


```solidity
function purchase(uint256 currentPrice, uint256 newPrice) external payable onlyHolderHeld onlyHolderSolvent;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currentPrice`|`uint256`| Current price, to prevent front-running.|
|`newPrice`|`uint256`|     New price to use after the purchase.|


### _setPrice

*See {setPrice()}.*


```solidity
function _setPrice(uint256 newPrice_) internal;
```

### relinquish

Relinquishment is a voluntary giving up of the Orb. It's a combination of withdrawing all funds
not owed to the beneficiary since last settlement, and foreclosing yourself after.
Most useful if the creator themselves hold the Orb and want to re-auction it.
For any other holder, setting the price to zero would be more practical.

*Calls _withdraw(), which does value transfer from the contract.
Emits Foreclosure() and Withdrawal().*


```solidity
function relinquish() external onlyHolder onlyHolderSolvent;
```

### foreclose

Foreclose can be called by anyone after the Orb holder runs out of funds to cover the Harberger tax.
It returns the Orb to the contract, readying it for re-auction.

*Emits Foreclosure().*


```solidity
function foreclose() external onlyHolderHeld;
```

### invokeWithCleartext

Invokes the Orb. Allows the holder to submit cleartext.


```solidity
function invokeWithCleartext(string memory cleartext) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`cleartext`|`string`| Required cleartext.|


### invokeWithHash

Invokes the Orb. Allows the holder to submit content hash, that represents a question to the Orb
creator. Puts the Orb on cooldown. The Orb can only be invoked by solvent holders.

*Content hash is keccak256 of the cleartext.
invocationCount is used to track the id of the next invocation.
Emits Invocation().*


```solidity
function invokeWithHash(bytes32 contentHash) public onlyHolder onlyHolderHeld onlyHolderSolvent;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contentHash`|`bytes32`| Required keccak256 hash of the cleartext.|


### recordInvocationCleartext

Function allows the holder to reveal cleartext later, either because it was challenged by the
creator, or just for posterity. This function can also be used to reveal empty-string content hashes.

*Only holders can reveal cleartext on-chain. Anyone could potentially figure out the invocation
cleartext from the content hash via brute force, but publishing this on-chain is only allowed by the
holder themselves, introducing a reasonable privacy protection.
If the content hash is of a cleartext that is longer than maximum cleartext length, the contract will
never record this cleartext, as it is invalid.
Allows overwriting. Assuming no hash collisions, this poses no risk, just wastes holder gas.*


```solidity
function recordInvocationCleartext(uint256 invocationId, string memory cleartext)
    external
    onlyHolder
    onlyHolderSolvent;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invocationId`|`uint256`| Invocation id, matching the one that was emitted when calling {invokeWithCleartext()} or {invokeWithHash()}.|
|`cleartext`|`string`|    Cleartext, limited in length. Must match the content hash.|


### respond

The Orb creator can use this function to respond to any existing invocation, no matter how long ago
it was made. A response to an invocation can only be written once. There is no way to record response
cleartext on-chain.

*Emits Response().*


```solidity
function respond(uint256 invocationId, bytes32 contentHash) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invocationId`|`uint256`| ID of an invocation to which the response is being made.|
|`contentHash`|`bytes32`|  keccak256 hash of the response text.|


### flagResponse

Orb holder can flag a response during Response Flagging Period, counting from when the response is made.
Flag indicates a "report", that the Orb holder was not satisfied with the response provided.
This is meant to act as a social signal to future Orb holders. It also increments flaggedResponsesCount,
allowing anyone to quickly look up how many responses were flagged.

*Only existing responses (with non-zero timestamps) can be flagged.
Responses can only be flagged by solvent holders to keep it consistent with {invokeWithHash()} or
{invokeWithCleartext()}.
Also, the holder must have received the Orb after the response was made;
this is to prevent holders from flagging responses that were made in response to others' invocations.
Emits ResponseFlagging().*


```solidity
function flagResponse(uint256 invocationId) external onlyHolder onlyHolderSolvent;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invocationId`|`uint256`| ID of an invocation to which the response is being flagged.|


### _responseExists

*Returns if a response to an invocation exists, based on the timestamp of the response being non-zero.*


```solidity
function _responseExists(uint256 invocationId_) internal view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`invocationId_`|`uint256`| ID of an invocation to which to check the existance of a response of.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|bool  If a response to an invocation exists or not.|


## Structs
### HashTime

```solidity
struct HashTime {
    bytes32 contentHash;
    uint256 timestamp;
}
```

