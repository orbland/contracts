// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title   Eric's Orb - Harberger Tax NFT with auction and on-chain triggers and responses
 * @author  Jonas Lekevicius, Eric Wall
 * @dev     Supperts ERC-721 interface, does not support token transfers.
 *          Uses {Ownable}'s {owner()} to identify the issuer of the Orb.
 * @notice  TODO human-friendly introduction to the contract.
 */
contract EricOrb is ERC721, Ownable {
  ////////////////////////////////////////////////////////////////////////////////
  //  EVENTS
  ////////////////////////////////////////////////////////////////////////////////

  // Auction Events
  event AuctionStarted(uint256 startTime, uint256 endTime);
  event NewBid(address indexed from, uint256 price);
  event UpdatedAuctionEnd(uint256 endTime);
  event AuctionClosed(address indexed winner, uint256 price);

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
  error InvalidAddress(address invalidAddress);
  error AlreadyHolder();
  error NotHolder();
  error ContractHoldsOrb();
  error ContractDoesNotHoldOrb();

  // Funds-Related Authorization Errors
  error HolderSolvent();
  error HolderInsolvent();
  error NoFunds();
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
  error FlaggingPeriodExpired(uint256 triggerId, uint256 timeSinceResponse, uint256 flaggingPeriodDuration);
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

  // STATE

  // Funds tracker, per address. Modified by deposits, withdrawals and settlements.
  mapping(address => uint256) private _funds;

  // Price of the Orb. No need for mapping, as only one token is very minted.
  uint256 public price;
  // Last time orb holder's funds were settled. Shouldn't be useful is orb is held by the contract.
  uint256 private _lastSettlementTime;

  // Auction State Variables
  // Start Time: when the auction was started. Stays fixed during the auction, otherwise 0.
  uint256 public startTime;
  // End Time: when the auction ends, can be extended by late bids. 0 not during the auction.
  uint256 public endTime;
  // Winning Bidder: address that currently has the highest bid. 0 not during the auction and before first bid.
  address public winningBidder;
  // Winning Bid: highest current bid. 0 not during the auction and before first bid.
  // Note: user has to deposit more than just the bid to ensure solvency after auction is closed.
  uint256 public winningBid;

  // Trigger and Response State Variables

  // Struct used to track both triggger and response base information: content hash and timestamp.
  struct HashTime {
    // keccak256 hash of the cleartext
    bytes32 contentHash;
    uint256 timestamp;
  }

  // Last Trigger Time: when the orb was last triggered. Used together with Cooldown constant.
  uint256 public lastTriggerTime;
  // Mapping for Triggers (Orb Invocations): triggerId to HashTime struct.
  mapping(uint256 => HashTime) public triggers;
  // Additional mapping for Trigger Cleartexts. Providing cleartexts is optional.
  mapping(uint256 => string) public triggersCleartext;
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
   *       Should only be used in conjuction with {onlyHolderHeld}, otherwise does not make sense.
   */
  modifier onlyHolder() {
    if (_msgSender() != ERC721.ownerOf(ERIC_ORB_ID)) {
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
   *       Can be multiple states: auction not started, auction over but not closed, or auction closed.
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
    if (_msgSender() == winningBidder) {
      revert NotPermittedForWinningBidder();
    }
    _;
  }

  // FUNDS-RELATED MODIFIERS

  /**
   * @dev  Ensures that the caller has funds on the contract. Prevents zero-value withdrawals.
   */
  modifier hasFunds() {
    if (_funds[_msgSender()] == 0) {
      revert NoFunds();
    }
    _;
  }

  /**
   * @dev  Ensures that the current orb holder has enough funds to cover Harberger tax until now.
   */
  modifier onlyHolderSolvent() {
    if (!_holderSolvent()) {
      revert HolderInsolvent();
    }
    _;
  }

  /**
   * @dev  Ensures that the current orb holder has run out of funds to cover Harberger tax.
   */
  modifier onlyHolderInsolvent() {
    if (_holderSolvent()) {
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
    if (_msgSender() == ERC721.ownerOf(ERIC_ORB_ID)) {
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
  function minimumBid() public view onlyDuringAuction returns (uint256) {
    if (winningBid == 0) {
      return STARTING_PRICE;
    } else {
      return winningBid + MINIMUM_BID_STEP;
    }
  }

  /**
   * @notice  Total funds (funds on contract + sent value) required to fund a bid of a given value.
   *          Returns the bid amount + enough to cover the Harberger tax for one Harberger tax period.
   * @dev     Can be used together with {minimumBid()} and {fundsOf{}} to figure out msg.value required for bid().
   * @param   amount  Bid amount to calculate for.
   * @return  uint256  Total funds required to satisfy the bid of `amount`.
   */
  function fundsRequiredToBid(uint256 amount) public pure returns (uint256) {
    // Minimum deposit is 1 Holder Tax Period, currently 1 year.
    uint256 requiredDeposit = (amount * HOLDER_TAX_NUMERATOR) / FEE_DENOMINATOR;
    return amount + requiredDeposit;
  }

  /**
   * @notice  Allow the Orb issuer to start the Orb Auction. Will run for at lest MINIMUM_AUCTION_DURATION.
   * @dev     Prevents repeated starts by checking the endTime. Important to set endTime to 0 after auction is closed.
   *          Also, resets winningBidder and winningBid. Should not be necessary, as {closeAuction()} also does that.
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
    uint256 currentFunds = _funds[_msgSender()];
    uint256 totalFunds = currentFunds + msg.value;

    if (amount < minimumBid()) {
      revert InsufficientBid(amount, minimumBid());
    }

    if (totalFunds < fundsRequiredToBid(amount)) {
      revert InsufficientFunds(totalFunds, fundsRequiredToBid(amount));
    }

    _funds[_msgSender()] = totalFunds;
    winningBidder = _msgSender();
    winningBid = amount;

    emit NewBid(_msgSender(), amount);

    if (block.timestamp + BID_AUCTION_EXTENSION > endTime) {
      endTime = block.timestamp + BID_AUCTION_EXTENSION;
      emit UpdatedAuctionEnd(endTime);
    }
  }

  /**
   * @notice  Closes the Auction, transferring the winning bid to the issuer, and the orb to the winner.
   *          The Orb can be triggered immediately.
   *          If no bids were made, resets the state to allow the auction to be started again later.
   * @dev     Critical state transition function. Called after endTime, but only if it's not 0.
   *          Can be called by anyone, although probably will be called by the issuer or the winner.
   *          Emits NewPrice() and AuctionClosed().
   */
  function closeAuction() external notDuringAuction onlyContractHeld {
    if (endTime == 0) {
      revert AuctionNotStarted();
    }

    if (winningBidder != address(0)) {
      _setPrice(winningBid);
      _funds[winningBidder] -= price;
      _funds[owner()] += price;

      _transfer(address(this), winningBidder, ERIC_ORB_ID);

      _lastSettlementTime = block.timestamp;
      // Allow triggering immediately after closing the auction.
      lastTriggerTime = block.timestamp - COOLDOWN;

      emit AuctionClosed(winningBidder, winningBid);

      winningBidder = address(0);
      winningBid = 0;
    } else {
      emit AuctionClosed(winningBidder, winningBid);
    }

    startTime = 0;
    endTime = 0;
  }

  ////////////////////////////////////////////////////////////////////////////////
  //  FUNCTIONS: FUNDS AND HOLDING
  ////////////////////////////////////////////////////////////////////////////////

  /**
   * @notice  Returns funds deposited on the contract by the given address.
   * @param   user  Address to return funds for.
   * @return  uint256  Address funds.
   */
  function fundsOf(address user) external view returns (uint256) {
    if (user == address(0)) {
      revert InvalidAddress(address(0));
    }

    return _funds[user];
  }

  /**
   * @notice  Returns if the current orb holder has enough funds to cover Harberger tax until now.
   * @return  bool  If the current holder is solvent.
   */
  function holderSolvent() external view onlyHolderHeld returns (bool) {
    return _holderSolvent();
  }

  /**
   * @notice  Allows depositing funds on the contract. Not allowed for insolvent holders.
   * @dev     Deposits are not allowed for insolvent holders to prevent cheating via front-running.
   *          If the user becomes insolvent, the orb will always be returned to the contract as the next step.
   *          Emits Deposit().
   */
  function deposit() external payable {
    if (_msgSender() == ERC721.ownerOf(ERIC_ORB_ID) && !_holderSolvent()) {
      revert HolderInsolvent();
    }

    _funds[_msgSender()] += msg.value;
    emit Deposit(_msgSender(), msg.value);
  }

  /**
   * @notice  Function to withdraw all funds on the contract.
   *          Not recommended for current orb holders, they should call exit() to take out their funds.
   * @dev     Not allowed for the winning auction bidder.
   */
  function withdrawAll() external notWinningBidder settlesIfHolder hasFunds {
    _withdraw(_funds[_msgSender()]);
  }

  /**
   * @notice  Function to withdraw given amount from the contract.
   *          For current orb holders, reduces the time until foreclosure.
   * @dev     Not allowed for the winning auction bidder.
   */
  function withdraw(uint256 amount) external notWinningBidder settlesIfHolder hasFunds {
    _withdraw(amount);
  }

  /**
   * @notice  .
   * @dev     .
   */
  function settle() external onlyHolderHeld {
    _settle();
  }

  function _holderSolvent() internal view returns (bool) {
    address holder = ERC721.ownerOf(ERIC_ORB_ID);
    if (owner() == holder) {
      return true;
    }
    return _funds[holder] > _owedSinceLastSettlement();
  }

  function _owedSinceLastSettlement() internal view returns (uint256) {
    uint256 secondsSinceLastSettlement = block.timestamp - _lastSettlementTime;
    return (price * HOLDER_TAX_NUMERATOR * secondsSinceLastSettlement) / (HOLDER_TAX_PERIOD * FEE_DENOMINATOR);
  }

  function _withdraw(uint256 amount_) internal {
    if (_funds[_msgSender()] < amount_) {
      revert InsufficientFunds(_funds[_msgSender()], amount_);
    }

    _funds[_msgSender()] -= amount_;

    emit Withdrawal(_msgSender(), amount_);

    Address.sendValue(payable(_msgSender()), amount_);
  }

  function _settle() internal {
    address holder = ERC721.ownerOf(ERIC_ORB_ID);

    // Owner doesn't need to pay themselves
    if (owner() == holder) {
      return;
    }

    // Should never be reached if contract holds the orb.
    assert(address(this) != holder);

    uint256 availableFunds = _funds[holder];
    uint256 owedFunds = _owedSinceLastSettlement();
    uint256 transferableToOwner = availableFunds <= owedFunds ? availableFunds : owedFunds;

    _funds[holder] -= transferableToOwner;
    _funds[owner()] += transferableToOwner;

    _lastSettlementTime = block.timestamp;

    emit Settlement(holder, owner(), transferableToOwner);
  }

  ////////////////////////////////////////////////////////////////////////////////
  //  FUNCTIONS: PURCHASING
  ////////////////////////////////////////////////////////////////////////////////

  function setPrice(uint256 newPrice) external onlyHolder onlyHolderHeld onlyHolderSolvent settles {
    _setPrice(newPrice);
  }

  function purchase(uint256 currentPrice, uint256 newPrice) external payable onlyHolderHeld onlyHolderSolvent settles {
    // require current price to prevent front-running
    if (currentPrice != price) {
      revert CurrentPriceIncorrect(currentPrice, price);
    }

    // just to prevent errors, price can be set to 0 later
    if (newPrice == 0) {
      revert InvalidNewPrice(newPrice);
    }

    address holder = ERC721.ownerOf(ERIC_ORB_ID);

    if (_msgSender() == holder) {
      revert AlreadyHolder();
    }

    _funds[_msgSender()] += msg.value;
    uint256 totalFunds = _funds[_msgSender()];

    // requires more than price -- not specified how much more, expects UI to handle
    // handle overflow?
    if (totalFunds <= price) {
      revert InsufficientFunds(totalFunds, price + 1);
    }

    uint256 ownerRoyalties = (price * SALE_ROYALTIES_NUMERATOR) / FEE_DENOMINATOR;
    uint256 currentOwnerShare = price - ownerRoyalties;

    _funds[_msgSender()] -= price;
    _funds[owner()] += ownerRoyalties;
    _funds[holder] += currentOwnerShare;

    _transfer(holder, _msgSender(), ERIC_ORB_ID);
    _lastSettlementTime = block.timestamp;

    _setPrice(newPrice);

    emit Purchase(holder, _msgSender());
  }

  function _setPrice(uint256 newPrice_) internal {
    uint256 oldPrice = price;
    price = newPrice_;

    emit NewPrice(oldPrice, newPrice_);
  }

  ////////////////////////////////////////////////////////////////////////////////
  //  FUNCTIONS: FORECLOSURE
  ////////////////////////////////////////////////////////////////////////////////

  function foreclosureTime() external view onlyHolderHeld returns (uint256) {
    return _foreclosureTime();
  }

  function exit() external onlyHolder onlyHolderHeld onlyHolderSolvent settles {
    _transfer(_msgSender(), address(this), ERIC_ORB_ID);
    price = 0;

    emit Foreclosure(_msgSender());

    _withdraw(_funds[_msgSender()]);
  }

  function foreclose() external onlyHolderHeld onlyHolderInsolvent settles {
    address holder = ERC721.ownerOf(ERIC_ORB_ID);
    _transfer(holder, address(this), ERIC_ORB_ID);
    price = 0;

    emit Foreclosure(holder);
  }

  function _foreclosureTime() internal view returns (uint256) {
    address holder = ERC721.ownerOf(ERIC_ORB_ID);
    if (owner() == holder) {
      return INFINITY;
    }

    if (price == 0) {
      return INFINITY;
      // avoid division by zero
    }

    uint256 remainingSeconds = (_funds[holder] * HOLDER_TAX_PERIOD * FEE_DENOMINATOR) / (price * HOLDER_TAX_NUMERATOR);
    return _lastSettlementTime + remainingSeconds;
  }

  ////////////////////////////////////////////////////////////////////////////////
  //  FUNCTIONS: TRIGGERING AND RESPONDING
  ////////////////////////////////////////////////////////////////////////////////

  function cooldownRemaining() external view onlyHolderHeld onlyHolderSolvent returns (uint256) {
    uint256 cooldownExpires = lastTriggerTime + COOLDOWN;
    if (block.timestamp >= cooldownExpires) {
      return 0;
    } else {
      return cooldownExpires - block.timestamp;
    }
  }

  function trigger(bytes32 contentHash, string memory cleartext) external onlyHolder onlyHolderHeld onlyHolderSolvent {
    if (block.timestamp < lastTriggerTime + COOLDOWN) {
      revert CooldownIncomplete(lastTriggerTime + COOLDOWN - block.timestamp);
    }

    uint256 cleartextLength = bytes(cleartext).length;

    if (cleartextLength > MAX_CLEARTEXT_LENGTH) {
      revert CleartextTooLong(cleartextLength, MAX_CLEARTEXT_LENGTH);
    }

    uint256 triggerId = triggersCount;

    if (cleartextLength > 0) {
      bytes32 cleartextHash = keccak256(abi.encodePacked(cleartext));
      if (contentHash != cleartextHash) {
        revert CleartextHashMismatch(cleartextHash, contentHash);
      }

      triggersCleartext[triggerId] = cleartext;
    }

    triggers[triggerId] = HashTime(contentHash, block.timestamp);
    triggersCount += 1;

    lastTriggerTime = block.timestamp;

    emit Triggered(_msgSender(), triggerId, contentHash, block.timestamp);
  }

  function recordTriggerCleartext(
    uint256 triggerId,
    string memory cleartext
  ) external onlyHolder onlyHolderHeld onlyHolderSolvent {
    uint256 cleartextLength = bytes(cleartext).length;
    // not requiring to be more than 0 -- content hash might be of an empty string
    if (cleartextLength > MAX_CLEARTEXT_LENGTH) {
      revert CleartextTooLong(cleartextLength, MAX_CLEARTEXT_LENGTH);
    }

    bytes32 recordedContentHash = triggers[triggerId].contentHash;
    bytes32 cleartextHash = keccak256(abi.encodePacked(cleartext));

    if (recordedContentHash != cleartextHash) {
      revert CleartextHashMismatch(cleartextHash, recordedContentHash);
    }

    // allows overwriting; assuming no hash collisions, just wastes gas
    triggersCleartext[triggerId] = cleartext;
  }

  function respond(uint256 triggerId, bytes32 contentHash) external onlyOwner {
    if (!_triggerExists(triggerId)) {
      revert TriggerNotFound(triggerId);
    }

    if (_responseExists(triggerId)) {
      revert ResponseExists(triggerId);
    }

    responses[triggerId] = HashTime(contentHash, block.timestamp);

    emit Responded(_msgSender(), triggerId, contentHash, block.timestamp);
  }

  function flagResponse(uint256 triggerId) external onlyHolder onlyHolderHeld onlyHolderSolvent {
    // solvency requirement is a weird one, but keeping it consistent with trigger()
    if (!_responseExists(triggerId)) {
      revert ResponseNotFound(triggerId);
    }

    if (block.timestamp - responses[triggerId].timestamp > RESPONSE_FLAGGING_PERIOD) {
      revert FlaggingPeriodExpired(
        triggerId,
        block.timestamp - responses[triggerId].timestamp,
        RESPONSE_FLAGGING_PERIOD
      );
    }

    if (responseFlagged[triggerId] == true) {
      revert ResponseAlreadyFlagged(triggerId);
    }

    responseFlagged[triggerId] = true;
    flaggedResponsesCount += 1;

    emit ResponseFlagged(_msgSender(), triggerId);
  }

  function _triggerExists(uint256 triggerId_) internal view returns (bool) {
    if (triggers[triggerId_].timestamp != 0) {
      return true;
    }
    return false;
  }

  function _responseExists(uint256 triggerId_) internal view returns (bool) {
    if (responses[triggerId_].timestamp != 0) {
      return true;
    }
    return false;
  }
}
