// SPDX-License-Identifier: MIT
/*..............................................................................


                          ./         (@@@@@@@@@@@@@@@@@,
                     &@@@@       /@@@@&.        *&@@@@@@@@@@*
                 %@@@@@@.      (@@@                  &@@@@@@@@@&
              .@@@@@@@@       @@@                      ,@@@@@@@@@@/
            *@@@@@@@@@       (@%                         &@@@@@@@@@@/
           @@@@@@@@@@/       @@                           (@@@@@@@@@@@
          @@@@@@@@@@@        &@                            %@@@@@@@@@@@
         @@@@@@@@@@@#         @                             @@@@@@@@@@@@
        #@@@@@@@@@@@.                                       /@@@@@@@@@@@@
        @@@@@@@@@@@@                                         @@@@@@@@@@@@
        @@@@@@@@@@@@                                         @@@@@@@@@@@@
        @@@@@@@@@@@@.                                        @@@@@@@@@@@@
        @@@@@@@@@@@@%                                       ,@@@@@@@@@@@@
        ,@@@@@@@@@@@@                                       @@@@@@@@@@@@/
         %@@@@@@@@@@@&                                     .@@@@@@@@@@@@
          #@@@@@@@@@@@#                                    @@@@@@@@@@@&
           .@@@@@@@@@@@&                                 ,@@@@@@@@@@@,
             *@@@@@@@@@@@,                              @@@@@@@@@@@#
                @@@@@@@@@@@*                          @@@@@@@@@@@.
                  .&@@@@@@@@@@*                   .@@@@@@@@@@@.
                       &@@@@@@@@@@@%*..   ..,#@@@@@@@@@@@@@*
                     ,@@@@   ,#&@@@@@@@@@@@@@@@@@@#*     &@@@#
                    @@@@@                                 #@@@@.
                   @@@@@*                                  @@@@@,
                  @@@@@@@(                               .@@@@@@@
                  (@@@@@@@@@@@@@@%/*,.       ..,/#@@@@@@@@@@@@@@@
                     #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%
                             ./%@@@@@@@@@@@@@@@@@@@%/,


..............................................................................*/
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
/// @dev     Supports ERC-721 interface but reverts on all transfers.
///          Uses `Ownable`'s `owner()` to identify the creator of the Orb.
///          Uses `ERC721`'s `ownerOf(tokenId)` to identify the current holder of the Orb.
/// @notice  This is a basic Q&A-type Orb. The holder has the right to submit a text-based question to the
///          creator and the right to receive a text-based response. The question is limited in length but
///          responses may come in any length. Questions and answers are hash-committed to the Ethereum blockchain
///          so that the track record cannot be changed. The Orb has a cooldown.
///          The Orb uses Harberger tax and is always on sale. This means that when you purchase the Orb, you must
///          also set a price which you’re willing to sell the Orb at. However, you must pay an amount base on tax rate
///          to the Orb smart contract per year in order to maintain the Orb ownership. This amount is accounted for
///          per second, and user funds need to be topped up before the foreclosure time to maintain ownership.
contract Orb is Ownable, ERC165, ERC721, IOrb {
    ////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS AND IMMUTABLES

    /// Beneficiary is another address that receives all Orb proceeds. It is set in the `constructor` as an immutable
    /// value. Beneficiary is not allowed to bid in the auction or purchase the Orb. The intended use case for the
    /// beneficiary is to set it to a revenue splitting contract. Proceeds that go to the beneficiary are:
    /// - The auction winning bid amount;
    /// - Royalties from Orb purchase when not purchased from the Orb creator;
    /// - Full purchase price when purchased from the Orb creator;
    /// - Harberger tax revenue.
    address public immutable beneficiary;

    // Internal Immutables and Constants

    /// Orb ERC-721 token number. Can be whatever arbitrary number, only one token will ever exist. Made public to
    /// allow easier lookups of Orb holder.
    uint256 public immutable tokenId;

    /// Fee Nominator: basis points. Other fees are in relation to this.
    uint256 internal constant FEE_DENOMINATOR = 10_000;
    /// Harberger tax period: for how long the tax rate applies. Value: 1 year.
    uint256 internal constant HOLDER_TAX_PERIOD = 365 days;
    /// Maximum cooldown duration, to prevent potential underflows. Value: 10 years.
    uint256 internal constant COOLDOWN_MAXIMUM_DURATION = 3650 days;
    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant MAX_PRICE = 2 ** 128;

    // STATE

    /// Honored Until: timestamp until which the Orb Oath is honored for the holder.
    uint256 public honoredUntil;

    /// Base URI for tokenURI JSONs. Initially set in the `constructor` and setable with `setBaseURI()`.
    string internal baseURI;

    /// Funds tracker, per address. Modified by deposits, withdrawals and settlements. The value is without settlement.
    /// It means effective user funds (withdrawable) would be different for holder (subtracting
    /// `_owedSinceLastSettlement()`) and beneficiary (adding `_owedSinceLastSettlement()`). If Orb is held by the
    /// creator, funds are not subtracted, as Harberger tax does not apply to the creator.
    mapping(address => uint256) public fundsOf;

    // Fees State Variables

    /// Harberger tax for holding. Initial value is 10%.
    uint256 public holderTaxNumerator = 1_000;
    /// Secondary sale royalty paid to beneficiary, based on sale price.
    uint256 public royaltyNumerator = 1_000;
    /// Price of the Orb. No need for mapping, as only one token is ever minted. Also used during auction to store
    /// future purchase price. Has no meaning if the Orb is held by the contract and the auction is not running.
    uint256 public price;
    /// Last time Orb holder's funds were settled. Used to calculate amount owed since last settlement. Has no meaning
    /// if the Orb is held by the contract.
    uint256 public lastSettlementTime;

    // Auction State Variables

    /// Auction starting price. Initial value is 0 - allows any bid.
    uint256 public auctionStartingPrice = 0;
    /// Auction minimum bid step: required increase between bids. Each bid has to increase over previous bid by at
    /// least this much. If trying to set as zero, will be set to 1 (wei). Initial value is also 1 wei, to disallow
    /// equal value bids.
    uint256 public auctionMinimumBidStep = 1;
    /// Auction minimum duration: the auction will run for at least this long. Initial value is 1 day, and this value
    /// cannot be set to zero.
    uint256 public auctionMinimumDuration = 1 days;
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

    // Invocation and Response State Variables

    /// Struct used to track invocation and response information: keccak256 content hash and block timestamp.
    /// When used for responses, timestamp is used to determine if the response can be flagged by the holder.
    /// Invocation timestamp is tracked for the benefit of other contracts.
    struct HashTime {
        // keccak256 hash of the cleartext
        bytes32 contentHash;
        uint256 timestamp;
    }

    /// Cooldown: how often the Orb can be invoked.
    uint256 public cooldown = 7 days;
    /// Maximum length for invocation cleartext content.
    uint256 public cleartextMaximumLength = 280;
    /// Holder receive time: when the Orb was last transferred, except to this contract.
    uint256 public holderReceiveTime;
    /// Last invocation time: when the Orb was last invoked. Used together with `cooldown` constant.
    uint256 public lastInvocationTime;

    /// Mapping for invocations: invocationId to HashTime struct.
    mapping(uint256 => HashTime) public invocations;
    /// Count of invocations made: used to calculate invocationId of the next invocation.
    uint256 public invocationCount = 0;
    /// Mapping for responses (answers to invocations): matching invocationId to HashTime struct.
    mapping(uint256 => HashTime) public responses;
    /// Mapping for flagged (reported) responses. Used by the holder not satisfied with a response.
    mapping(uint256 => bool) public responseFlagged;
    /// Flagged responses count is a convencience count of total flagged responses. Not used by the contract itself.
    uint256 public flaggedResponsesCount = 0;

    ////////////////////////////////////////////////////////////////////////////////
    //  CONSTRUCTOR
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev  When deployed, contract mints the only token that will ever exist, to itself.
     *       This token represents the Orb and is called the Orb elsewhere in the contract.
     *       {Ownable} sets the deployer to be the owner, and also the creator in the Orb context.
     * @param name_          Orb name, used in ERC-721 metadata.
     * @param symbol_        Orb symbol or ticker, used in ERC-721 metadata.
     * @param tokenId_       ERC-721 token ID of the Orb.
     * @param beneficiary_   Beneficiary receives all Orb proceeds.
     * @param oathHash_      Hash of the Oath taken to create the Orb.
     * @param honoredUntil_  Date until which the Orb creator will honor the Oath for the Orb holder.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 tokenId_,
        address beneficiary_,
        bytes32 oathHash_,
        uint256 honoredUntil_,
        string memory baseURI_
    ) ERC721(name_, symbol_) {
        tokenId = tokenId_;
        beneficiary = beneficiary_;
        honoredUntil = honoredUntil_;
        baseURI = baseURI_;

        emit Creation(oathHash_, honoredUntil_);

        _safeMint(address(this), tokenId);
    }

    /**
     * @dev  ERC-165 supportsInterface. Orb contract supports ERC-721 and IOrb interfaces.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC165, IERC165) returns (bool) {
        return interfaceId == type(IOrb).interfaceId || super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  MODIFIERS
    ////////////////////////////////////////////////////////////////////////////////

    // AUTHORIZATION MODIFIERS

    /**
     * @notice  Contract inherits {onlyOwner} modifier from {Ownable}.
     */

    /**
     * @dev  Ensures that the caller owns the Orb.
     *       Should only be used in conjuction with {onlyHolderHeld} or on external functions,
     *       otherwise does not make sense.
     */
    modifier onlyHolder() {
        if (msg.sender != ERC721.ownerOf(tokenId)) {
            revert NotHolder();
        }
        _;
    }

    // ORB STATE MODIFIERS

    /**
     * @dev  Ensures that the Orb belongs to someone, not the contract itself.
     */
    modifier onlyHolderHeld() {
        if (address(this) == ERC721.ownerOf(tokenId)) {
            revert ContractHoldsOrb();
        }
        _;
    }

    /**
     * @dev  Ensures that the Orb belongs to the contract itself or the creator.
     *       All setting-adjusting functions should use this modifier.
     *       It means that the Orb properties cannot be modified while it is held by the holder.
     */
    modifier onlyCreatorControlled() {
        if (address(this) != ERC721.ownerOf(tokenId) && owner() != ERC721.ownerOf(tokenId)) {
            revert CreatorDoesNotControlOrb();
        }
        _;
    }

    // AUCTION MODIFIERS

    /**
     * @dev  Ensures that an auction is currently not running.
     *       Can be multiple states: auction not started, auction over but not finalized, or auction finalized.
     */
    modifier notDuringAuction() {
        if (auctionRunning()) {
            revert AuctionRunning();
        }
        _;
    }

    // FUNDS-RELATED MODIFIERS

    /**
     * @dev  Ensures that the current Orb holder has enough funds to cover Harberger tax until now.
     */
    modifier onlyHolderSolvent() {
        if (!holderSolvent()) {
            revert HolderInsolvent();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ERC-721 OVERRIDES
    ////////////////////////////////////////////////////////////////////////////////

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @notice  Transfers the Orb to another address. Not allowed, always reverts.
     * @dev     Always reverts.
     */
    function transferFrom(address, address, uint256) public pure override {
        revert TransferringNotSupported();
    }

    /**
     * @dev  See {transferFrom()} above.
     */
    function safeTransferFrom(address, address, uint256) public pure override {
        revert TransferringNotSupported();
    }

    /**
     * @dev  See {transferFrom()} above.
     */
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert TransferringNotSupported();
    }

    /**
     * @notice  Transfers the ERC-20 token to the new address.
     *          If the new owner is not this contract (an actual user), updates holderReceiveTime.
     *          holderReceiveTime is used to limit response flagging window.
     */
    function _transferOrb(address from_, address to_) internal {
        _transfer(from_, to_, tokenId);
        if (to_ != address(this)) {
            holderReceiveTime = block.timestamp;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ORB PARAMETERS
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Allows re-swearing of the oath and set a new honoredUntil date.
     *          This function can only be called by the Orb creator when the Orb is not held by anyone.
     *          HonoredUntil date can be decreased, unlike with the {extendHonoredUntil()} function.
     * @dev     Emits {OathSwearing} event.
     */
    function swearOath(bytes32 oathHash, uint256 newHonoredUntil) external onlyOwner onlyCreatorControlled {
        honoredUntil = newHonoredUntil;
        emit OathSwearing(oathHash, newHonoredUntil);
    }

    /**
     * @notice  Allows the Orb creator to extend the honoredUntil date.
     *          This function can be called by the Orb creator anytime and only allows extending
     *          the honoredUntil date.
     * @dev     Emits {HonoredUntilUpdate} event.
     */
    function extendHonoredUntil(uint256 newHonoredUntil) external onlyOwner {
        if (newHonoredUntil < honoredUntil) {
            revert HonoredUntilNotDecreasable();
        }
        uint256 previousHonoredUntil = honoredUntil;
        honoredUntil = newHonoredUntil;
        emit HonoredUntilUpdate(previousHonoredUntil, newHonoredUntil);
    }

    /**
     * @notice  Allows the Orb creator to replace the baseURI.
     *          This function can be called by the Orb creator anytime and is meant for
     *          when the current baseURI has to be updated.
     * @param   newBaseURI  New baseURI, will be concatenated with the token ID.
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    /**
     * @notice  Allows the Orb creator to set the auction parameters.
     *          This function can only be called by the Orb creator when the Orb is not held by anyone.
     * @dev     Emits {AuctionParametersUpdate} event.
     * @param   newStartingPrice    New starting price for the auction. Can be 0.
     * @param   newMinimumBidStep   New minimum bid step for the auction. Will always be set to at least 1.
     * @param   newMinimumDuration  New minimum duration for the auction. Must be > 0.
     * @param   newBidExtension     New bid extension for the auction. Can be 0.
     */
    function setAuctionParameters(
        uint256 newStartingPrice,
        uint256 newMinimumBidStep,
        uint256 newMinimumDuration,
        uint256 newBidExtension
    ) external onlyOwner onlyCreatorControlled {
        if (newMinimumDuration == 0) {
            revert InvalidAuctionDuration(newMinimumDuration);
        }

        uint256 previousStartingPrice = auctionStartingPrice;
        auctionStartingPrice = newStartingPrice;

        uint256 previousMinimumBidStep = auctionMinimumBidStep;
        uint256 boundedMinimumBidStep = newMinimumBidStep > 0 ? newMinimumBidStep : 1;
        auctionMinimumBidStep = boundedMinimumBidStep;

        uint256 previousMinimumDuration = auctionMinimumDuration;
        auctionMinimumDuration = newMinimumDuration;

        uint256 previousBidExtension = auctionBidExtension;
        auctionBidExtension = newBidExtension;

        emit AuctionParametersUpdate(
            previousStartingPrice,
            newStartingPrice,
            previousMinimumBidStep,
            boundedMinimumBidStep,
            previousMinimumDuration,
            newMinimumDuration,
            previousBidExtension,
            newBidExtension
        );
    }

    /**
     * @notice  Allows the Orb creator to set the new holder tax and royalty.
     *          This function can only be called by the Orb creator when the Orb is not held by anyone.
     * @dev     Emits FeesUpdate() event.
     * @param   newHolderTaxNumerator  New holder tax numerator, in relation to FEE_DENOMINATOR.
     * @param   newRoyaltyNumerator    New royalty numerator, in relation to FEE_DENOMINATOR.
     */
    function setFees(uint256 newHolderTaxNumerator, uint256 newRoyaltyNumerator)
        external
        onlyOwner
        onlyCreatorControlled
    {
        if (newRoyaltyNumerator > FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(newRoyaltyNumerator, FEE_DENOMINATOR);
        }

        uint256 previousHolderTaxNumerator = holderTaxNumerator;
        holderTaxNumerator = newHolderTaxNumerator;

        uint256 previousRoyaltyNumerator = royaltyNumerator;
        royaltyNumerator = newRoyaltyNumerator;

        emit FeesUpdate(
            previousHolderTaxNumerator, newHolderTaxNumerator, previousRoyaltyNumerator, newRoyaltyNumerator
        );
    }

    /**
     * @notice  Allows the Orb creator to set the new cooldown duration.
     *          This function can only be called by the Orb creator when the Orb is not held by anyone.
     * @dev     Emits CooldownUpdate() event.
     * @param   newCooldown  New cooldown in seconds.
     */
    function setCooldown(uint256 newCooldown) external onlyOwner onlyCreatorControlled {
        if (newCooldown > COOLDOWN_MAXIMUM_DURATION) {
            revert CooldownExceedsMaximumDuration(newCooldown, COOLDOWN_MAXIMUM_DURATION);
        }

        uint256 previousCooldown = cooldown;
        cooldown = newCooldown;
        emit CooldownUpdate(previousCooldown, newCooldown);
    }

    /**
     * @notice  Allows the Orb creator to set the new cleartext maximum length.
     *          This function can only be called by the Orb creator when the Orb is not held by anyone.
     * @dev     Emits CleartextMaximumLengthUpdate() event.
     * @param   newCleartextMaximumLength  New cleartext maximum length.
     */
    function setCleartextMaximumLength(uint256 newCleartextMaximumLength) external onlyOwner onlyCreatorControlled {
        if (newCleartextMaximumLength == 0) {
            revert InvalidCleartextMaximumLength(newCleartextMaximumLength);
        }

        uint256 previousCleartextMaximumLength = cleartextMaximumLength;
        cleartextMaximumLength = newCleartextMaximumLength;
        emit CleartextMaximumLengthUpdate(previousCleartextMaximumLength, newCleartextMaximumLength);
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: AUCTION
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Returns if the auction is currently running. Use auctionEndTime() to check when it ends.
     * @dev     Start time will always be less than timestamp, as it resets to 0.
     *          Start time is only updated for auction progress tracking, not critical functionality.
     * @return  bool  If the auction is running.
     */
    function auctionRunning() public view returns (bool) {
        return auctionEndTime > block.timestamp;
    }

    /**
     * @notice  Minimum bid that would currently be accepted by {bid()}.
     * @dev     auctionStartingPrice if no bids were made, otherwise previous bid increased by auctionMinimumBidStep.
     * @return  uint256  Minimum bid required for {bid()}.
     */
    function minimumBid() public view returns (uint256) {
        if (leadingBid == 0) {
            return auctionStartingPrice;
        } else {
            unchecked {
                return leadingBid + auctionMinimumBidStep;
            }
        }
    }

    /**
     * @notice  Allow the Orb creator to start the Orb Auction. Will run for at least auctionMinimumDuration.
     * @dev     Prevents repeated starts by checking the auctionEndTime.
     *          Important to set auctionEndTime to 0 after auction is finalized.
     *          Also, resets leadingBidder and leadingBid.
     *          Should not be necessary, as {finalizeAuction()} also does that.
     *          Emits AuctionStart().
     */
    function startAuction() external onlyOwner notDuringAuction {
        if (address(this) != ERC721.ownerOf(tokenId)) {
            revert ContractDoesNotHoldOrb();
        }

        if (auctionEndTime > 0) {
            revert AuctionRunning();
        }

        auctionEndTime = block.timestamp + auctionMinimumDuration;

        emit AuctionStart(block.timestamp, auctionEndTime);
    }

    /**
     * @notice  Bids the provided amount, if there's enough funds across funds on contract and transaction value.
     *          Might extend the auction if the bid is near the end.
     *          Important: the leading bidder will not be able to withdraw funds until someone outbids them.
     * @dev     Emits AuctionBid().
     * @param   amount      The value to bid.
     * @param   priceIfWon  Price if the bid wins. Must be less than MAX_PRICE.
     */
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

        if (priceIfWon > MAX_PRICE) {
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

    /**
     * @notice  Finalizes the Auction, transferring the winning bid to the beneficiary, and the Orb to the winner.
     *          Sets lastInvocationTime so that the Orb could be invoked immediately.
     *          The price has been set when bidding, now becomes relevant.
     *          If no bids were made, resets the state to allow the auction to be started again later.
     * @dev     Critical state transition function. Called after auctionEndTime, but only if it's not 0.
     *          Can be called by anyone, although probably will be called by the creator or the winner.
     *          Emits PriceUpdate() and AuctionFinalization().
     */
    function finalizeAuction() external notDuringAuction {
        if (auctionEndTime == 0) {
            revert AuctionNotStarted();
        }

        if (leadingBidder != address(0)) {
            fundsOf[leadingBidder] -= leadingBid;
            fundsOf[beneficiary] += leadingBid;

            lastSettlementTime = block.timestamp;
            lastInvocationTime = block.timestamp - cooldown;

            emit AuctionFinalization(leadingBidder, leadingBid);
            emit PriceUpdate(0, price);
            // price has been set when bidding

            _transferOrb(address(this), leadingBidder);
            leadingBidder = address(0);
            leadingBid = 0;
        } else {
            price = 0;
            emit AuctionFinalization(leadingBidder, leadingBid);
        }

        auctionEndTime = 0;
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: FUNDS AND HOLDING
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Allows depositing funds on the contract. Not allowed for insolvent holders.
     * @dev     Deposits are not allowed for insolvent holders to prevent cheating via front-running.
     *          If the user becomes insolvent, the Orb will always be returned to the contract as the next step.
     *          Emits Deposit().
     */
    function deposit() external payable {
        if (msg.sender == ERC721.ownerOf(tokenId) && !holderSolvent()) {
            revert HolderInsolvent();
        }

        fundsOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice  Function to withdraw all funds on the contract.
     *          Not recommended for current Orb holders, they should call relinquish() to take out their funds.
     * @dev     Not allowed for the leading auction bidder.
     */
    function withdrawAll() external {
        _withdraw(msg.sender, fundsOf[msg.sender]);
    }

    /**
     * @notice  Function to withdraw given amount from the contract.
     *          For current Orb holders, reduces the time until foreclosure.
     * @dev     Not allowed for the leading auction bidder.
     */
    function withdraw(uint256 amount) external {
        _withdraw(msg.sender, amount);
    }

    /**
     * @notice  Function to withdraw all beneficiary funds on the contract.
     * @dev     Allowed for anyone at any time, does not use msg.sender in its execution.
     */
    function withdrawAllForBeneficiary() external {
        _withdraw(beneficiary, fundsOf[beneficiary]);
    }

    /**
     * @notice  Settlements transfer funds from Orb holder to the beneficiary.
     *          Orb accounting minimizes required transactions: Orb holder's foreclosure time is only
     *          dependent on the price and available funds. Fund transfers are not necessary unless
     *          these variables (price, holder funds) are being changed. Settlement transfers funds owed
     *          since the last settlement, and a new period of virtual accounting begins.
     * @dev     Holder might owe more than they have funds available: it means that the holder is foreclosable.
     *          Settlement would transfer all holder funds to the beneficiary, but not more.
     *          Does nothing if the creator holds the Orb. Reverts if contract holds the Orb.
     *          Emits Settlement().
     */
    function settle() external onlyHolderHeld {
        _settle();
    }

    /**
     * @dev     Returns if the current Orb holder has enough funds to cover Harberger tax until now.
     *          Always true is creator holds the Orb.
     * @return  bool  If the current holder is solvent.
     */
    function holderSolvent() public view returns (bool) {
        address holder = ERC721.ownerOf(tokenId);
        if (owner() == holder) {
            return true;
        }
        return fundsOf[holder] >= _owedSinceLastSettlement();
    }

    /**
     * @dev     Returns the accounting base for Orb fees (Harberger tax rate and royalty).
     * @return  uint256  The accounting base for Orb fees.
     */
    function feeDenominator() external pure returns (uint256) {
        return FEE_DENOMINATOR;
    }

    /**
     * @dev     Returns the Harberger tax period base. Holder tax is for each of this period.
     * @return  uint256  How long is the Harberger tax period, in seconds.
     */
    function holderTaxPeriod() external pure returns (uint256) {
        return HOLDER_TAX_PERIOD;
    }

    /**
     * @dev     Calculates how much money Orb holder owes Orb beneficiary. This amount would be transferred between
     *          accounts during settlement.
     *          Owed amount can be higher than hodler's funds! It's important to check if holder has enough funds
     *          before transferring.
     * @return  bool  Wei Orb holder owes Orb beneficiary since the last settlement time.
     */
    function _owedSinceLastSettlement() internal view returns (uint256) {
        uint256 secondsSinceLastSettlement = block.timestamp - lastSettlementTime;
        return (price * holderTaxNumerator * secondsSinceLastSettlement) / (HOLDER_TAX_PERIOD * FEE_DENOMINATOR);
    }

    /**
     * @dev     Executes the withdrawal for a given amount, does the actual value transfer from the contract
     *          to user's wallet. The only function in the contract that sends value and has re-entrancy risk.
     *          Does not check if the address is payable, as the Address library reverts if it is not.
     *          Emits Withdrawal().
     * @param   recipient_  The address to send the value to.
     * @param   amount_     The value in wei to withdraw from the contract.
     */
    function _withdraw(address recipient_, uint256 amount_) internal {
        if (msg.sender == leadingBidder) {
            revert NotPermittedForLeadingBidder();
        }

        if (msg.sender == ERC721.ownerOf(tokenId)) {
            _settle();
        }

        if (fundsOf[recipient_] < amount_) {
            revert InsufficientFunds(fundsOf[recipient_], amount_);
        }

        fundsOf[recipient_] -= amount_;

        emit Withdrawal(recipient_, amount_);

        Address.sendValue(payable(recipient_), amount_);
    }

    /**
     * @dev  See {settle()}.
     */
    function _settle() internal {
        address holder = ERC721.ownerOf(tokenId);

        if (owner() == holder) {
            return;
        }

        // Should never be reached if this contract holds the Orb.
        assert(address(this) != holder);

        uint256 availableFunds = fundsOf[holder];
        uint256 owedFunds = _owedSinceLastSettlement();
        uint256 transferableToBeneficiary = availableFunds <= owedFunds ? availableFunds : owedFunds;

        fundsOf[holder] -= transferableToBeneficiary;
        fundsOf[beneficiary] += transferableToBeneficiary;

        lastSettlementTime = block.timestamp;

        emit Settlement(holder, beneficiary, transferableToBeneficiary);
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: PURCHASING AND LISTING
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Sets the new purchase price for the Orb. Harberger tax means the asset is always for sale.
     *          The price can be set to zero, making foreclosure time to be never.
     * @dev     Can only be called by a solvent holder.
     *          Settles before adjusting the price, as the new price will change foreclosure time.
     *          Does not check if the new price differs from the previous price: no risk.
     *          Limits the price to MAX_PRICE to prevent potential overflows in math.
     *          Emits PriceUpdate().
     * @param   newPrice  New price for the Orb.
     */
    function setPrice(uint256 newPrice) external onlyHolder onlyHolderSolvent {
        _settle();
        _setPrice(newPrice);
    }

    /**
     * @notice  Lists the Orb for sale at the given price to buy directly from the Orb creator.
     *          This is an alternative to the auction mechanism, and can be used to simply have the Orb for sale
     *          at a fixed price, waiting for the buyer.
     *          Listing is only allowed if the auction has not been started and the Orb is held by the contract.
     *          When the Orb is purchased from the creator, all proceeds go to the beneficiary and the Orb comes
     *          fully charged, with no cooldown.
     * @dev     Emits Transfer() and PriceUpdate().
     * @param   listingPrice  The price to buy the Orb from the creator.
     */
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

    /**
     * @notice  Purchasing is the mechanism to take over the Orb. With Harberger tax, the Orb can always be
     *          purchased from its holder.
     *          Purchasing is only allowed while the holder is solvent. If not, the Orb has to be foreclosed and
     *          re-auctioned.
     *          Purchaser is required to have more funds than the price itself, but the exact amount is left for the
     *          user interface implementation to calculate and send along.
     *          Purchasing sends sale royalty part to the beneficiary.
     * @dev     Requires to provide the current price as the first parameter to prevent front-running: without current
     *          price requirement someone could purchase the Orb ahead of someone else, set the price higher, and
     *          profit from the purchase.
     *          Does not modify last invocation time, unlike buying from the auction.
     *          Does not allow purchasing from yourself.
     *          Emits PriceUpdate() and Purchase().
     * @param   currentPrice  Current price, to prevent front-running.
     * @param   newPrice      New price to use after the purchase.
     */
    function purchase(uint256 currentPrice, uint256 newPrice) external payable onlyHolderHeld onlyHolderSolvent {
        if (currentPrice != price) {
            revert CurrentPriceIncorrect(currentPrice, price);
        }

        if (lastSettlementTime >= block.timestamp) {
            revert PurchasingNotPermitted();
        }

        _settle();

        address holder = ERC721.ownerOf(tokenId);

        if (msg.sender == holder) {
            revert AlreadyHolder();
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

        if (owner() == holder) {
            lastInvocationTime = block.timestamp - cooldown;
            fundsOf[beneficiary] += currentPrice;
        } else {
            uint256 beneficiaryRoyalty = (currentPrice * royaltyNumerator) / FEE_DENOMINATOR;
            uint256 currentOwnerShare = currentPrice - beneficiaryRoyalty;

            fundsOf[beneficiary] += beneficiaryRoyalty;
            fundsOf[holder] += currentOwnerShare;
        }

        lastSettlementTime = block.timestamp;

        _setPrice(newPrice);

        emit Purchase(holder, msg.sender, currentPrice);

        _transferOrb(holder, msg.sender);
    }

    /**
     * @dev  See {setPrice()}.
     */
    function _setPrice(uint256 newPrice_) internal {
        if (newPrice_ > MAX_PRICE) {
            revert InvalidNewPrice(newPrice_);
        }

        uint256 previousPrice = price;
        price = newPrice_;

        emit PriceUpdate(previousPrice, newPrice_);
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: FORECLOSURE
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Relinquishment is a voluntary giving up of the Orb. It's a combination of withdrawing all funds
     *          not owed to the beneficiary since last settlement, and foreclosing yourself after.
     *          Most useful if the creator themselves hold the Orb and want to re-auction it.
     *          For any other holder, setting the price to zero would be more practical.
     * @dev     Calls _withdraw(), which does value transfer from the contract.
     *          Emits Foreclosure() and Withdrawal().
     */
    function relinquish() external onlyHolder onlyHolderSolvent {
        _settle();

        price = 0;

        emit Relinquishment(msg.sender);

        _transferOrb(msg.sender, address(this));
        _withdraw(msg.sender, fundsOf[msg.sender]);
    }

    /**
     * @notice  Foreclose can be called by anyone after the Orb holder runs out of funds to cover the Harberger tax.
     *          It returns the Orb to the contract, readying it for re-auction.
     * @dev     Emits Foreclosure().
     */
    function foreclose() external onlyHolderHeld {
        if (holderSolvent()) {
            revert HolderSolvent();
        }

        _settle();

        address holder = ERC721.ownerOf(tokenId);
        price = 0;

        emit Foreclosure(holder);

        _transferOrb(holder, address(this));
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: INVOKING AND RESPONDING
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Invokes the Orb. Allows the holder to submit cleartext.
     * @param   cleartext  Required cleartext.
     */
    function invokeWithCleartext(string memory cleartext) external {
        uint256 length = bytes(cleartext).length;
        if (length > cleartextMaximumLength) {
            revert CleartextTooLong(length, cleartextMaximumLength);
        }
        invokeWithHash(keccak256(abi.encodePacked(cleartext)));
        emit CleartextRecording(invocationCount, cleartext);
    }

    /**
     * @notice  Invokes the Orb. Allows the holder to submit content hash, that represents a question to the Orb
     *          creator. Puts the Orb on cooldown. The Orb can only be invoked by solvent holders.
     * @dev     Content hash is keccak256 of the cleartext.
     *          invocationCount is used to track the id of the next invocation.
     *          Emits Invocation().
     * @param   contentHash  Required keccak256 hash of the cleartext.
     */
    function invokeWithHash(bytes32 contentHash) public onlyHolder onlyHolderHeld onlyHolderSolvent {
        if (block.timestamp < lastInvocationTime + cooldown) {
            revert CooldownIncomplete(lastInvocationTime + cooldown - block.timestamp);
        }

        invocationCount += 1;
        uint256 invocationId = invocationCount; // starts at 1

        invocations[invocationId] = HashTime(contentHash, block.timestamp);
        lastInvocationTime = block.timestamp;

        emit Invocation(msg.sender, invocationId, contentHash, block.timestamp);
    }

    /**
     * @notice  Function allows the holder to reveal cleartext later, either because it was challenged by the
     *          creator, or just for posterity. This function can also be used to reveal empty-string content hashes.
     * @dev     Only holders can reveal cleartext on-chain. Anyone could potentially figure out the invocation
     *          cleartext from the content hash via brute force, but publishing this on-chain is only allowed by the
     *          holder themselves, introducing a reasonable privacy protection.
     *          If the content hash is of a cleartext that is longer than maximum cleartext length, the contract will
     *          never record this cleartext, as it is invalid.
     *          Allows overwriting. Assuming no hash collisions, this poses no risk, just wastes holder gas.
     * @param   invocationId  Invocation id, matching the one that was emitted when calling
     *                        {invokeWithCleartext()} or {invokeWithHash()}.
     * @param   cleartext     Cleartext, limited in length. Must match the content hash.
     */
    function recordInvocationCleartext(uint256 invocationId, string memory cleartext)
        external
        onlyHolder
        onlyHolderSolvent
    {
        uint256 cleartextLength = bytes(cleartext).length;

        if (cleartextLength > cleartextMaximumLength) {
            revert CleartextTooLong(cleartextLength, cleartextMaximumLength);
        }

        bytes32 recordedContentHash = invocations[invocationId].contentHash;
        bytes32 cleartextHash = keccak256(abi.encodePacked(cleartext));

        if (recordedContentHash != cleartextHash) {
            revert CleartextHashMismatch(cleartextHash, recordedContentHash);
        }

        uint256 invocationTime = invocations[invocationId].timestamp;
        if (holderReceiveTime >= invocationTime) {
            revert CleartextRecordingNotPermitted(invocationId);
        }

        emit CleartextRecording(invocationId, cleartext);
    }

    /**
     * @notice  The Orb creator can use this function to respond to any existing invocation, no matter how long ago
     *          it was made. A response to an invocation can only be written once. There is no way to record response
     *          cleartext on-chain.
     * @dev     Emits Response().
     * @param   invocationId  ID of an invocation to which the response is being made.
     * @param   contentHash   keccak256 hash of the response text.
     */
    function respond(uint256 invocationId, bytes32 contentHash) external onlyOwner {
        if (invocationId > invocationCount || invocationId == 0) {
            revert InvocationNotFound(invocationId);
        }

        if (_responseExists(invocationId)) {
            revert ResponseExists(invocationId);
        }

        responses[invocationId] = HashTime(contentHash, block.timestamp);

        emit Response(msg.sender, invocationId, contentHash, block.timestamp);
    }

    /**
     * @notice  Orb holder can flag a response during Response Flagging Period, counting from when the response is made.
     *          Flag indicates a "report", that the Orb holder was not satisfied with the response provided.
     *          This is meant to act as a social signal to future Orb holders. It also increments flaggedResponsesCount,
     *          allowing anyone to quickly look up how many responses were flagged.
     * @dev     Only existing responses (with non-zero timestamps) can be flagged.
     *          Responses can only be flagged by solvent holders to keep it consistent with {invokeWithHash()} or
     *          {invokeWithCleartext()}.
     *          Also, the holder must have received the Orb after the response was made;
     *          this is to prevent holders from flagging responses that were made in response to others' invocations.
     *          Emits ResponseFlagging().
     * @param   invocationId  ID of an invocation to which the response is being flagged.
     */
    function flagResponse(uint256 invocationId) external onlyHolder onlyHolderSolvent {
        if (!_responseExists(invocationId)) {
            revert ResponseNotFound(invocationId);
        }

        // Response Flagging Period starts counting from when the response is made.
        // Its value matches the cooldown of the Orb.
        uint256 responseTime = responses[invocationId].timestamp;
        if (block.timestamp - responseTime > cooldown) {
            revert FlaggingPeriodExpired(invocationId, block.timestamp - responseTime, cooldown);
        }
        if (holderReceiveTime >= responseTime) {
            revert FlaggingPeriodExpired(invocationId, holderReceiveTime, responseTime);
        }
        if (responseFlagged[invocationId]) {
            revert ResponseAlreadyFlagged(invocationId);
        }

        responseFlagged[invocationId] = true;
        flaggedResponsesCount += 1;

        emit ResponseFlagging(msg.sender, invocationId);
    }

    /**
     * @dev     Returns if a response to an invocation exists, based on the timestamp of the response being non-zero.
     * @param   invocationId_  ID of an invocation to which to check the existance of a response of.
     * @return  bool  If a response to an invocation exists or not.
     */
    function _responseExists(uint256 invocationId_) internal view returns (bool) {
        if (responses[invocationId_].timestamp != 0) {
            return true;
        }
        return false;
    }
}
