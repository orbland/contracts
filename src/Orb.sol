// SPDX-License-Identifier: MIT
/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - *
.                                                                                                                      .
.                                                                                                                      .
.                                             ./         (@@@@@@@@@@@@@@@@@,                                           .
.                                        &@@@@       /@@@@&.        *&@@@@@@@@@@*                                      .
.                                    %@@@@@@.      (@@@                  &@@@@@@@@@&                                   .
.                                 .@@@@@@@@       @@@                      ,@@@@@@@@@@/                                .
.                               *@@@@@@@@@       (@%                         &@@@@@@@@@@/                              .
.                              @@@@@@@@@@/       @@                           (@@@@@@@@@@@                             .
.                             @@@@@@@@@@@        &@                            %@@@@@@@@@@@                            .
.                            @@@@@@@@@@@#         @                             @@@@@@@@@@@@                           .
.                           #@@@@@@@@@@@.                                       /@@@@@@@@@@@@                          .
.                           @@@@@@@@@@@@                                         @@@@@@@@@@@@                          .
.                           @@@@@@@@@@@@                                         @@@@@@@@@@@@                          .
.                           @@@@@@@@@@@@.                                        @@@@@@@@@@@@                          .
.                           @@@@@@@@@@@@%                                       ,@@@@@@@@@@@@                          .
.                           ,@@@@@@@@@@@@                                       @@@@@@@@@@@@/                          .
.                            %@@@@@@@@@@@&                                     .@@@@@@@@@@@@                           .
.                             #@@@@@@@@@@@#                                    @@@@@@@@@@@&                            .
.                              .@@@@@@@@@@@&                                 ,@@@@@@@@@@@,                             .
.                                *@@@@@@@@@@@,                              @@@@@@@@@@@#                               .
.                                   @@@@@@@@@@@*                          @@@@@@@@@@@.                                 .
.                                     .&@@@@@@@@@@*                   .@@@@@@@@@@@.                                    .
.                                          &@@@@@@@@@@@%*..   ..,#@@@@@@@@@@@@@*                                       .
.                                        ,@@@@   ,#&@@@@@@@@@@@@@@@@@@#*     &@@@#                                     .
.                                       @@@@@                                 #@@@@.                                   .
.                                      @@@@@*                                  @@@@@,                                  .
.                                     @@@@@@@(                               .@@@@@@@                                  .
.                                     (@@@@@@@@@@@@@@%/*,.       ..,/#@@@@@@@@@@@@@@@                                  .
.                                        #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%                                     .
.                                                ./%@@@@@@@@@@@@@@@@@@@%/,                                             .
.                                                                                                                      .
.                                                                                                                      .
* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */
pragma solidity ^0.8.17;

import {IOrb} from "src/IOrb.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title   Orb - Harberger-taxed NFT with auction and on-chain invocations and responses
/// @author  Jonas Lekevicius
/// @author  Eric Wall
/// @notice  This is a basic Q&A-type Orb. The keeper has the right to submit a text-based question to the creator and
///          the right to receive a text-based response. The question is limited in length but responses may come in
///          any length. Questions and answers are hash-committed to the blockchain so that the track record cannot be
///          changed. The Orb has a cooldown.
///          The Orb uses Harberger tax and is always on sale. This means that when you purchase the Orb, you must also
///          set a price which you’re willing to sell the Orb at. However, you must pay an amount based on tax rate to
///          the Orb contract per year in order to maintain the Orb ownership. This amount is accounted for per second,
///          and user funds need to be topped up before the foreclosure time to maintain ownership.
/// @dev     Supports ERC-721 interface but reverts on all transfers. Uses `Ownable`'s `owner()` to identify the
///          creator of the Orb. Uses `ERC721`'s `ownerOf(tokenId)` to identify the current keeper of the Orb.
contract Orb is Ownable, ERC165, ERC721, IOrb {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS AND IMMUTABLES

    /// Beneficiary is another address that receives all Orb proceeds. It is set in the `constructor` as an immutable
    /// value. Beneficiary is not allowed to bid in the auction or purchase the Orb. The intended use case for the
    /// beneficiary is to set it to a revenue splitting contract. Proceeds that go to the beneficiary are:
    /// - The auction winning bid amount;
    /// - Royalties from Orb purchase when not purchased from the Orb creator;
    /// - Full purchase price when purchased from the Orb creator;
    /// - Harberger tax revenue.
    address public immutable beneficiary;

    /// Orb ERC-721 token number. Can be whatever arbitrary number, only one token will ever exist. Made public to
    /// allow easier lookups of Orb keeper.
    uint256 public immutable tokenId;

    // Internal Constants

    /// Fee Nominator: basis points (100.00%). Other fees are in relation to this, and formatted as such.
    uint256 internal constant FEE_DENOMINATOR = 100_00;
    /// Harberger tax period: for how long the tax rate applies. Value: 1 year.
    uint256 internal constant KEEPER_TAX_PERIOD = 365 days;
    /// Maximum cooldown duration, to prevent potential underflows. Value: 10 years.
    uint256 internal constant COOLDOWN_MAXIMUM_DURATION = 3650 days;
    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant MAXIMUM_PRICE = 2 ** 128;

    // STATE

    /// Honored Until: timestamp until which the Orb Oath is honored for the keeper.
    uint256 public honoredUntil;
    /// Response Period: time period in which the keeper promises to respond to an invocation.
    /// There are no penalties for being late within this contract.
    uint256 public responsePeriod;

    /// Base URI for tokenURI JSONs. Initially set in the `constructor` and setable with `setBaseURI()`.
    string internal baseURI;

    /// Funds tracker, per address. Modified by deposits, withdrawals and settlements. The value is without settlement.
    /// It means effective user funds (withdrawable) would be different for keeper (subtracting
    /// `_owedSinceLastSettlement()`) and beneficiary (adding `_owedSinceLastSettlement()`). If Orb is held by the
    /// creator, funds are not subtracted, as Harberger tax does not apply to the creator.
    mapping(address => uint256) public fundsOf;

    // Fees State Variables

    /// Harberger tax for holding. Initial value is 10.00%.
    uint256 public keeperTaxNumerator = 10_00;
    /// Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 10.00%.
    uint256 public royaltyNumerator = 10_00;
    /// Price of the Orb. Also used during auction to store future purchase price. Has no meaning if the Orb is held by
    /// the contract and the auction is not running.
    uint256 public price;
    /// Last time Orb keeper's funds were settled. Used to calculate amount owed since last settlement. Has no meaning
    /// if the Orb is held by the contract.
    uint256 public lastSettlementTime;

    // Auction State Variables

    /// Auction starting price. Initial value is 0 - allows any bid.
    uint256 public auctionStartingPrice;
    /// Auction minimum bid step: required increase between bids. Each bid has to increase over previous bid by at
    /// least this much. If trying to set as zero, will be set to 1 (wei). Initial value is also 1 wei, to disallow
    /// equal value bids.
    uint256 public auctionMinimumBidStep = 1;
    /// Auction minimum duration: the auction will run for at least this long. Initial value is 1 day, and this value
    /// cannot be set to zero, as it would prevent any bids from being made.
    uint256 public auctionMinimumDuration = 1 days;
    /// Keeper's Auction minimum duration: auction started by the keeper via `relinquishWithAuction()` will run for at
    /// least this long. Initial value is 1 day, and this value cannot be set to zero, as it would prevent any bids
    /// from being made.
    uint256 public auctionKeeperMinimumDuration = 1 days;
    /// Auction bid extension: if auction remaining time is less than this after a bid is made, auction will continue
    /// for at least this long. Can be set to zero, in which case the auction will always be `auctionMinimumDuration`
    /// long. Initial value is 5 minutes.
    uint256 public auctionBidExtension = 5 minutes;
    /// Auction end time: timestamp when the auction ends, can be extended by late bids. 0 not during the auction.
    uint256 public auctionEndTime;
    /// Leading bidder: address that currently has the highest bid. 0 not during the auction and before first bid.
    address public leadingBidder;
    /// Leading bid: highest current bid. 0 not during the auction and before first bid.
    uint256 public leadingBid;
    /// Auction Beneficiary: address that receives most of the auction proceeds. Zero address if run by creator.
    address public auctionBeneficiary;

    // Invocation and Response State Variables

    /// Structs used to track invocation and response information: keccak256 content hash and block timestamp.
    /// InvocationData is used to determine if the response can be flagged by the keeper.
    /// Invocation timestamp is tracked for the benefit of other contracts.
    struct InvocationData {
        address invoker;
        // keccak256 hash of the cleartext
        bytes32 contentHash;
        uint256 timestamp;
    }

    struct ResponseData {
        // keccak256 hash of the cleartext
        bytes32 contentHash;
        uint256 timestamp;
    }

    /// Cooldown: how often the Orb can be invoked.
    uint256 public cooldown = 7 days;
    /// Flagging Period: for how long after an invocation the keeper can flag the response.
    uint256 public flaggingPeriod = 7 days;
    /// Maximum length for invocation cleartext content.
    uint256 public cleartextMaximumLength = 280;
    /// Keeper receive time: when the Orb was last transferred, except to this contract.
    uint256 public keeperReceiveTime;
    /// Last invocation time: when the Orb was last invoked. Used together with `cooldown` constant.
    uint256 public lastInvocationTime;

    /// Mapping for invocations: invocationId to InvocationData struct. InvocationId starts at 1.
    mapping(uint256 => InvocationData) public invocations;
    /// Count of invocations made: used to calculate invocationId of the next invocation.
    uint256 public invocationCount;
    /// Mapping for responses (answers to invocations): matching invocationId to ResponseData struct.
    mapping(uint256 => ResponseData) public responses;
    /// Mapping for flagged (reported) responses. Used by the keeper not satisfied with a response.
    mapping(uint256 => bool) public responseFlagged;
    /// Flagged responses count is a convencience count of total flagged responses. Not used by the contract itself.
    uint256 public flaggedResponsesCount;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  CONSTRUCTOR AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev    When deployed, contract mints the only token that will ever exist, to itself.
    ///         This token represents the Orb and is called the Orb elsewhere in the contract.
    ///         `Ownable` sets the deployer to be the `owner()`, and also the creator in the Orb context.
    /// @param  name_          Orb name, used in ERC-721 metadata.
    /// @param  symbol_        Orb symbol or ticker, used in ERC-721 metadata.
    /// @param  tokenId_       ERC-721 token id of the Orb.
    /// @param  beneficiary_   Address to receive all Orb proceeds.
    /// @param  baseURI_       Initial baseURI value for tokenURI JSONs.
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 tokenId_,
        address beneficiary_,
        string memory baseURI_
    ) ERC721(name_, symbol_) {
        tokenId = tokenId_;
        beneficiary = beneficiary_;
        baseURI = baseURI_;

        emit Creation();

        _safeMint(address(this), tokenId);
    }

    /// @dev     ERC-165 supportsInterface. Orb contract supports ERC-721 and IOrb interfaces.
    /// @param   interfaceId           Interface id to check for support.
    /// @return  isInterfaceSupported  If interface with given 4 bytes id is supported.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC165, IERC165)
        returns (bool isInterfaceSupported)
    {
        return interfaceId == type(IOrb).interfaceId || super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  MODIFIERS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // AUTHORIZATION MODIFIERS

    /// @dev  Ensures that the caller owns the Orb. Should only be used in conjuction with `onlyKeeperHeld` or on
    ///       external functions, otherwise does not make sense.
    ///       Contract inherits `onlyOwner` modifier from `Ownable`.
    modifier onlyKeeper() {
        if (msg.sender != ERC721.ownerOf(tokenId)) {
            revert NotKeeper();
        }
        _;
    }

    // ORB STATE MODIFIERS

    /// @dev  Ensures that the Orb belongs to someone, not the contract itself.
    modifier onlyKeeperHeld() {
        if (address(this) == ERC721.ownerOf(tokenId)) {
            revert ContractHoldsOrb();
        }
        _;
    }

    /// @dev  Ensures that the Orb belongs to the contract itself or the creator, and the auction hasn't been started.
    ///       Most setting-adjusting functions should use this modifier. It means that the Orb properties cannot be
    ///       modified while it is held by the keeper or users can bid on the Orb.
    modifier onlyCreatorControlled() {
        if (address(this) != ERC721.ownerOf(tokenId) && owner() != ERC721.ownerOf(tokenId)) {
            revert CreatorDoesNotControlOrb();
        }
        if (auctionEndTime > 0) {
            revert AuctionRunning();
        }
        _;
    }

    // AUCTION MODIFIERS

    /// @dev  Ensures that an auction is currently not running. Can be multiple states: auction not started, auction
    ///       over but not finalized, or auction finalized.
    modifier notDuringAuction() {
        if (auctionRunning()) {
            revert AuctionRunning();
        }
        _;
    }

    // FUNDS-RELATED MODIFIERS

    /// @dev  Ensures that the current Orb keeper has enough funds to cover Harberger tax until now.
    modifier onlyKeeperSolvent() {
        if (!keeperSolvent()) {
            revert KeeperInsolvent();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ERC-721 OVERRIDES
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev     Override to provide ERC-721 contract's `tokenURI()` with the baseURI.
    /// @return  baseURIValue  Current baseURI value.
    function _baseURI() internal view override returns (string memory baseURIValue) {
        return baseURI;
    }

    /// @notice  Transfers the Orb to another address. Not allowed, always reverts.
    /// @dev     Always reverts.
    function transferFrom(address, address, uint256) public pure override {
        revert TransferringNotSupported();
    }

    /// @dev  See `transferFrom()`.
    function safeTransferFrom(address, address, uint256) public pure override {
        revert TransferringNotSupported();
    }

    /// @dev  See `transferFrom()`.
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert TransferringNotSupported();
    }

    /// @dev    Transfers the ERC-721 token to the new address. If the new owner is not this contract (an actual user),
    ///         updates `keeperReceiveTime`. `keeperReceiveTime` is used to limit response flagging duration.
    /// @param  from_  Address to transfer the Orb from.
    /// @param  to_    Address to transfer the Orb to.
    function _transferOrb(address from_, address to_) internal {
        _transfer(from_, to_, tokenId);
        if (to_ != address(this)) {
            keeperReceiveTime = block.timestamp;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ORB PARAMETERS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Allows re-swearing of the Orb Oath and set a new `honoredUntil` date. This function can only be called
    ///          by the Orb creator when the Orb is in their control. With `swearOath()`, `honoredUntil` date can be
    ///          decreased, unlike with the `extendHonoredUntil()` function.
    /// @dev     Emits `OathSwearing`.
    /// @param   oathHash           Hash of the Oath taken to create the Orb.
    /// @param   newHonoredUntil    Date until which the Orb creator will honor the Oath for the Orb keeper.
    /// @param   newResponsePeriod  Duration within which the Orb creator promises to respond to an invocation.
    function swearOath(bytes32 oathHash, uint256 newHonoredUntil, uint256 newResponsePeriod)
        external
        onlyOwner
        onlyCreatorControlled
    {
        honoredUntil = newHonoredUntil;
        responsePeriod = newResponsePeriod;
        emit OathSwearing(oathHash, newHonoredUntil, newResponsePeriod);
    }

    /// @notice  Allows the Orb creator to extend the `honoredUntil` date. This function can be called by the Orb
    ///          creator anytime and only allows extending the `honoredUntil` date.
    /// @dev     Emits `HonoredUntilUpdate`.
    /// @param   newHonoredUntil  Date until which the Orb creator will honor the Oath for the Orb keeper. Must be
    ///                           greater than the current `honoredUntil` date.
    function extendHonoredUntil(uint256 newHonoredUntil) external onlyOwner {
        if (newHonoredUntil < honoredUntil) {
            revert HonoredUntilNotDecreasable();
        }
        uint256 previousHonoredUntil = honoredUntil;
        honoredUntil = newHonoredUntil;
        emit HonoredUntilUpdate(previousHonoredUntil, newHonoredUntil);
    }

    /// @notice  Allows the Orb creator to replace the `baseURI`. This function can be called by the Orb creator
    ///          anytime and is meant for when the current `baseURI` has to be updated.
    /// @param   newBaseURI  New `baseURI`, will be concatenated with the token id in `tokenURI()`.
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    /// @notice  Allows the Orb creator to set the auction parameters. This function can only be called by the Orb
    ///          creator when the Orb is in their control.
    /// @dev     Emits `AuctionParametersUpdate`.
    /// @param   newStartingPrice          New starting price for the auction. Can be 0.
    /// @param   newMinimumBidStep         New minimum bid step for the auction. Will always be set to at least 1.
    /// @param   newMinimumDuration        New minimum duration for the auction. Must be > 0.
    /// @param   newKeeperMinimumDuration  New minimum duration for the auction is started by the keeper via
    ///                                    `relinquishWithAuction()`. Setting to 0 effectively disables keeper
    ///                                    auctions.
    /// @param   newBidExtension           New bid extension for the auction. Can be 0.
    function setAuctionParameters(
        uint256 newStartingPrice,
        uint256 newMinimumBidStep,
        uint256 newMinimumDuration,
        uint256 newKeeperMinimumDuration,
        uint256 newBidExtension
    ) external onlyOwner onlyCreatorControlled {
        if (newMinimumDuration == 0) {
            revert InvalidAuctionDuration(newMinimumDuration);
        }

        uint256 previousStartingPrice = auctionStartingPrice;
        auctionStartingPrice = newStartingPrice;

        uint256 previousMinimumBidStep = auctionMinimumBidStep;
        auctionMinimumBidStep = newMinimumBidStep > 0 ? newMinimumBidStep : 1;

        uint256 previousMinimumDuration = auctionMinimumDuration;
        auctionMinimumDuration = newMinimumDuration;

        uint256 previousKeeperMinimumDuration = auctionKeeperMinimumDuration;
        auctionKeeperMinimumDuration = newKeeperMinimumDuration;

        uint256 previousBidExtension = auctionBidExtension;
        auctionBidExtension = newBidExtension;

        emit AuctionParametersUpdate(
            previousStartingPrice,
            newStartingPrice,
            previousMinimumBidStep,
            auctionMinimumBidStep,
            previousMinimumDuration,
            newMinimumDuration,
            previousKeeperMinimumDuration,
            newKeeperMinimumDuration,
            previousBidExtension,
            newBidExtension
        );
    }

    /// @notice  Allows the Orb creator to set the new keeper tax and royalty. This function can only be called by the
    ///          Orb creator when the Orb is in their control.
    /// @dev     Emits `FeesUpdate`.
    /// @param   newKeeperTaxNumerator  New keeper tax numerator, in relation to `feeDenominator()`.
    /// @param   newRoyaltyNumerator    New royalty numerator, in relation to `feeDenominator()`. Cannot be larger than
    ///                                 `feeDenominator()`.
    function setFees(uint256 newKeeperTaxNumerator, uint256 newRoyaltyNumerator)
        external
        onlyOwner
        onlyCreatorControlled
    {
        if (newRoyaltyNumerator > FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(newRoyaltyNumerator, FEE_DENOMINATOR);
        }

        uint256 previousKeeperTaxNumerator = keeperTaxNumerator;
        keeperTaxNumerator = newKeeperTaxNumerator;

        uint256 previousRoyaltyNumerator = royaltyNumerator;
        royaltyNumerator = newRoyaltyNumerator;

        emit FeesUpdate(
            previousKeeperTaxNumerator, newKeeperTaxNumerator, previousRoyaltyNumerator, newRoyaltyNumerator
        );
    }

    /// @notice  Allows the Orb creator to set the new cooldown duration and flagging period - duration for how long
    ///          Orb keeper may flag a response. This function can only be called by the Orb creator when the Orb is in
    ///          their control.
    /// @dev     Emits `CooldownUpdate`.
    /// @param   newCooldown        New cooldown in seconds. Cannot be longer than `COOLDOWN_MAXIMUM_DURATION`.
    /// @param   newFlaggingPeriod  New flagging period in seconds.
    function setCooldown(uint256 newCooldown, uint256 newFlaggingPeriod) external onlyOwner onlyCreatorControlled {
        if (newCooldown > COOLDOWN_MAXIMUM_DURATION) {
            revert CooldownExceedsMaximumDuration(newCooldown, COOLDOWN_MAXIMUM_DURATION);
        }

        uint256 previousCooldown = cooldown;
        cooldown = newCooldown;
        uint256 previousFlaggingPeriod = flaggingPeriod;
        flaggingPeriod = newFlaggingPeriod;
        emit CooldownUpdate(previousCooldown, newCooldown, previousFlaggingPeriod, newFlaggingPeriod);
    }

    /// @notice  Allows the Orb creator to set the new cleartext maximum length. This function can only be called by
    ///          the Orb creator when the Orb is in their control.
    /// @dev     Emits `CleartextMaximumLengthUpdate`.
    /// @param   newCleartextMaximumLength  New cleartext maximum length. Cannot be 0.
    function setCleartextMaximumLength(uint256 newCleartextMaximumLength) external onlyOwner onlyCreatorControlled {
        if (newCleartextMaximumLength == 0) {
            revert InvalidCleartextMaximumLength(newCleartextMaximumLength);
        }

        uint256 previousCleartextMaximumLength = cleartextMaximumLength;
        cleartextMaximumLength = newCleartextMaximumLength;
        emit CleartextMaximumLengthUpdate(previousCleartextMaximumLength, newCleartextMaximumLength);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: AUCTION
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Returns if the auction is currently running. Use `auctionEndTime()` to check when it ends.
    /// @return  isAuctionRunning  If the auction is running.
    function auctionRunning() public view returns (bool isAuctionRunning) {
        return auctionEndTime > block.timestamp;
    }

    /// @notice  Minimum bid that would currently be accepted by `bid()`.
    /// @dev     `auctionStartingPrice` if no bids were made, otherwise the leading bid increased by
    ///          `auctionMinimumBidStep`.
    /// @return  auctionMinimumBid  Minimum bid required for `bid()`.
    function minimumBid() public view returns (uint256 auctionMinimumBid) {
        if (leadingBid == 0) {
            return auctionStartingPrice;
        } else {
            unchecked {
                return leadingBid + auctionMinimumBidStep;
            }
        }
    }

    /// @notice  Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.
    /// @dev     Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
    ///          after auction is finalized. Emits `AuctionStart`.
    function startAuction() external onlyOwner notDuringAuction {
        if (address(this) != ERC721.ownerOf(tokenId)) {
            revert ContractDoesNotHoldOrb();
        }

        if (auctionEndTime > 0) {
            revert AuctionRunning();
        }

        auctionEndTime = block.timestamp + auctionMinimumDuration;
        auctionBeneficiary = beneficiary;

        emit AuctionStart(block.timestamp, auctionEndTime);
    }

    /// @notice  Bids the provided amount, if there's enough funds across funds on contract and transaction value.
    ///          Might extend the auction if bidding close to auction end. Important: the leading bidder will not be
    ///          able to withdraw any funds until someone outbids them or the auction is finalized.
    /// @dev     Emits `AuctionBid`.
    /// @param   amount      The value to bid.
    /// @param   priceIfWon  Price if the bid wins. Must be less than `MAXIMUM_PRICE`.
    function bid(uint256 amount, uint256 priceIfWon) external payable {
        if (!auctionRunning()) {
            revert AuctionNotRunning();
        }

        if (msg.sender == beneficiary) {
            revert BeneficiaryDisallowed();
        }

        uint256 totalFunds = fundsOf[msg.sender] + msg.value;

        if (amount < minimumBid()) {
            revert InsufficientBid(amount, minimumBid());
        }

        if (totalFunds < amount) {
            revert InsufficientFunds(totalFunds, amount);
        }

        if (priceIfWon > MAXIMUM_PRICE) {
            revert InvalidNewPrice(priceIfWon);
        }

        fundsOf[msg.sender] = totalFunds;
        leadingBidder = msg.sender;
        leadingBid = amount;
        price = priceIfWon;

        emit AuctionBid(msg.sender, amount);

        if (block.timestamp + auctionBidExtension > auctionEndTime) {
            auctionEndTime = block.timestamp + auctionBidExtension;
            emit AuctionExtension(auctionEndTime);
        }
    }

    /// @notice  Finalizes the auction, transferring the winning bid to the beneficiary, and the Orb to the winner.
    ///          If the auction was started by previous Keeper with `relinquishWithAuction()`, then most of the auction
    ///          proceeds (minus the royalty) will be sent to the previous Keeper. Sets `lastInvocationTime` so that
    ///          the Orb could be invoked immediately. The price has been set when bidding, now becomes relevant. If no
    ///          bids were made, resets the state to allow the auction to be started again later.
    /// @dev     Critical state transition function. Called after `auctionEndTime`, but only if it's not 0. Can be
    ///          called by anyone, although probably will be called by the creator or the winner. Emits `PriceUpdate`
    ///          and `AuctionFinalization`.
    function finalizeAuction() external notDuringAuction {
        if (auctionEndTime == 0) {
            revert AuctionNotStarted();
        }

        if (leadingBidder != address(0)) {
            fundsOf[leadingBidder] -= leadingBid;
            uint256 auctionMinimumRoyaltyNumerator =
                (keeperTaxNumerator * auctionKeeperMinimumDuration) / KEEPER_TAX_PERIOD;
            uint256 auctionRoyalty =
                auctionMinimumRoyaltyNumerator > royaltyNumerator ? auctionMinimumRoyaltyNumerator : royaltyNumerator;
            _splitProceeds(leadingBid, auctionBeneficiary, auctionRoyalty);

            lastSettlementTime = block.timestamp;
            lastInvocationTime = block.timestamp - cooldown;

            emit AuctionFinalization(leadingBidder, leadingBid);
            emit PriceUpdate(0, price);
            // price has been set when bidding

            _transferOrb(address(this), leadingBidder);
            leadingBidder = address(0);
            leadingBid = 0;
        } else {
            emit AuctionFinalization(leadingBidder, leadingBid);
        }

        auctionEndTime = 0;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: FUNDS AND HOLDING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Allows depositing funds on the contract. Not allowed for insolvent keepers.
    /// @dev     Deposits are not allowed for insolvent keepers to prevent cheating via front-running. If the user
    ///          becomes insolvent, the Orb will always be returned to the contract as the next step. Emits `Deposit`.
    function deposit() external payable {
        if (msg.sender == ERC721.ownerOf(tokenId) && !keeperSolvent()) {
            revert KeeperInsolvent();
        }

        fundsOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice  Function to withdraw all funds on the contract. Not recommended for current Orb keepers if the price
    ///          is not zero, as they will become immediately foreclosable. To give up the Orb, call `relinquish()`.
    /// @dev     Not allowed for the leading auction bidder.
    function withdrawAll() external {
        _withdraw(msg.sender, fundsOf[msg.sender]);
    }

    /// @notice  Function to withdraw given amount from the contract. For current Orb keepers, reduces the time until
    ///          foreclosure.
    /// @dev     Not allowed for the leading auction bidder.
    /// @param   amount  The amount to withdraw.
    function withdraw(uint256 amount) external {
        _withdraw(msg.sender, amount);
    }

    /// @notice  Function to withdraw all beneficiary funds on the contract. Settles if possible.
    /// @dev     Allowed for anyone at any time, does not use `msg.sender` in its execution.
    function withdrawAllForBeneficiary() external {
        if (ERC721.ownerOf(tokenId) != address(this)) {
            _settle();
        }
        _withdraw(beneficiary, fundsOf[beneficiary]);
    }

    /// @notice  Settlements transfer funds from Orb keeper to the beneficiary. Orb accounting minimizes required
    ///          transactions: Orb keeper's foreclosure time is only dependent on the price and available funds. Fund
    ///          transfers are not necessary unless these variables (price, keeper funds) are being changed. Settlement
    ///          transfers funds owed since the last settlement, and a new period of virtual accounting begins.
    /// @dev     See also `_settle()`.
    function settle() external onlyKeeperHeld {
        _settle();
    }

    /// @dev     Returns if the current Orb keeper has enough funds to cover Harberger tax until now. Always true if
    ///          creator holds the Orb.
    /// @return  isKeeperSolvent  If the current keeper is solvent.
    function keeperSolvent() public view returns (bool isKeeperSolvent) {
        address keeper = ERC721.ownerOf(tokenId);
        if (owner() == keeper) {
            return true;
        }
        return fundsOf[keeper] >= _owedSinceLastSettlement();
    }

    /// @dev     Returns the accounting base for Orb fees (Harberger tax rate and royalty).
    /// @return  feeDenominatorValue  The accounting base for Orb fees.
    function feeDenominator() external pure returns (uint256 feeDenominatorValue) {
        return FEE_DENOMINATOR;
    }

    /// @dev     Returns the Harberger tax period base. Keeper tax is for each of this period.
    /// @return  keeperTaxPeriodSeconds  How long is the Harberger tax period, in seconds.
    function keeperTaxPeriod() external pure returns (uint256 keeperTaxPeriodSeconds) {
        return KEEPER_TAX_PERIOD;
    }

    /// @dev     Calculates how much money Orb keeper owes Orb beneficiary. This amount would be transferred between
    ///          accounts during settlement. **Owed amount can be higher than keeper's funds!** It's important to check
    ///          if keeper has enough funds before transferring.
    /// @return  owedValue  Wei Orb keeper owes Orb beneficiary since the last settlement time.
    function _owedSinceLastSettlement() internal view returns (uint256 owedValue) {
        uint256 secondsSinceLastSettlement = block.timestamp - lastSettlementTime;
        return (price * keeperTaxNumerator * secondsSinceLastSettlement) / (KEEPER_TAX_PERIOD * FEE_DENOMINATOR);
    }

    /// @dev    Executes the withdrawal for a given amount, does the actual value transfer from the contract to user's
    ///         wallet. The only function in the contract that sends value and has re-entrancy risk. Does not check if
    ///         the address is payable, as the Address library reverts if it is not. Emits `Withdrawal`.
    /// @param  recipient_  The address to send the value to.
    /// @param  amount_     The value in wei to withdraw from the contract.
    function _withdraw(address recipient_, uint256 amount_) internal {
        if (recipient_ == leadingBidder) {
            revert NotPermittedForLeadingBidder();
        }

        if (recipient_ == ERC721.ownerOf(tokenId)) {
            _settle();
        }

        if (fundsOf[recipient_] < amount_) {
            revert InsufficientFunds(fundsOf[recipient_], amount_);
        }

        fundsOf[recipient_] -= amount_;

        emit Withdrawal(recipient_, amount_);

        Address.sendValue(payable(recipient_), amount_);
    }

    /// @dev  Keeper might owe more than they have funds available: it means that the keeper is foreclosable.
    ///       Settlement would transfer all keeper funds to the beneficiary, but not more. Does not transfer funds if
    ///       the creator holds the Orb, but always updates `lastSettlementTime`. Should never be called if Orb is
    ///       owned by the contract. Emits `Settlement`.
    function _settle() internal {
        address keeper = ERC721.ownerOf(tokenId);

        if (owner() == keeper) {
            lastSettlementTime = block.timestamp;
            return;
        }

        uint256 availableFunds = fundsOf[keeper];
        uint256 owedFunds = _owedSinceLastSettlement();
        uint256 transferableToBeneficiary = availableFunds <= owedFunds ? availableFunds : owedFunds;

        fundsOf[keeper] -= transferableToBeneficiary;
        fundsOf[beneficiary] += transferableToBeneficiary;

        lastSettlementTime = block.timestamp;

        emit Settlement(keeper, beneficiary, transferableToBeneficiary);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: PURCHASING AND LISTING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Sets the new purchase price for the Orb. Harberger tax means the asset is always for sale. The price
    ///          can be set to zero, making foreclosure time to be never. Can only be called by a solvent keeper.
    ///          Settles before adjusting the price, as the new price will change foreclosure time.
    /// @dev     Emits `Settlement` and `PriceUpdate`. See also `_setPrice()`.
    /// @param   newPrice  New price for the Orb.
    function setPrice(uint256 newPrice) external onlyKeeper onlyKeeperSolvent {
        _settle();
        _setPrice(newPrice);
    }

    /// @notice  Lists the Orb for sale at the given price to buy directly from the Orb creator. This is an alternative
    ///          to the auction mechanism, and can be used to simply have the Orb for sale at a fixed price, waiting
    ///          for the buyer. Listing is only allowed if the auction has not been started and the Orb is held by the
    ///          contract. When the Orb is purchased from the creator, all proceeds go to the beneficiary and the Orb
    ///          comes fully charged, with no cooldown.
    /// @dev     Emits `Transfer` and `PriceUpdate`.
    /// @param   listingPrice  The price to buy the Orb from the creator.
    function listWithPrice(uint256 listingPrice) external onlyOwner {
        if (address(this) != ERC721.ownerOf(tokenId)) {
            revert ContractDoesNotHoldOrb();
        }

        if (auctionEndTime > 0) {
            revert AuctionRunning();
        }

        _transferOrb(address(this), msg.sender);
        _setPrice(listingPrice);
    }

    /// @notice  Purchasing is the mechanism to take over the Orb. With Harberger tax, the Orb can always be purchased
    ///          from its keeper. Purchasing is only allowed while the keeper is solvent. If not, the Orb has to be
    ///          foreclosed and re-auctioned. This function does not require the purchaser to have more funds than
    ///          required, but purchasing without any reserve would leave the new owner immediately foreclosable.
    ///          Beneficiary receives either just the royalty, or full price if the Orb is purchased from the creator.
    /// @dev     Requires to provide key Orb parameters (current price, Harberger tax rate, royalty, cooldown and
    ///          cleartext maximum length) to prevent front-running: without these parameters Orb creator could
    ///          front-run purcaser and change Orb parameters before the purchase; and without current price anyone
    ///          could purchase the Orb ahead of the purchaser, set the price higher, and profit from the purchase.
    ///          Does not modify `lastInvocationTime` unless buying from the creator.
    ///          Does not allow settlement in the same block before `purchase()` to prevent transfers that avoid
    ///          royalty payments. Does not allow purchasing from yourself. Emits `PriceUpdate` and `Purchase`.
    /// @param   newPrice                       New price to use after the purchase.
    /// @param   currentPrice                   Current price, to prevent front-running.
    /// @param   currentKeeperTaxNumerator      Current keeper tax numerator, to prevent front-running.
    /// @param   currentRoyaltyNumerator        Current royalty numerator, to prevent front-running.
    /// @param   currentCooldown                Current cooldown, to prevent front-running.
    /// @param   currentCleartextMaximumLength  Current cleartext maximum length, to prevent front-running.
    function purchase(
        uint256 newPrice,
        uint256 currentPrice,
        uint256 currentKeeperTaxNumerator,
        uint256 currentRoyaltyNumerator,
        uint256 currentCooldown,
        uint256 currentCleartextMaximumLength
    ) external payable onlyKeeperHeld onlyKeeperSolvent {
        if (currentPrice != price) {
            revert CurrentValueIncorrect(currentPrice, price);
        }
        if (currentKeeperTaxNumerator != keeperTaxNumerator) {
            revert CurrentValueIncorrect(currentKeeperTaxNumerator, keeperTaxNumerator);
        }
        if (currentRoyaltyNumerator != royaltyNumerator) {
            revert CurrentValueIncorrect(currentRoyaltyNumerator, royaltyNumerator);
        }
        if (currentCooldown != cooldown) {
            revert CurrentValueIncorrect(currentCooldown, cooldown);
        }
        if (currentCleartextMaximumLength != cleartextMaximumLength) {
            revert CurrentValueIncorrect(currentCleartextMaximumLength, cleartextMaximumLength);
        }

        if (lastSettlementTime >= block.timestamp) {
            revert PurchasingNotPermitted();
        }

        _settle();

        address keeper = ERC721.ownerOf(tokenId);

        if (msg.sender == keeper) {
            revert AlreadyKeeper();
        }
        if (msg.sender == beneficiary) {
            revert BeneficiaryDisallowed();
        }

        fundsOf[msg.sender] += msg.value;
        uint256 totalFunds = fundsOf[msg.sender];

        if (totalFunds < currentPrice) {
            revert InsufficientFunds(totalFunds, currentPrice);
        }

        fundsOf[msg.sender] -= currentPrice;
        if (owner() == keeper) {
            lastInvocationTime = block.timestamp - cooldown;
            fundsOf[beneficiary] += currentPrice;
        } else {
            _splitProceeds(currentPrice, keeper, royaltyNumerator);
        }

        _setPrice(newPrice);

        emit Purchase(keeper, msg.sender, currentPrice);

        _transferOrb(keeper, msg.sender);
    }

    /// @dev    Assigns proceeds to beneficiary and primary receiver, accounting for royalty. Used by `purchase()` and
    ///         `finalizeAuction()`. Fund deducation should happen before calling this function. Receiver might be
    ///         beneficiary if no split is needed.
    /// @param  proceeds_  Total proceeds to split between beneficiary and receiver.
    /// @param  receiver_  Address of the receiver of the proceeds minus royalty.
    /// @param  royalty_   Beneficiary royalty numerator to use for the split.
    function _splitProceeds(uint256 proceeds_, address receiver_, uint256 royalty_) internal {
        uint256 beneficiaryRoyalty = (proceeds_ * royalty_) / FEE_DENOMINATOR;
        uint256 receiverShare = proceeds_ - beneficiaryRoyalty;
        fundsOf[beneficiary] += beneficiaryRoyalty;
        fundsOf[receiver_] += receiverShare;
    }

    /// @dev    Does not check if the new price differs from the previous price: no risk. Limits the price to
    ///         MAXIMUM_PRICE to prevent potential overflows in math. Emits `PriceUpdate`.
    /// @param  newPrice_  New price for the Orb.
    function _setPrice(uint256 newPrice_) internal {
        if (newPrice_ > MAXIMUM_PRICE) {
            revert InvalidNewPrice(newPrice_);
        }

        uint256 previousPrice = price;
        price = newPrice_;

        emit PriceUpdate(previousPrice, newPrice_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: RELINQUISHMENT AND FORECLOSURE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Relinquishment is a voluntary giving up of the Orb. It's a combination of withdrawing all funds not
    ///          owed to the beneficiary since last settlement and transferring the Orb to the contract. Keepers giving
    ///          up the Orb may start an auction for it for their own benefit. Once auction is finalized, most of the
    ///          proceeds (minus the royalty) go to the relinquishing Keeper. Alternatives to relinquisment are setting
    ///          the price to zero or withdrawing all funds. Orb creator cannot start the keeper auction via this
    ///          function, and must call `relinquish(false)` and `startAuction()` separately to run the creator
    ///          auction.
    /// @dev     Calls `_withdraw()`, which does value transfer from the contract. Emits `Relinquishment`,
    ///          `Withdrawal`, and optionally `AuctionStart`.
    function relinquish(bool withAuction) external onlyKeeper onlyKeeperSolvent {
        _settle();

        price = 0;
        emit Relinquishment(msg.sender);

        if (withAuction && auctionKeeperMinimumDuration > 0) {
            if (owner() == msg.sender) {
                revert NotPermittedForCreator();
            }
            auctionBeneficiary = msg.sender;
            auctionEndTime = block.timestamp + auctionKeeperMinimumDuration;
            emit AuctionStart(block.timestamp, auctionEndTime);
        }

        _transferOrb(msg.sender, address(this));
        _withdraw(msg.sender, fundsOf[msg.sender]);
    }

    /// @notice  Foreclose can be called by anyone after the Orb keeper runs out of funds to cover the Harberger tax.
    ///          It returns the Orb to the contract and starts a auction to find the next keeper. Most of the proceeds
    ///          (minus the royalty) go to the previous keeper.
    /// @dev     Emits `Foreclosure`, and optionally `AuctionStart`.
    function foreclose() external onlyKeeperHeld {
        if (keeperSolvent()) {
            revert KeeperSolvent();
        }

        _settle();

        address keeper = ERC721.ownerOf(tokenId);
        price = 0;

        emit Foreclosure(keeper);

        if (auctionKeeperMinimumDuration > 0) {
            auctionBeneficiary = keeper;
            auctionEndTime = block.timestamp + auctionKeeperMinimumDuration;
            emit AuctionStart(block.timestamp, auctionEndTime);
        }

        _transferOrb(keeper, address(this));
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOKING AND RESPONDING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Invokes the Orb. Allows the keeper to submit cleartext.
    /// @dev     Cleartext is hashed and passed to `invokeWithHash()`. Emits `CleartextRecording`.
    /// @param   cleartext  Invocation cleartext.
    function invokeWithCleartext(string memory cleartext) external {
        uint256 length = bytes(cleartext).length;
        if (length > cleartextMaximumLength) {
            revert CleartextTooLong(length, cleartextMaximumLength);
        }
        invokeWithHash(keccak256(abi.encodePacked(cleartext)));
        emit CleartextRecording(invocationCount, cleartext);
    }

    /// @notice  Invokes the Orb. Allows the keeper to submit content hash, that represents a question to the Orb
    ///          creator. Puts the Orb on cooldown. The Orb can only be invoked by solvent keepers.
    /// @dev     Content hash is keccak256 of the cleartext. `invocationCount` is used to track the id of the next
    ///          invocation. Invocation ids start from 1. Emits `Invocation`.
    /// @param   contentHash  Required keccak256 hash of the cleartext.
    function invokeWithHash(bytes32 contentHash) public onlyKeeper onlyKeeperHeld onlyKeeperSolvent {
        if (block.timestamp < lastInvocationTime + cooldown) {
            revert CooldownIncomplete(lastInvocationTime + cooldown - block.timestamp);
        }

        invocationCount += 1;
        uint256 invocationId = invocationCount; // starts at 1

        invocations[invocationId] = InvocationData(msg.sender, contentHash, block.timestamp);
        lastInvocationTime = block.timestamp;

        emit Invocation(invocationId, msg.sender, block.timestamp, contentHash);
    }

    /// @notice  The Orb creator can use this function to respond to any existing invocation, no matter how long ago
    ///          it was made. A response to an invocation can only be written once. There is no way to record response
    ///          cleartext on-chain.
    /// @dev     Emits `Response`.
    /// @param   invocationId  Id of an invocation to which the response is being made.
    /// @param   contentHash   keccak256 hash of the response text.
    function respond(uint256 invocationId, bytes32 contentHash) external onlyOwner {
        if (invocationId > invocationCount || invocationId == 0) {
            revert InvocationNotFound(invocationId);
        }

        if (_responseExists(invocationId)) {
            revert ResponseExists(invocationId);
        }

        responses[invocationId] = ResponseData(contentHash, block.timestamp);

        emit Response(invocationId, msg.sender, block.timestamp, contentHash);
    }

    /// @notice  Orb keeper can flag a response during Response Flagging Period, counting from when the response is
    ///          made. Flag indicates a "report", that the Orb keeper was not satisfied with the response provided.
    ///          This is meant to act as a social signal to future Orb keepers. It also increments
    ///          `flaggedResponsesCount`, allowing anyone to quickly look up how many responses were flagged.
    /// @dev     Only existing responses (with non-zero timestamps) can be flagged. Responses can only be flagged by
    ///          solvent keepers to keep it consistent with `invokeWithHash()` or `invokeWithCleartext()`. Also, the
    ///          keeper must have received the Orb after the response was made; this is to prevent keepers from
    ///          flagging responses that were made in response to others' invocations. Emits `ResponseFlagging`.
    /// @param   invocationId  Id of an invocation to which the response is being flagged.
    function flagResponse(uint256 invocationId) external onlyKeeper onlyKeeperSolvent {
        if (!_responseExists(invocationId)) {
            revert ResponseNotFound(invocationId);
        }

        // Response Flagging Period starts counting from when the response is made.
        uint256 responseTime = responses[invocationId].timestamp;
        if (block.timestamp - responseTime > flaggingPeriod) {
            revert FlaggingPeriodExpired(invocationId, block.timestamp - responseTime, flaggingPeriod);
        }
        if (keeperReceiveTime >= responseTime) {
            revert FlaggingPeriodExpired(invocationId, keeperReceiveTime, responseTime);
        }
        if (responseFlagged[invocationId]) {
            revert ResponseAlreadyFlagged(invocationId);
        }

        responseFlagged[invocationId] = true;
        flaggedResponsesCount += 1;

        emit ResponseFlagging(invocationId, msg.sender);
    }

    /// @dev     Returns if a response to an invocation exists, based on the timestamp of the response being non-zero.
    /// @param   invocationId_  Id of an invocation to which to check the existance of a response of.
    /// @return  isResponseFound  If a response to an invocation exists or not.
    function _responseExists(uint256 invocationId_) internal view returns (bool isResponseFound) {
        if (responses[invocationId_].timestamp != 0) {
            return true;
        }
        return false;
    }
}
