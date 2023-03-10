// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title   Eric's Orb - Harberger Tax NFT with auction and on-chain triggers and responses
 * @author  Jonas Lekevicius, Eric Wall
 * @dev     Supports ERC-721 interface, does not support token transfers.
 *          Uses {Ownable}'s {owner()} to identify the issuer of the Orb.
 * @notice  Eric's Orb is a basic Q&A-type Orb. The holder has the right to submit a text-based question to
 *          Eric and the right to receive a text-based response. The question is limited to 280 characters but
 *          responses may come in any length. Questions and answers are hash-committed to the Ethereum blockchain
 *          so that the track record cannot be changed. The Orb has a 1-week cooldown.
 *
 *          The Orb uses Harberger Tax and is always on sale. This means that when you purchase the Orb, you must
 *          also set a price which you’re willing to sell the Orb at. However, you must pay 10% of that amount to
 *          the Orb smart contract per year in order to maintain the Orb ownership. This amount is accounted for
 *          per second, and user funds need to be topped up before the foreclosure time to maintain ownership.
 */
contract EricOrb is ERC721, Ownable {
    ////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////

    // Auction Events
    event AuctionStarted(uint256 startTime, uint256 endTime);
    event NewBid(address indexed from, uint256 price);
    event UpdatedAuctionEnd(uint256 endTime);
    event AuctionFinalized(address indexed winner, uint256 price);

    // Fund Management, Holding and Purchasing Events
    event Deposit(address indexed sender, uint256 amount);
    event Withdrawal(address indexed recipient, uint256 amount);
    event Settlement(address indexed from, address indexed to, uint256 amount);
    event NewPrice(uint256 from, uint256 to);
    event Purchase(address indexed from, address indexed to);
    event Foreclosure(address indexed from);

    // Triggering and Responding Events
    event Triggered(address indexed from, uint256 indexed triggerId, bytes32 contentHash, uint256 time);
    event Responded(address indexed from, uint256 indexed triggerId, bytes32 contentHash, uint256 time);
    event ResponseFlagged(address indexed from, uint256 indexed responseId);

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

    // Funds-Related Authorization Errors
    error HolderSolvent();
    error HolderInsolvent();
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);

    // Auction Errors
    error AuctionNotRunning();
    error AuctionRunning();
    error AuctionNotStarted();
    error NotPermittedForWinningBidder();
    error InsufficientBid(uint256 bidProvided, uint256 bidRequired);

    // Purchasing Errors
    error CurrentPriceIncorrect(uint256 priceProvided, uint256 currentPrice);
    error InvalidNewPrice(uint256 priceProvided);

    // Triggering and Responding Errors
    error CooldownIncomplete(uint256 timeRemaining);
    error CleartextTooLong(uint256 cleartextLength, uint256 maxLength);
    error CleartextHashMismatch(bytes32 cleartextHash, bytes32 contentHash);
    error TriggerNotFound(uint256 triggerId);
    error ResponseNotFound(uint256 triggerId);
    error ResponseExists(uint256 triggerId);
    error FlaggingPeriodExpired(uint256 triggerId, uint256 currentTimeValue, uint256 timeValueLimit);
    error ResponseAlreadyFlagged(uint256 triggerId);

    ////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS

    // Public Constants
    // Cooldown: how often Orb can be triggered.
    uint256 public constant COOLDOWN = 7 days;
    // Response Flagging Period: how long after resonse was recorded it can be flagged by the holder.
    uint256 public constant RESPONSE_FLAGGING_PERIOD = 7 days;
    // Maximum length for trigger cleartext content; tweet length.
    uint256 public constant MAX_CLEARTEXT_LENGTH = 280;

    // Fee Nominator: basis points. Other fees are in relation to this.
    uint256 public constant FEE_DENOMINATOR = 10000;
    // Harberger Tax for holding. Value: 10%.
    uint256 public constant HOLDER_TAX_NUMERATOR = 1000;
    // Harberger Tax period: for how long the Tax Rate applies. Value: 1 year. So, 10% of price per year.
    uint256 public constant HOLDER_TAX_PERIOD = 365 days;
    // Secondary sale (royalties) to issuer: 10% of the sale price.
    uint256 public constant SALE_ROYALTIES_NUMERATOR = 1000;

    // Auction starting price.
    uint256 public constant STARTING_PRICE = 0.1 ether;
    // Each bid has to increase over previous bid by at least this much.
    uint256 public constant MINIMUM_BID_STEP = 0.01 ether;
    // Auction will run for at least this long.
    uint256 public constant MINIMUM_AUCTION_DURATION = 1 days;
    // If remaining time is less than this after a bid is made, auction will continue for at least this long.
    uint256 public constant BID_AUCTION_EXTENSION = 30 minutes;

    // Internal Constants
    // Eric's Orb tokenId. Can be whatever arbitrary number, only one token will ever exist. Value: nice.
    uint256 internal constant ERIC_ORB_ID = 69;
    // Base URL for tokenURL JSONs.
    string internal constant BASE_URL = "https://static.orb.land/eric/";
    // Special value returned when foreclosure time is "never".
    uint256 internal constant INFINITY = type(uint256).max;
    // Maximum orb price, limited to prevent potential overflows.
    uint256 internal constant MAX_PRICE = 2 ** 128;

    // STATE

    // Funds tracker, per address. Modified by deposits, withdrawals and settlements.
    mapping(address => uint256) public fundsOf;

    // Price of the Orb. No need for mapping, as only one token is very minted.
    // Shouldn't be useful is orb is held by the contract.
    uint256 public price;
    // Last time orb holder's funds were settled.
    // Shouldn't be useful is orb is held by the contract.
    uint256 public lastSettlementTime;

    // Auction State Variables
    // Start Time: when the auction was started. Stays fixed during the auction, otherwise 0.
    uint256 public startTime;
    // End Time: when the auction ends, can be extended by late bids. 0 not during the auction.
    uint256 public endTime;
    // Winning Bidder: address that currently has the highest bid. 0 not during the auction and before first bid.
    address public winningBidder;
    // Winning Bid: highest current bid. 0 not during the auction and before first bid.
    // Note: user has to deposit more than just the bid to ensure solvency after auction is finalized.
    uint256 public winningBid;

    // Trigger and Response State Variables

    // Struct used to track both triggger and response base information: content hash and timestamp.
    struct HashTime {
        // keccak256 hash of the cleartext
        bytes32 contentHash;
        uint256 timestamp;
    }

    // Holder Receive Time: When the orb was last transferred, except to this contract.
    uint256 public holderReceiveTime;
    // Last Trigger Time: when the orb was last triggered. Used together with Cooldown constant.
    uint256 public lastTriggerTime;
    // Mapping for Triggers (Orb Invocations): triggerId to contentHash (bytes32).
    mapping(uint256 => bytes32) public triggers;
    // Count of triggers made. Used to calculate triggerId of the next trigger.
    uint256 public triggersCount = 0;
    // Mapping for Responses (Replies to Triggers): matching triggerId to HashTime struct.
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
     *       {Ownable} sets the deployer to be the owner, and also the issuer in the orb context.
     */
    constructor() ERC721("Eric's Orb", "ORB") {
        _safeMint(address(this), ERIC_ORB_ID);
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  MODIFIERS
    ////////////////////////////////////////////////////////////////////////////////

    // AUTHORIZATION MODIFIERS

    /**
     * @notice  Contract inherits {onlyOwner} modifier from {Ownable}.
     */

    /**
     * @dev  Ensures that the caller owns the orb.
     *       Should only be used in conjuction with {onlyHolderHeld} or on external functions,
     *       otherwise does not make sense.
     */
    modifier onlyHolder() {
        if (msg.sender != ERC721.ownerOf(ERIC_ORB_ID)) {
            revert NotHolder();
        }
        _;
    }

    // ORB STATE MODIFIERS

    /**
     * @dev  Ensures that the orb belongs to someone, not the contract itself.
     */
    modifier onlyHolderHeld() {
        if (address(this) == ERC721.ownerOf(ERIC_ORB_ID)) {
            revert ContractHoldsOrb();
        }
        _;
    }

    /**
     * @dev  Ensures that the orb belongs to the contract itself, either because it hasn't been auctioned,
     *       or because it has returned to the contract due to {exit()} or {foreclose()}
     */
    modifier onlyContractHeld() {
        if (address(this) != ERC721.ownerOf(ERIC_ORB_ID)) {
            revert ContractDoesNotHoldOrb();
        }
        _;
    }

    // AUCTION MODIFIERS

    /**
     * @dev  Ensures that an auction is currently running.
     */
    modifier onlyDuringAuction() {
        if (!auctionRunning()) {
            revert AuctionNotRunning();
        }
        _;
    }

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

    /**
     * @dev  Ensures that the caller is not currently winning the auction.
     *       User winning the auction cannot withdraw funds, as funds include user's bid.
     */
    modifier notWinningBidder() {
        if (msg.sender == winningBidder) {
            revert NotPermittedForWinningBidder();
        }
        _;
    }

    // FUNDS-RELATED MODIFIERS

    /**
     * @dev  Ensures that the current orb holder has enough funds to cover Harberger tax until now.
     */
    modifier onlyHolderSolvent() {
        if (!holderSolvent()) {
            revert HolderInsolvent();
        }
        _;
    }

    /**
     * @dev  Ensures that the current orb holder has run out of funds to cover Harberger tax.
     */
    modifier onlyHolderInsolvent() {
        if (holderSolvent()) {
            revert HolderSolvent();
        }
        _;
    }

    /**
     * @dev  Modifier settles current orb holder's debt before executing the rest of the function.
     */
    modifier settles() {
        _settle();
        _;
    }

    /**
     * @dev  Modifier settles current orb holder's debt before executing the rest of the function,
     *       only if the caller is the orb holder. Useful for holder withdrawals.
     */
    modifier settlesIfHolder() {
        if (msg.sender == ERC721.ownerOf(ERIC_ORB_ID)) {
            _settle();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ERC-721 OVERRIDES
    ////////////////////////////////////////////////////////////////////////////////

    function _baseURI() internal pure override returns (string memory) {
        return BASE_URL;
    }

    /**
     * @notice  Transfers the orb to another address. Not allowed, always reverts.
     * @dev     Always reverts. In future versions we might allow transfers.
     *          Transfers would settle (both accounts in multi-orb) and require the receiver to have deposit.
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
    function _transferOrb(address oldAddress, address newAddress) internal {
        _transfer(oldAddress, newAddress, ERIC_ORB_ID);
        if (newAddress != address(this)) {
            holderReceiveTime = block.timestamp;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: AUCTION
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Returns if the auction is currently running. Use endTime() to check when it ends.
     * @dev     Start time will always be less than timestamp, as it resets to 0.
     *          Start time is only updated for auction progress tracking, not critical functionality.
     * @return  bool  If the auction is running.
     */
    function auctionRunning() public view returns (bool) {
        return endTime > block.timestamp && address(this) == ERC721.ownerOf(ERIC_ORB_ID);
    }

    /**
     * @notice  Minimum bid that would currently be accepted by {bid()}.
     * @dev     STARTING_PRICE if no bids were made, otherwise previous bid increased by MINIMUM_BID_STEP.
     * @return  uint256  Minimum bid required for {bid()}.
     */
    function minimumBid() public view returns (uint256) {
        if (winningBid == 0) {
            return STARTING_PRICE;
        } else {
            unchecked {
                return winningBid + MINIMUM_BID_STEP;
            }
        }
    }

    /**
     * @notice  Total funds (funds on contract + sent value) required to fund a bid of a given value.
     *          Returns bid amount + enough to cover the Harberger tax for one Harberger tax period, 1 year by default.
     * @dev     Can be used together with {minimumBid()} and {fundsOf{}} to figure out msg.value required for bid().
     * @param   amount  Bid amount to calculate for.
     * @return  uint256  Total funds required to satisfy the bid of `amount`.
     */
    function fundsRequiredToBid(uint256 amount) public pure returns (uint256) {
        return amount + (amount * HOLDER_TAX_NUMERATOR) / FEE_DENOMINATOR;
    }

    /**
     * @notice  Allow the Orb issuer to start the Orb Auction. Will run for at lest MINIMUM_AUCTION_DURATION.
     * @dev     Prevents repeated starts by checking the endTime.
     *          Important to set endTime to 0 after auction is finalized.
     *          Also, resets winningBidder and winningBid.
     *          Should not be necessary, as {finalizeAuction()} also does that.
     *          Emits AuctionStarted().
     */
    function startAuction() external onlyOwner onlyContractHeld notDuringAuction {
        if (endTime > 0) {
            revert AuctionRunning();
        }

        startTime = block.timestamp;
        endTime = block.timestamp + MINIMUM_AUCTION_DURATION;
        winningBidder = address(0);
        winningBid = 0;

        emit AuctionStarted(startTime, endTime);
    }

    /**
     * @notice  Bids the provided amount, if there's enough funds across funds on contract and transaction value.
     *          Might extend the auction if the bid is near the end.
     *          Important: the winning bidder will not be able to withdraw funds until someone outbids them.
     * @dev     Emits NewBid().
     * @param   amount  The value to bid.
     */
    function bid(uint256 amount) external payable onlyDuringAuction {
        uint256 totalFunds = fundsOf[msg.sender] + msg.value;

        if (amount < minimumBid()) {
            revert InsufficientBid(amount, minimumBid());
        }

        if (totalFunds < fundsRequiredToBid(amount)) {
            revert InsufficientFunds(totalFunds, fundsRequiredToBid(amount));
        }

        fundsOf[msg.sender] = totalFunds;
        winningBidder = msg.sender;
        winningBid = amount;

        emit NewBid(msg.sender, amount);

        if (block.timestamp + BID_AUCTION_EXTENSION > endTime) {
            endTime = block.timestamp + BID_AUCTION_EXTENSION;
            emit UpdatedAuctionEnd(endTime);
        }
    }

    /**
     * @notice  Finalizes the Auction, transferring the winning bid to the issuer, and the orb to the winner.
     *          Sets lastTriggerTime so that the Orb could be triggered immediately.
     *          If no bids were made, resets the state to allow the auction to be started again later.
     * @dev     Critical state transition function. Called after endTime, but only if it's not 0.
     *          Can be called by anyone, although probably will be called by the issuer or the winner.
     *          Emits NewPrice() and AuctionFinalized().
     */
    function finalizeAuction() external notDuringAuction {
        if (endTime == 0) {
            revert AuctionNotStarted();
        }

        if (winningBidder != address(0)) {
            _setPrice(winningBid);
            fundsOf[winningBidder] -= price;
            fundsOf[owner()] += price;

            lastSettlementTime = block.timestamp;
            lastTriggerTime = block.timestamp - COOLDOWN;

            emit AuctionFinalized(winningBidder, winningBid);

            _transferOrb(address(this), winningBidder);
            winningBidder = address(0);
            winningBid = 0;
        } else {
            emit AuctionFinalized(winningBidder, winningBid);
        }

        startTime = 0;
        endTime = 0;
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: FUNDS AND HOLDING
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Returns funds for an address on this contract, freely available to withdraw.
     *          Accounts for owed Harberger tax, so can be used to display an actual effective balance.
     * @dev     The only addresses where this mismatches with {fundsOf[]} is the issuer and the holder.
     * @param   user  Address to return effective funds of.
     * @return  uint256  Address effective funds.
     */
    function effectiveFundsOf(address user) external view returns (uint256) {
        uint256 unadjustedFunds = fundsOf[user];
        address holder = ERC721.ownerOf(ERIC_ORB_ID);

        if ((user == owner() || user == holder) && owner() != holder) {
            uint256 owedFunds = _owedSinceLastSettlement();
            uint256 holderFunds = fundsOf[holder];
            uint256 transferableToOwner = holderFunds <= owedFunds ? holderFunds : owedFunds;

            if (user == owner()) {
                return unadjustedFunds + transferableToOwner;
            }
            if (user == holder) {
                return unadjustedFunds - transferableToOwner;
            }
        }

        return unadjustedFunds;
    }

    /**
     * @notice  Allows depositing funds on the contract. Not allowed for insolvent holders.
     * @dev     Deposits are not allowed for insolvent holders to prevent cheating via front-running.
     *          If the user becomes insolvent, the orb will always be returned to the contract as the next step.
     *          Emits Deposit().
     */
    function deposit() external payable {
        if (msg.sender == ERC721.ownerOf(ERIC_ORB_ID) && !holderSolvent()) {
            revert HolderInsolvent();
        }

        fundsOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice  Function to withdraw all funds on the contract.
     *          Not recommended for current orb holders, they should call exit() to take out their funds.
     * @dev     Not allowed for the winning auction bidder.
     */
    function withdrawAll() external notWinningBidder settlesIfHolder {
        _withdraw(fundsOf[msg.sender]);
    }

    /**
     * @notice  Function to withdraw given amount from the contract.
     *          For current orb holders, reduces the time until foreclosure.
     * @dev     Not allowed for the winning auction bidder.
     */
    function withdraw(uint256 amount) external notWinningBidder settlesIfHolder {
        _withdraw(amount);
    }

    /**
     * @notice  Settlements transfer funds from orb holder to orb issuer.
     *          Orb accounting minimizes required transactions: orb holder's foreclosure time is only
     *          dependent on the price and available funds. Fund transfers are not necessary unless
     *          these variables (price, holder funds) are being changed. Settlement transfers funds owed
     *          since the last settlement, and a new period of virtual accounting begins.
     * @dev     Holder might owe more than they have funds available: it means that the holder is foreclosable.
     *          Settlement would transfer all holder funds to the issuer, but not more.
     *          Does nothing if the issuer holds the orb. Reverts if contract holds the orb.
     *          Emits Settlement().
     */
    function settle() external onlyHolderHeld {
        _settle();
    }

    /**
     * @dev     Returns if the current orb holder has enough funds to cover Harberger tax until now.
     *          Always true is issuer holds the orb.
     * @return  bool  If the current holder is solvent.
     */
    function holderSolvent() public view returns (bool) {
        address holder = ERC721.ownerOf(ERIC_ORB_ID);
        if (owner() == holder) {
            return true;
        }
        return fundsOf[holder] > _owedSinceLastSettlement();
    }

    /**
     * @dev     Calculates how much money orb holder owes orb issuer. This amount would be transferred between
     *          accounts during settlement.
     *          Owed amount can be higher than hodler's funds! It's important to check if holder has enough funds
     *          before transferring.
     * @return  bool  Wei orb holders owes orb issuer since the last settlement time.
     */
    function _owedSinceLastSettlement() internal view returns (uint256) {
        uint256 secondsSinceLastSettlement = block.timestamp - lastSettlementTime;
        return (price * HOLDER_TAX_NUMERATOR * secondsSinceLastSettlement) / (HOLDER_TAX_PERIOD * FEE_DENOMINATOR);
    }

    /**
     * @dev     Executes the withdrawal for a given amount, does the actual value transfer from the contract
     *          to user's wallet. The only function in the contract that sends value and has re-entrancy risk.
     *          Does not check if the address is payable, as the Address library reverts if it is not.
     *          Emits Withdrawal().
     * @param   amount_  The value in wei to withdraw from the contract.
     */
    function _withdraw(uint256 amount_) internal {
        if (fundsOf[msg.sender] < amount_) {
            revert InsufficientFunds(fundsOf[msg.sender], amount_);
        }

        fundsOf[msg.sender] -= amount_;

        emit Withdrawal(msg.sender, amount_);

        Address.sendValue(payable(msg.sender), amount_);
    }

    /**
     * @dev  See {settle()}.
     */
    function _settle() internal {
        address holder = ERC721.ownerOf(ERIC_ORB_ID);

        if (owner() == holder) {
            return;
        }

        // Should never be reached if this contract holds the orb.
        assert(address(this) != holder);

        uint256 availableFunds = fundsOf[holder];
        uint256 owedFunds = _owedSinceLastSettlement();
        uint256 transferableToOwner = availableFunds <= owedFunds ? availableFunds : owedFunds;

        fundsOf[holder] -= transferableToOwner;
        fundsOf[owner()] += transferableToOwner;

        lastSettlementTime = block.timestamp;

        emit Settlement(holder, owner(), transferableToOwner);
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: PURCHASING
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Sets the new purchase price for the orb. Harberger tax means the asset is always for sale.
     *          The price can be set to zero, making foreclosure time to be never.
     * @dev     Can only be called by a solvent holder.
     *          Settles before adjusting the price, as the new price will change foreclosure time.
     *          Does not check if the new price differs from the previous price: no risk.
     *          Limits the price to MAX_PRICE to prevent potential overflows in math.
     *          Emits NewPrice().
     * @param   newPrice  New price for the orb.
     */
    function setPrice(uint256 newPrice) external onlyHolder onlyHolderSolvent settles {
        _setPrice(newPrice);
    }

    /**
     * @notice  Purchasing is the mechanism to take over the orb. With Harberger tax, an orb can always be
     *          purchased from its holder.
     *          Purchasing is only allowed while the holder is solvent. If not, the orb has to be foreclosed and
     *          re-auctioned.
     *          Purchaser is required to have more funds than the price itself, but the exact amount is left for the
     *          user interface implementation to calculate and send along.
     *          Purchasing sends Sale Royalties part to the orb issuer, 10% by default.
     * @dev     Requires to provide the current price as the first parameter to prevent front-running: without current
     *          price requirement someone could purchase the orb ahead of someone else, set the price higher, and
     *          profit from the purchase.
     *          Does not modify last trigger time, unlike buying from the auction.
     *          Does not allow purchasing from yourself.
     *          Emits NewPrice() and Purchase().
     * @param   currentPrice  Current price, to prevent front-running.
     * @param   newPrice  New price to use after the purchase.
     */
    function purchase(uint256 currentPrice, uint256 newPrice)
        external
        payable
        onlyHolderHeld
        onlyHolderSolvent
        settles
    {
        if (currentPrice != price) {
            revert CurrentPriceIncorrect(currentPrice, price);
        }

        address holder = ERC721.ownerOf(ERIC_ORB_ID);

        if (msg.sender == holder) {
            revert AlreadyHolder();
        }

        fundsOf[msg.sender] += msg.value;
        uint256 totalFunds = fundsOf[msg.sender];

        if (totalFunds < currentPrice) {
            revert InsufficientFunds(totalFunds, currentPrice);
        }

        uint256 ownerRoyalties = (currentPrice * SALE_ROYALTIES_NUMERATOR) / FEE_DENOMINATOR;
        uint256 currentOwnerShare = currentPrice - ownerRoyalties;

        fundsOf[msg.sender] -= currentPrice;
        fundsOf[owner()] += ownerRoyalties;
        fundsOf[holder] += currentOwnerShare;

        lastSettlementTime = block.timestamp;

        _setPrice(newPrice);

        emit Purchase(holder, msg.sender);

        _transferOrb(holder, msg.sender);
    }

    /**
     * @dev  See {setPrice()}.
     */
    function _setPrice(uint256 newPrice_) internal {
        if (newPrice_ > MAX_PRICE) {
            revert InvalidNewPrice(newPrice_);
        }

        uint256 oldPrice = price;
        price = newPrice_;

        emit NewPrice(oldPrice, newPrice_);
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: FORECLOSURE
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Exit is a voluntary giving up of the orb. It's a combination of withdrawing all funds not owed to
     *          the issuer since last settlement, and foreclosing yourself after.
     *          Most useful if the issuer themselves hold the orb and want to re-auction it.
     *          For any other holder, setting the price to zero would be more practical.
     * @dev     Calls _withdraw(), which does value transfer from the contract.
     *          Emits Foreclosure() and Withdrawal().
     */
    function exit() external onlyHolder onlyHolderSolvent settles {
        price = 0;

        emit Foreclosure(msg.sender);

        _transferOrb(msg.sender, address(this));
        _withdraw(fundsOf[msg.sender]);
    }

    /**
     * @notice  Foreclose can be called by anyone after the orb holder runs out of funds to cover the Harberger tax.
     *          It returns the orb to the contract, readying it for re-auction.
     * @dev     Emits Foreclosure().
     */
    function foreclose() external onlyHolderHeld onlyHolderInsolvent settles {
        address holder = ERC721.ownerOf(ERIC_ORB_ID);
        price = 0;
        emit Foreclosure(holder);
        _transferOrb(holder, address(this));
    }

    /**
     * @notice  Foreclosure time is time when the current holder will no longer have enough funds to cover the
     *          Harberger tax and can be foreclosed.
     * @dev     Only valid if someone, not the contract, holds the orb.
     *          If orb is held by the issuer or if the price is zero, foreclosure time is a special value INFINITY.
     * @return  uint256  Timestamp of the foreclosure time.
     */
    function foreclosureTime() external view returns (uint256) {
        address holder = ERC721.ownerOf(ERIC_ORB_ID);
        if (owner() == holder) {
            return INFINITY;
        }

        // Avoid division by zero.
        if (price == 0) {
            return INFINITY;
        }

        uint256 remainingSeconds =
            (fundsOf[holder] * HOLDER_TAX_PERIOD * FEE_DENOMINATOR) / (price * HOLDER_TAX_NUMERATOR);
        return lastSettlementTime + remainingSeconds;
    }

    ////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: TRIGGERING AND RESPONDING
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice  Time remaining until the orb can be triggered again.
     *          Returns zero if the cooldown has expired and the orb is ready.
     * @dev     This function is only meaningful if the orb is not held by contract, and the holder is solvent.
     *          Contract itself cannot trigger the orb, so the response would be meaningless.
     * @return  uint256  Time in seconds until the orb is ready to be triggered.
     */
    function cooldownRemaining() external view returns (uint256) {
        uint256 cooldownExpires = lastTriggerTime + COOLDOWN;
        if (block.timestamp >= cooldownExpires) {
            return 0;
        } else {
            return cooldownExpires - block.timestamp;
        }
    }

    /**
     * @notice  Triggers the orb (otherwise known as Orb Invocation). Allows the holder to submit cleartext.
     * @param   cleartext  Required cleartext.
     */
    function triggerWithCleartext(string memory cleartext) external {
        uint256 length = bytes(cleartext).length;
        if (length > MAX_CLEARTEXT_LENGTH) {
            revert CleartextTooLong(length, MAX_CLEARTEXT_LENGTH);
        }
        triggerWithHash(keccak256(abi.encodePacked(cleartext)));
    }

    /**
     * @notice  Triggers the orb (otherwise known as Orb Invocation). Allows the holder to submit content hash,
     *          that represents a question to the orb issuer.
     *          Puts the orb on cooldown.
     *          The Orb can only be triggered by solvent holders.
     * @dev     Content hash is keccak256 of the cleartext.
     *          triggersCount is used to track the id of the next trigger.
     *          Emits Triggered().
     * @param   contentHash  Required keccak256 hash of the cleartext.
     */
    function triggerWithHash(bytes32 contentHash) public onlyHolder onlyHolderHeld onlyHolderSolvent {
        if (block.timestamp < lastTriggerTime + COOLDOWN) {
            revert CooldownIncomplete(lastTriggerTime + COOLDOWN - block.timestamp);
        }

        uint256 triggerId = triggersCount;

        triggers[triggerId] = contentHash;
        lastTriggerTime = block.timestamp;
        triggersCount += 1;

        emit Triggered(msg.sender, triggerId, contentHash, block.timestamp);
    }

    /**
     * @notice  Function allows the holder to reveal cleartext later, either because it was challenged by the
     *          issuer, or just for posterity. This function can also be used to reveal empty-string content hashes.
     * @dev     Only holders can reveal cleartext on-chain. Anyone could potentially figure out the trigger cleartext
     *          from the content hash via brute force, but publishing this on-chain is only allowed by the holder
     *          themselves, introducing a reasonable privacy protection.
     *          If the content hash is of a cleartext that is longer than maximum cleartext length, the contract will
     *          never record this cleartext, as it is invalid.
     *          Allows overwriting. Assuming no hash collisions, this poses no risk, just wastes holder gas.
     * @param   triggerId  Triggred id, matching the one that was emitted when calling {trigger()}.
     * @param   cleartext  Cleartext, limited to tweet length. Must match the content hash.
     */
    function recordTriggerCleartext(uint256 triggerId, string memory cleartext)
        external
        view
        onlyHolder
        onlyHolderSolvent
    {
        uint256 cleartextLength = bytes(cleartext).length;

        if (cleartextLength > MAX_CLEARTEXT_LENGTH) {
            revert CleartextTooLong(cleartextLength, MAX_CLEARTEXT_LENGTH);
        }

        bytes32 recordedContentHash = triggers[triggerId];
        bytes32 cleartextHash = keccak256(abi.encodePacked(cleartext));

        if (recordedContentHash != cleartextHash) {
            revert CleartextHashMismatch(cleartextHash, recordedContentHash);
        }
    }

    /**
     * @notice  The Orb issuer can use this function to respond to any existing trigger, no matter how long ago
     *          it was made. A response to a trigger can only be written once. There is no way to record response
     *          cleartext on-chain.
     * @dev     Emits Responded().
     * @param   triggerId  ID of a trigger to which the response is being made.
     * @param   contentHash  keccak256 hash of the response text.
     */
    function respond(uint256 triggerId, bytes32 contentHash) external onlyOwner {
        if (triggerId >= triggersCount) {
            revert TriggerNotFound(triggerId);
        }

        if (_responseExists(triggerId)) {
            revert ResponseExists(triggerId);
        }

        responses[triggerId] = HashTime(contentHash, block.timestamp);

        emit Responded(msg.sender, triggerId, contentHash, block.timestamp);
    }

    /**
     * @notice  Orb holder can flag a response during Response Flagging Period, counting from when the response is made.
     *          Flag indicates a "report", that the orb holder was not satisfied with the response provided.
     *          This is meant to act as a social signal to future orb holders. It also increments flaggedResponsesCount,
     *          allowing anyone to quickly look up how many responses were flagged.
     * @dev     Only existing responses (with non-zero timestamps) can be flagged.
     *          Responses can only be flagged by solvent holders to keep it consistent with {trigger()}.
     *          Emits ResponseFlagged().
     * @param   triggerId  ID of a trigger to which the response is being flagged.
     */
    function flagResponse(uint256 triggerId) external onlyHolder onlyHolderSolvent {
        if (!_responseExists(triggerId)) {
            revert ResponseNotFound(triggerId);
        }

        // Response Flagging Period starts counting from when the response is made.
        uint256 responseTime = responses[triggerId].timestamp;
        if (block.timestamp - responseTime > RESPONSE_FLAGGING_PERIOD) {
            revert FlaggingPeriodExpired(triggerId, block.timestamp - responseTime, RESPONSE_FLAGGING_PERIOD);
        }
        if (holderReceiveTime >= responseTime) {
            revert FlaggingPeriodExpired(triggerId, holderReceiveTime, responseTime);
        }
        if (responseFlagged[triggerId]) {
            revert ResponseAlreadyFlagged(triggerId);
        }

        responseFlagged[triggerId] = true;
        flaggedResponsesCount += 1;

        emit ResponseFlagged(msg.sender, triggerId);
    }

    /**
     * @dev     Returns if a response to a trigger exists, based on the timestamp of the response being non-zero.
     * @param   triggerId_  ID of a trigger to which to check the existance of a response of.
     * @return  bool  If a response to a trigger exists or not.
     */
    function _responseExists(uint256 triggerId_) internal view returns (bool) {
        if (responses[triggerId_].timestamp != 0) {
            return true;
        }
        return false;
    }
}