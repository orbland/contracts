// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract EricOrb is ERC721, Ownable {
  // Orb params

  uint256 public constant COOLDOWN = 7 days;

  // not mapping, just for tokenId 0
  uint256 public price;
  uint256 public lastTriggerTime;

  // On-chain trigger-response tracking

  struct HashTime {
    bytes32 contentHash;
    uint256 timestamp;
  }

  mapping(uint256 => HashTime) public triggers;
  mapping(uint256 => string) public triggersCleartext;
  uint256 public triggersCount = 0;
  mapping(uint256 => HashTime) public responses;
  mapping(uint256 => bool) public responseFlagged;
  uint256 public flaggedResponsesCount = 0;

  // Auction params

  // Auction starts at
  uint256 private constant STARTING_PRICE = 0.1 ether;
  // Each bid has to increase price by at least this much
  uint256 private constant MINIMUM_BID_STEP = 0.01 ether;
  // Auction will run for at least
  uint256 private constant MINIMUM_AUCTION_DURATION = 1 days;
  // If remaining time is less than this, auction will be extend to now + this
  uint256 public constant BID_AUCTION_EXTENSION = 30 minutes;

  uint256 public startTime;
  uint256 public endTime;
  address public winningBidder;
  uint256 public winningBid;

  // System params

  uint256 public constant FEE_DENOMINATOR = 10000; // Basis points
  uint256 public constant HOLDER_TAX_NUMERATOR = 1000; // Harberger tax: 10%...
  uint256 public constant HOLDER_TAX_PERIOD = 365 days; // ...per year
  uint256 public constant SALE_ROYALTIES_NUMERATOR = 1000; // Secondary sale to issuer: 10%

  mapping(address => uint256) private _funds;
  uint256 private _lastSettlementTime; // of the orb holder, shouldn"t be useful is orb is held by contract.

  // Events

  event AuctionStarted(uint256 startTime, uint256 endTime);
  event NewBid(address indexed from, uint256 price);
  event UpdatedAuctionEnd(uint256 endTime);
  event AuctionClosed(address indexed winner, uint256 price);

  event Deposit(address indexed sender, uint256 amount);
  event Withdrawal(address indexed recipient, uint256 amount);
  event Settlement(address indexed from, address indexed to, uint256 amount);

  event NewPrice(uint256 from, uint256 to);
  event Purchase(address indexed from, address indexed to);
  event Foreclosure(address indexed from);

  event Triggered(address indexed from, uint256 indexed triggerId, bytes32 contentHash, uint256 time);
  event Responded(address indexed from, uint256 indexed triggerId, bytes32 contentHash, uint256 time);
  event ResponseFlagged(address indexed from, uint256 indexed responseId);

  constructor() ERC721("EricOrb", "ORB") {
    _safeMint(address(this), 0);
  }

  // ERC-721 compatibility

  function _baseURI() internal pure override returns (string memory) {
    return "https://static.orb.land/eric/";
  }

  // In the future we might allow transfers.
  // It would settle (both accounts in multi-orb) and require the receiver to have deposit.
  function transferFrom(address, address, uint256) public pure override {
    revert("transfering not supported, purchase required");
    // transferFrom(address from, address to, uint256 tokenId) external override onlyOwner onlyOwnerHeld
    // require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
    // _transfer(from, to, tokenId);
  }

  function safeTransferFrom(address, address, uint256) public pure override {
    revert("transfering not supported, purchase required");
    // safeTransferFrom(address from, address to, uint256 tokenId) external override onlyOwner onlyOwnerHeld
    // safeTransferFrom(from, to, tokenId, "");
  }

  function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
    revert("transfering not supported, purchase required");
    // safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
    //   external override onlyOwner onlyOwnerHeld
    // require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
    // _safeTransfer(from, to, tokenId, data);
  }

  // Modifiers

  // inherits onlyOwner

  // modifier notOwner() {
  //   require(owner() != _msgSender(), "caller is the owner");
  //   _;
  // }

  // Should be use in conjuction with onlyHolderHeld to make sure it"s not the contract
  modifier onlyHolder() {
    address holder = ERC721.ownerOf(0);
    require(_msgSender() == holder, "not orb holder");
    _;
  }

  modifier onlyHolderHeld() {
    address holder = ERC721.ownerOf(0);
    require(address(this) != holder, "contract holds the orb");
    _;
  }

  modifier onlyContractHeld() {
    address holder = ERC721.ownerOf(0);
    require(address(this) == holder, "contract does not hold the orb");
    _;
  }

  modifier onlyDuringAuction() {
    require(auctionRunning(), "auction not running");
    _;
  }

  modifier notDuringAuction() {
    require(!auctionRunning(), "auction running");
    _;
  }

  modifier notWinningBidder() {
    require(_msgSender() != winningBidder, "not permitted for winning bidder");
    _;
  }

  modifier onlyHolderInsolvent() {
    require(!_holderSolvent(), "holder solvent");
    _;
  }

  modifier onlyHolderSolvent() {
    require(_holderSolvent(), "holder insolvent");
    _;
  }

  modifier settles() {
    _settle();
    _;
  }

  modifier settlesIfHolder() {
    address holder = ERC721.ownerOf(0);
    if (_msgSender() == holder) {
      _settle();
    }
    _;
  }

  modifier hasFunds() {
    address recipient = _msgSender();
    require(_funds[recipient] > 0, "no funds available");
    _;
  }

  // Auction

  function startAuction() external onlyOwner onlyContractHeld notDuringAuction {
    require(endTime == 0, "auction already started");

    startTime = block.timestamp;
    endTime = block.timestamp + MINIMUM_AUCTION_DURATION;
    winningBidder = address(0);
    winningBid = 0;

    emit AuctionStarted(startTime, endTime);
  }

  function auctionRunning() public view returns (bool) {
    return endTime > block.timestamp && address(this) == ERC721.ownerOf(0);
    // start time will always be less than timestamp, as it resets to 0.
    // start time is only updated for auction progress tracking, not critical functionality.
  }

  // function currentHighestBid() external view returns (uint256) {
  //   if (winningBidder == address(0)) {
  //     return 0;
  //   }
  //   uint256 winningBidderBalance = _funds[winningBidder];
  //   uint256 highestBidDeposit = (winningBidderBalance * holderTaxNumerator) / feeDenominator;
  //   uint256 highestBid = winningBidderBalance - highestBidDeposit;
  //   return highestBid;
  // }

  function minimumBid() public view onlyDuringAuction returns (uint256) {
    if (winningBid == 0) {
      return STARTING_PRICE;
    } else {
      return winningBid + MINIMUM_BID_STEP;
    }
  }

  function fundsRequiredToBid(uint256 amount_) public pure returns (uint256) {
    // minimum deposit is 1 Holder Tax Period, currently 1 year.
    uint256 requiredDeposit = (amount_ * HOLDER_TAX_NUMERATOR) / FEE_DENOMINATOR;
    return amount_ + requiredDeposit;
  }

  function bid(uint256 amount_) external payable onlyDuringAuction {
    uint256 currentFunds = _funds[_msgSender()];
    uint256 totalFunds = currentFunds + msg.value;

    require(amount_ >= minimumBid(), "bid not sufficient");
    require(totalFunds >= fundsRequiredToBid(amount_), "not sufficient funds");

    _funds[_msgSender()] = totalFunds;
    winningBidder = _msgSender();
    winningBid = amount_;

    emit NewBid(_msgSender(), amount_);

    if (block.timestamp + BID_AUCTION_EXTENSION > endTime) {
      endTime = block.timestamp + BID_AUCTION_EXTENSION;
      emit UpdatedAuctionEnd(endTime);
    }
  }

  function closeAuction() external notDuringAuction onlyContractHeld {
    require(endTime > 0, "auction was not started");
    if (winningBidder != address(0)) {
      price = winningBid;
      _funds[winningBidder] -= price;
      _funds[owner()] += price;

      _transfer(address(this), winningBidder, 0);

      _lastSettlementTime = block.timestamp;
      lastTriggerTime = block.timestamp - COOLDOWN; // allow triggering immediately after closing the auction.

      emit AuctionClosed(winningBidder, winningBid);

      winningBidder = address(0);
      winningBid = 0;
    } else {
      emit AuctionClosed(winningBidder, winningBid);
    }

    startTime = 0;
    endTime = 0;
  }

  // Key funds manangement methods

  function fundsOf(address user_) external view returns (uint256) {
    require(user_ != address(0), "address zero is not valid");
    return _funds[user_];
  }

  function deposit() external payable {
    address holder = ERC721.ownerOf(0);
    if (_msgSender() == holder) {
      require(_holderSolvent(), "deposits allowed only during solvency");
    }

    _funds[_msgSender()] += msg.value;
    emit Deposit(_msgSender(), msg.value);
  }

  function withdrawAll() external notWinningBidder settlesIfHolder hasFunds {
    _withdraw(_funds[_msgSender()]);
  }

  function withdraw(uint256 amount_) external notWinningBidder settlesIfHolder hasFunds {
    require(_funds[_msgSender()] >= amount_, "not enough funds");
    _withdraw(amount_);
  }

  function _withdraw(uint256 amount_) internal {
    address recipient = _msgSender();
    _funds[recipient] -= amount_;

    emit Withdrawal(recipient, amount_);

    Address.sendValue(payable(recipient), amount_);
  }

  function settle() external onlyHolderHeld {
    _settle();
  }

  function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a <= b ? a : b;
  }

  function _settle() internal {
    address holder = ERC721.ownerOf(0);

    if (owner() == holder) {
      return;
      // Owner doesn"t need to pay themselves
    }

    assert(address(this) != holder); // should never be reached if contract holds the orb

    uint256 availableFunds = _funds[holder];
    uint256 transferableToOwner = min(availableFunds, _owedSinceLastSettlement());
    _funds[holder] -= transferableToOwner;
    _funds[owner()] += transferableToOwner;

    _lastSettlementTime = block.timestamp;

    emit Settlement(holder, owner(), transferableToOwner);
  }

  // Orb Selling

  function setPrice(uint256 newPrice_) external onlyHolder onlyHolderHeld onlyHolderSolvent settles {
    _setPrice(newPrice_);
  }

  function _setPrice(uint256 newPrice_) internal {
    uint256 oldPrice = price;
    price = newPrice_;
    emit NewPrice(oldPrice, newPrice_);
  }

  // function minimumAcceptedPurchaseAmount() external view returns (uint256) {
  //   uint256 minimumDeposit = (price * holderTaxNumerator) / feeDenominator;
  //   return price + minimumDeposit;
  // }

  function purchase(
    uint256 currentPrice_,
    uint256 newPrice_
  ) external payable onlyHolderHeld onlyHolderSolvent settles {
    // require current price to prevent front-running
    require(currentPrice_ == price, "current price incorrect");

    // just to prevent errors, price can be set to 0 later
    require(newPrice_ > 0, "new price cannot be zero when purchasing");

    address holder = ERC721.ownerOf(0);
    require(_msgSender() != holder, "you already own the orb");

    _funds[_msgSender()] += msg.value;
    uint256 totalFunds = _funds[_msgSender()];

    // requires more than price -- not specified how much more, expects UI to handle
    require(totalFunds > price, "not enough funds");
    // require(totalFunds >= minimumAcceptedPurchaseAmount(), "not enough funds");

    uint256 ownerRoyalties = (price * SALE_ROYALTIES_NUMERATOR) / FEE_DENOMINATOR;
    uint256 currentOwnerShare = price - ownerRoyalties;

    _funds[_msgSender()] -= price;
    _funds[owner()] += ownerRoyalties;
    _funds[holder] += currentOwnerShare;

    _transfer(holder, _msgSender(), 0);
    _lastSettlementTime = block.timestamp;

    _setPrice(newPrice_);

    emit Purchase(holder, _msgSender());
  }

  // Foreclosure

  function exit() external onlyHolder onlyHolderHeld onlyHolderSolvent settles {
    _transfer(_msgSender(), address(this), 0);
    price = 0;

    emit Foreclosure(_msgSender());

    _withdraw(_funds[_msgSender()]);
  }

  function foreclose() external onlyHolderHeld onlyHolderInsolvent settles {
    address holder = ERC721.ownerOf(0);
    _transfer(holder, address(this), 0);
    price = 0;

    emit Foreclosure(holder);
  }

  function foreclosureTime() external view onlyHolderHeld returns (uint256) {
    return _foreclosureTime();
  }

  function holderSolvent() external view onlyHolderHeld returns (bool) {
    return _holderSolvent();
  }

  // Orb Triggering and Responding

  function cooldownRemaining() external view onlyHolderHeld onlyHolderSolvent returns (uint256) {
    uint256 cooldownExpires = lastTriggerTime + COOLDOWN;
    if (block.timestamp >= cooldownExpires) {
      return 0;
    } else {
      return cooldownExpires - block.timestamp;
    }
  }

  function trigger(
    bytes32 contentHash_,
    string memory cleartext_
  ) external onlyHolder onlyHolderHeld onlyHolderSolvent {
    require(block.timestamp >= lastTriggerTime + COOLDOWN, "orb is not ready yet");

    uint256 cleartextLength = bytes(cleartext_).length;
    require(cleartextLength <= 280, "cleartext is too long");

    lastTriggerTime = block.timestamp;
    uint256 triggerId = triggersCount;

    triggers[triggerId] = HashTime(contentHash_, block.timestamp);
    triggersCount += 1;

    if (cleartextLength > 0) {
      bytes32 submittedCleartextHash = keccak256(abi.encodePacked(cleartext_));
      require(contentHash_ == submittedCleartextHash, "cleartext does not match content hash");

      triggersCleartext[triggerId] = cleartext_;
    }

    emit Triggered(_msgSender(), triggerId, contentHash_, block.timestamp);
  }

  function recordTriggerCleartext(
    uint256 triggerId_,
    string memory cleartext_
  ) external onlyHolder onlyHolderHeld onlyHolderSolvent {
    uint256 cleartextLength = bytes(cleartext_).length;
    require(cleartextLength <= 280, "cleartext is too long");
    // not requiring to be more than 0

    bytes32 recordedContentHash = triggers[triggerId_].contentHash;
    bytes32 submittedCleartextHash = keccak256(abi.encodePacked(cleartext_));

    require(recordedContentHash == submittedCleartextHash, "cleartext does not match content hash");

    triggersCleartext[triggerId_] = cleartext_;
    // allows overwriting; assuming now hash collisions, just wastes gas
  }

  function respond(uint256 toTrigger_, bytes32 contentHash_) external onlyOwner {
    require(_triggerExists(toTrigger_), "this orb trigger does not exist");
    require(!_responseExists(toTrigger_), "this orb trigger has already been responded");

    responses[toTrigger_] = HashTime(contentHash_, block.timestamp);

    emit Responded(_msgSender(), toTrigger_, contentHash_, block.timestamp);
  }

  function flagResponse(uint256 responseId_) external onlyHolder onlyHolderHeld onlyHolderSolvent {
    // solvency requirement is a weird one, but keeping it consistent with trigger()
    require(responses[responseId_].timestamp != 0, "response does not exist");
    require(responses[responseId_].timestamp > block.timestamp - 7 days, "response is too old to flag");
    require(responseFlagged[responseId_] == false, "response has already been flagged");

    responseFlagged[responseId_] = true;
    flaggedResponsesCount += 1;

    emit ResponseFlagged(_msgSender(), responseId_);
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

  // Internal calculations

  function _owedSinceLastSettlement() internal view returns (uint256) {
    uint256 secondsSinceLastSettlement = block.timestamp - _lastSettlementTime;
    return (price * HOLDER_TAX_NUMERATOR * secondsSinceLastSettlement) / (HOLDER_TAX_PERIOD * FEE_DENOMINATOR);
  }

  function _holderSolvent() internal view returns (bool) {
    address holder = ERC721.ownerOf(0);
    if (owner() == holder) {
      return true;
    }
    return _funds[holder] > _owedSinceLastSettlement();
  }

  function _foreclosureTime() internal view returns (uint256) {
    address holder = ERC721.ownerOf(0);
    if (owner() == holder) {
      return 0;
    }

    // uint256 costPerPeriod = price * holderTaxNumerator / feeDenominator;
    // uint256 costPerSecond = costPerPeriod / holderTaxPeriod;
    // uint256 remainingSeconds = _funds[holder] / costPerSecond;
    // return _lastSettlementTime + remainingSeconds;

    uint256 remainingSeconds = (_funds[holder] * HOLDER_TAX_PERIOD * FEE_DENOMINATOR) / (price * HOLDER_TAX_NUMERATOR);
    return _lastSettlementTime + remainingSeconds;
  }
}
