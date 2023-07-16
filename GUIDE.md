# Orb Guide

This is pretty much everything you need to know about setting up your Orb: all the settings, options and requirements.

## Orb Creation

**Your Ethereum address**

This address will be the Creator of the Orb. You will receive revenue to it, and use it to submit responses.

It can be changed later by transferring Orb ownership to another wallet, but access cannot be restored if it's lost. You will need to be able to connect to our web3 app with that wallet and sign messages, so ideally your wallet should support Metamask or WalletConnect.

Your address will show up in Orb history, so if you have an ENS name, set it as a primary name to show up as your ENS, not just a hash.

**Orb name and symbol**

We suggest "NameOrb", for example "EricOrb", and "ORB" as symbol. It will show up on Etherscan.

A nicer name, likes "Eric's Orb" is also needed, for ERC-721 metadata and the Orb UI.

**Orb beneficiary**

This will be automatically set for you. It is an contract that receives all Orb proceeds and splits it based on shares set during creation. Shares or beneficiary payees are immutable, and cannot be changed.

## Orb Settings

These settings can be changed later, but only if you (Creator, and not any Keeper) control the Orb.

### Auction Settings

Note: Orb has two types of auctions: Creator auction and Keeper auction. As a Creator, you can start Creator auction for initial sale of the Orb. All the revenue goes to your Orb beneficiary. Keeper auctions can be started by Orb holders who want to give up the Orb and find the next holder: majority of the proceeds from these auction go to the previous Keeper (minus royalty percentage, see below).

- **Starting price** - minimum initial bid people can make in the Orb auction. Applies to both Creator and Keeper auctions. (In contract set as wei)
- **Minimum bid step** - by at least how much each bid must be higher. Set to something reasonable to prevent spam bids. (In contract set as wei)
- **Minimum Creator auction duration** - for how long Creator auctions should run for. Can be extended slightly by late bids, defined below. (In contract set as seconds)
- **Minimum Keeper auction duration** - same, but for Keeper auctions. If set to zero, Keeper auctions are disabled. (In contract set as seconds)
- **Late auction bids extension** - a period at the end of the auction, during which bids extend the auction. For example, if it is set to 5 minutes, and bid arrives with with 3 minutes remaining, auction end will be pushed by 2 minutes — to leave at least 5 minutes between last bid and auction end. (In contract set as seconds)

### Fee Settings

- **Keeper tax, or Harberger tax** - how many percent of the Keeper-set Orb price they have to pay per year to maintain ownership. For example, if it's set to 10%, and Orb price is set to 10 ETH, Keeper has to pay 1 ETH / year. If tax rate is 1200%, Keeper pays their set Orb price each month to maintain ownership. (In contract set as basis points, 10 000 = 100%)
- **Royalty** - percentage of how much of the Orb purchase price or Keeper auction proceeds go to the beneficiary. If set to 10% and Orb is purchased from a Keeper for 10 ETH, 1 ETH would go the beneficiary. Cannot be more than 100%, lol. (In contract set as basis points, 1 000 = 10%)

### Cooldown Settings

- **Cooldown duration** - how often the Orb can be invoked by the Keeper. Orb comes fully charged (ready to be invoked) after a Creator auction. (In contract set as seconds)
- **Flagging duration** - how long after a response has been made can a Keeper "flag" it — publicly mark it as unacceptable. If a response is private and gets flagged, Creator always has the right to reveal it. Can be set to zero to disable flagging. (In contract set as seconds)

### Invocation Settings

- **Invocation maximum length** - how long of a question do you accept. Cannot be zero, lol. (In contract stored as a number of bytes in string)

## Orb Oath

Orb Oath has elements that are set off-chain and hashed, and elements that get submitted on-chain, including the hash of off-chain elements. All aspects of the Oath can be changed be re-swearing, but only when Orb is in Creator's controlled (not owned by a Keeper).

### Oath and Terms

- **Orb Oath** - a text that will be clearly visible on the Orb page, a verbalization of the Orb promise. There are no limits of what it can or has to say. It can have newlines, and supports markdown. Here's Eric's:

```
I, Eric Wall, solemnly swear to honor my Orb as far as my eyes, my arms and my mind serve me. I shall answer any question dutifully—as long as I do not violate any law or ethical conduct, or put myself or others into danger by doing so. The sum of my collected knowledge and wisdom is at your disposal. This is my Orb, and I shall bear no other Orbs of this kind under the reign of this Orb.
```

- **Terms** - an addendum to the Orb Oath that will be less visible and can be less exciting, spelling out edge cases, invocation limitations, allowed topics, etc. It can also be any length, with multiple paragraphs, and supports markdown.
- **Timestamp** - mostly added for hash uniqueness, but also signifies when the Oath was written.

### Policies

All policies are set as boolean (true / false).

- **Allow Public Invocations** - are public Keeper questions allowed? If false, all invocations will be private.
- **Allow Private Invocations** - are public Keeper questions allowed? If false, all invocations will be public. Not compatible with "Allow Public Invocations - false".
- **Allow Private Responses** - can Creator responses be private? If false, all responses will have to be public, and therefore not compatible with "Allow Private Invocations - true". If true, Keepers will have a choice to request a private response - then the response will have to private. If not requested by the Keeper, Creator can still choose to make a response private.
- **Allow Read Past Invocations** - can Keepers read private questions of previous Keepers and responses to these questions? If false, then only the Keeper that asks a private question will ever have access to a response - no one else will, even if this policy is later changed. Reduces Orb value to future Keepers.
- **Allow Reveal Own Invocations** - can Keepers publicly (on the Orb page) reveal a private question or a response to their *own* invocation? If false, what's private stays private.
- **Allow Reveal Past Invocations** - can Keepers also publicly reveal a private question or a response to an invocation of a previous Keeper? Can only be true if "Allow Reveal Own Invocations" is also true.

### On-chain Elements

All previous elements are put into a JSON and `keccak256` hashed to produce an Oath Hash. This hash is submitted on-chain together with:

- **Honored Until date** - timestamp (in seconds) until which the Oath will be honored by its Creator. Keepers invoking the Orb after that date are informed that they might not receive a response, as the Orb is no longer honored. Can be pushed further into the future any time, even if not owned by Creator.
- **Response duration** - how quickly should Keepers expect a response after an invocation is made. Currently there is no smart contract logic around this duration, but the UI will highlight if a response is made late. (In contract set as seconds)

## Orb Configuration

Lastly, there are elements that can be changed any time and only concern with the UI.

- **URL** - What should be URL of the orb, defined as a subdomain: XXX.orb.land.
- **Name** - Orb's nice name, like "Eric's Orb"
- **Type** - Currently always "Text Q&A"
- **Creator's Name** - Just the name, like "Eric". Used in the UI like "Eric gives himself 7 days to respond".
- **Creator's Twitter** - Twitter username, used to encourage following there.
- **Expected Auction Start Date** - Orb can launch with a countdown when the auction is expected to start. As a creator you still have to submit `startAuction` transaction. This date and time is just for visitor interest.
