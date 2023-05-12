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

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title   Orb - Harberger Tax NFT with auction and on-chain invocations and responses
 * @author  Jonas Lekevicius, Eric Wall
 * @dev     Supports ERC-721 interface, does not support token transfers.
 *          Uses {Ownable}'s {owner()} to identify the creator of the Orb.
 * @notice  This is a basic Q&A-type Orb. The holder has the right to submit a text-based question to the
 *          creator and the right to receive a text-based response. The question is limited in length but
 *          responses may come in any length. Questions and answers are hash-committed to the Ethereum blockchain
 *          so that the track record cannot be changed. The Orb has a cooldown.
 *
 *          The Orb uses Harberger Tax and is always on sale. This means that when you purchase the Orb, you must
 *          also set a price which you’re willing to sell the Orb at. However, you must pay an amount base on tax rate
 *          to the Orb smart contract per year in order to maintain the Orb ownership. This amount is accounted for
 *          per second, and user funds need to be topped up before the foreclosure time to maintain ownership.
 */
contract Orb is ERC721, Ownable {
    ////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////

    event Creation(bytes32 oathHash, uint256 honoredUntil);

    // Auction Events
    event AuctionStart(uint256 auctionStartTime, uint256 auctionEndTime);
    event AuctionBid(address indexed bidder, uint256 bid);
    event AuctionExtension(uint256 newAuctionEndTime);
    event AuctionFinalization(address indexed winner, uint256 winningBid);

    // Fund Management, Holding and Purchasing Events
    event Deposit(address indexed depositor, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);
    event Settlement(address indexed holder, address indexed beneficiary, uint256 amount);
    event PriceUpdate(uint256 previousPrice, uint256 newPrice);
    event Purchase(address indexed seller, address indexed buyer, uint256 price);
    event Foreclosure(address indexed formerHolder);
    event Relinquishment(address indexed formerHolder);

    // Invoking and Responding Events
    event Invocation(address indexed invoker, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);
    event Response(address indexed responder, uint256 indexed invocationId, bytes32 contentHash, uint256 timestamp);
    event CleartextRecording(uint256 indexed invocationId, string cleartext);
    event ResponseFlagging(address indexed flagger, uint256 indexed invocationId);

    // Orb Parameter Events
    event OathSwearing(bytes32 oathHash, uint256 honoredUntil);
    event HonoredUntilUpdate(uint256 previousHonoredUntil, uint256 newHonoredUntil);

    ////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////

    // ERC-721 Errors
    error TransferringNotSupported();

    // Authorization Errors
    error AlreadyHolder();
    error NotHolder();
    error ContractHoldsOrb();
    error ContractDoesNotHoldOrb();
    error CreatorDoesNotControlOrb();
    error BeneficiaryDisallowed();

    // Orb Parameter Errors
    error HonoredUntilNotDecreasable();

    // Funds-Related Authorization Errors
    error HolderSolvent();
    error HolderInsolvent();
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);

    // Auction Errors
    error AuctionNotRunning();
    error AuctionRunning();
    error AuctionNotStarted();
    error NotPermittedForLeadingBidder();
    error InsufficientBid(uint256 bidProvided, uint256 bidRequired);

    // Purchasing Errors
    error CurrentPriceIncorrect(uint256 priceProvided, uint256 currentPrice);
    error PurchasingNotPermitted();
    error InvalidNewPrice(uint256 priceProvided);

    // Invoking and Responding Errors
    error CooldownIncomplete(uint256 timeRemaining);
    error CleartextTooLong(uint256 cleartextLength, uint256 cleartextMaximumLength);
    error CleartextHashMismatch(bytes32 cleartextHash, bytes32 recordedContentHash);
    error InvocationNotFound(uint256 invocationId);
    error ResponseNotFound(uint256 invocationId);
    error ResponseExists(uint256 invocationId);
    error FlaggingPeriodExpired(uint256 invocationId, uint256 currentTimeValue, uint256 timeValueLimit);
    error ResponseAlreadyFlagged(uint256 invocationId);

    ////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS AND IMMUTABLES

    // Beneficiary receives all Orb proceeds.
    address public immutable beneficiary;

    // Fee Nominator: basis points. Other fees are in relation to this.
    uint256 public constant FEE_DENOMINATOR = 10_000;
    // Harberger Tax period: for how long the Tax Rate applies. Value: 1 year.
    uint256 public constant HOLDER_TAX_PERIOD = 365 days;

    // Internal Immutables and Constants

    // Orb tokenId. Can be whatever arbitrary number, only one token will ever exist.
    uint256 internal immutable tokenId;

    // Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant MAX_PRICE = 2 ** 128;

    // STATE

    // Honored Until: timestamp until which the Orb Oath is honored for the holder.
    uint256 public honoredUntil;

    // Base URL for tokenURL JSONs.
    string internal baseURL = "https://static.orb.land/orb/";

    // Funds tracker, per address. Modified by deposits, withdrawals and settlements.
    // The value is without settlement. It means effective user funds (withdrawable) would be different
    // for holder (subtracting owedSinceLastSettlement) and beneficiary (adding owedSinceLastSettlement).
    // If Orb is held by the creator, funds are not subtracted, as Harberger Tax does not apply to the creator.
    mapping(address => uint256) public fundsOf;

    // Taxes State Variables

    // Harberger Tax for holding. Initial value is 10%.
    uint256 public holderTaxNumerator = 1_000;
    // Secondary sale royalty paid to beneficiary, based on sale price.
    uint256 public royaltyNumerator = 1_000;
    // Price of the Orb. No need for mapping, as only one token is ever minted.
    // Also used during auction to store future purchase price.
    // Shouldn't be useful if the Orb is held by the contract.
    uint256 public price;
    // Last time Orb holder's funds were settled.
    // Shouldn't be useful if the Orb is held by the contract.
    uint256 public lastSettlementTime;

    // Auction State Variables

    // Auction starting price.
    uint256 public auctionStartingPrice = 0.1 ether;
    // Each bid has to increase over previous bid by at least this much.
    uint256 public auctionMinimumBidStep = 0.1 ether;
    // Auction will run for at least this long.
    uint256 public auctionMinimumDuration = 1 days;
    // If remaining time is less than this after a bid is made, auction will continue for at least this long.
    uint256 public auctionBidExtension = 5 minutes;
    // Start Time: when the auction was started. Stays fixed during the auction, otherwise 0.
    uint256 public auctionStartTime;
    // End Time: when the auction ends, can be extended by late bids. 0 not during the auction.
    uint256 public auctionEndTime;
    // Winning Bidder: address that currently has the highest bid. 0 not during the auction and before first bid.
    address public leadingBidder;
    // Winning Bid: highest current bid. 0 not during the auction and before first bid.
    uint256 public leadingBid;

    // Invocation and Response State Variables

    // Struct used to track response information: content hash and timestamp.
    // Timestamp is used to determine if the response can be flagged by the holder.
    // Invocation timestamp doesn't need to be tracked, as nothing is done with it.
    struct HashTime {
        // keccak256 hash of the cleartext
        bytes32 contentHash;
        uint256 timestamp;
    }

    // Cooldown: how often Orb can be invoked.
    uint256 public cooldown = 7 days;
    // Maximum length for invocation cleartext content.
    uint256 public cleartextMaximumLength = 280;
    // Holder Receive Time: When the Orb was last transferred, except to this contract.
    uint256 public holderReceiveTime;
    // Last Invocation Time: when the Orb was last invoked. Used together with Cooldown constant.
    uint256 public lastInvocationTime;

    // Mapping for Invocation: invocationId to HashTime.
    mapping(uint256 => HashTime) public invocations;
    // Count of invocations made. Used to calculate invocationId of the next invocation.
    uint256 public invocationCount = 0;
    // Mapping for Responses (Answers to Invocations): matching invocationId to HashTime struct.
    mapping(uint256 => HashTime) public responses;
    // Additional mapping for flagged (reported) Responses. Used by the holder not satisfied with a response.
    mapping(uint256 => bool) public responseFlagged;
    // A convencience count of total responses made. Not used by the contract itself.
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
        uint256 honoredUntil_
    ) ERC721(name_, symbol_) {
        tokenId = tokenId_;
        beneficiary = beneficiary_;
        honoredUntil = honoredUntil_;

        emit Creation(oathHash_, honoredUntil_);

        _safeMint(address(this), tokenId);
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
        return baseURL;
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

        auctionStartTime = block.timestamp;
        auctionEndTime = block.timestamp + auctionMinimumDuration;

        emit AuctionStart(auctionStartTime, auctionEndTime);
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

        auctionStartTime = 0;
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

        if (lastSettlementTime == block.timestamp) {
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
        emit CleartextRecording(invocationCount, cleartext);
        invokeWithHash(keccak256(abi.encodePacked(cleartext)));
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

        uint256 invocationId = invocationCount;

        invocations[invocationId] = HashTime(contentHash, block.timestamp);
        lastInvocationTime = block.timestamp;
        invocationCount += 1;

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
        if (invocationId >= invocationCount) {
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
