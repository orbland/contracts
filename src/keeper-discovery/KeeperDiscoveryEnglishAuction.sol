// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

contract KeeperDiscoveryEnglishAuction is OwnableUpgradeable, UUPSUpgradeable {
    // Auction Events
    event AuctionStart(
        uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
    );
    event AuctionBid(address indexed bidder, uint256 indexed bid);
    event AuctionExtension(uint256 indexed newAuctionEndTime);
    event AuctionFinalization(address indexed winner, uint256 indexed winningBid);
    event AuctionParametersUpdate(
        uint256 previousStartingPrice,
        uint256 indexed newStartingPrice,
        uint256 previousMinimumBidStep,
        uint256 indexed newMinimumBidStep,
        uint256 previousMinimumDuration,
        uint256 indexed newMinimumDuration,
        uint256 previousKeeperMinimumDuration,
        uint256 newKeeperMinimumDuration,
        uint256 previousBidExtension,
        uint256 newBidExtension
    );

    error InvalidNewPrice(uint256 priceProvided);
    error NotPermittedForLeadingBidder();
    error InsufficientBid(uint256 bidProvided, uint256 bidRequired);
    error InvalidAuctionDuration(uint256 auctionDuration);

    // Auction State Variables

    /// Auction starting price. Initial value is 0 - allows any bid.
    uint256 public auctionStartingPrice;
    /// Auction minimum bid step: required increase between bids. Each bid has to increase over previous bid by at
    /// least this much. If trying to set as zero, will be set to 1 (wei). Initial value is also 1 wei, to disallow
    /// equal value bids.
    uint256 public auctionNextBidIncrease;
    /// Auction minimum duration: the auction will run for at least this long. Initial value is 1 day, and this value
    /// cannot be set to zero, as it would prevent any bids from being made.
    uint256 public auctionMinimumDuration;
    /// Keeper's Auction minimum duration: auction started by the keeper via `relinquish(true)` will run for at least
    /// this long. Initial value is 1 day, and this value cannot be set to zero, as it would prevent any bids from being
    /// made.
    uint256 public auctionKeeperMinimumDuration;
    /// Auction bid extension: if auction remaining time is less than this after a bid is made, auction will continue
    /// for at least this long. Can be set to zero, in which case the auction will always be `auctionMinimumDuration`
    /// long. Initial value is 5 minutes.
    uint256 public auctionBidExtension;
    /// Auction end time: timestamp when the auction ends, can be extended by late bids. 0 not during the auction.
    uint256 public auctionEndTime;
    /// Leading bidder: address that currently has the highest bid. 0 not during the auction and before first bid.
    address public leadingBidder;
    /// Leading bid: highest current bid. 0 not during the auction and before first bid.
    uint256 public leadingBid;

    modifier notDuringAuction() {
        if (_auctionRunning()) {
            revert AuctionRunning();
        }
        _;
    }

    modifier onlyHonored() {
        if (address(this) != keeper) {
            revert ContractDoesNotHoldOrb();
        }
        _;
    }

    modifier onlyCreatorControlled() {
        if (address(this) != keeper) {
            revert ContractDoesNotHoldOrb();
        }
        _;
    }

    function initialize() public initializer {
        auctionStartingPrice = 0.05 ether;
        auctionMinimumBidStep = 0.05 ether;
        auctionMinimumDuration = 1 days;
        auctionKeeperMinimumDuration = 1 days;
        auctionBidExtension = 4 minutes;
    }

    /// @notice  Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.
    /// @dev     Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
    ///          after auction is finalized. Emits `AuctionStart`.
    ///          V2 adds `onlyHonored` modifier to require active Oath to start auction.
    function startDiscovery() external virtual override onlyOwner notDuringAuction onlyHonored {
        if (address(this) != keeper) {
            revert ContractDoesNotHoldOrb();
        }

        if (auctionEndTime > 0) {
            revert AuctionRunning();
        }

        auctionEndTime = block.timestamp + auctionMinimumDuration;
        auctionBeneficiary = beneficiary;

        emit AuctionStart(block.timestamp, auctionEndTime, auctionBeneficiary);
    }

    /// @notice  Finalizes the auction, transferring the winning bid to the beneficiary, and the Orb to the winner.
    ///          If the auction was started by previous Keeper with `relinquish(true)`, then most of the auction
    ///          proceeds (minus the royalty) will be sent to the previous Keeper. Sets `lastInvocationTime` so that
    ///          the Orb could be invoked immediately. The price has been set when bidding, now becomes relevant. If no
    ///          bids were made, resets the state to allow the auction to be started again later.
    /// @dev     Critical state transition function. Called after `auctionEndTime`, but only if it's not 0. Can be
    ///          called by anyone, although probably will be called by the creator or the winner. Emits `PriceUpdate`
    ///          and `AuctionFinalization`.
    ///          V2 fixes a bug with Keeper auctions changing lastInvocationTime, and uses `auctionRoyaltyNumerator`
    ///          instead of `purchaseRoyaltyNumerator` for auction royalty (only relevant for Keeper auctions).
    function finalizeDiscovery() external virtual override notDuringAuction {
        if (auctionEndTime == 0) {
            revert AuctionNotStarted();
        }

        address _leadingBidder = leadingBidder;
        uint256 _leadingBid = leadingBid;

        if (_leadingBidder != address(0)) {
            fundsOf[_leadingBidder] -= _leadingBid;

            uint256 auctionMinimumRoyaltyNumerator =
                (keeperTaxNumerator * auctionKeeperMinimumDuration) / _KEEPER_TAX_PERIOD;
            uint256 auctionRoyalty = auctionMinimumRoyaltyNumerator > auctionRoyaltyNumerator
                ? auctionMinimumRoyaltyNumerator
                : auctionRoyaltyNumerator;
            _splitProceeds(_leadingBid, auctionBeneficiary, auctionRoyalty);

            lastSettlementTime = block.timestamp;
            if (auctionBeneficiary == beneficiary) {
                lastInvocationTime = block.timestamp - cooldown;
            }

            emit AuctionFinalization(_leadingBidder, _leadingBid);
            emit PriceUpdate(0, price);
            // price has been set when bidding
            // also price is always 0 when auction starts

            _transferOrb(address(this), _leadingBidder);
            leadingBidder = address(0);
            leadingBid = 0;
        } else {
            emit AuctionFinalization(address(0), 0);
        }

        auctionEndTime = 0;
    }

    /// @notice  Allows the Orb creator to set the auction parameters. This function can only be called by the Orb
    ///          creator when the Orb is in their control.
    /// @dev     Emits `AuctionParametersUpdate`.
    /// @param   newStartingPrice          New starting price for the auction. Can be 0.
    /// @param   newMinimumBidStep         New minimum bid step for the auction. Will always be set to at least 1.
    /// @param   newMinimumDuration        New minimum duration for the auction. Must be > 0.
    /// @param   newKeeperMinimumDuration  New minimum duration for the auction is started by the keeper via
    ///                                    `relinquish(true)`. Setting to 0 effectively disables keeper auctions.
    /// @param   newBidExtension           New bid extension for the auction. Can be 0.
    function setAuctionParameters(
        uint256 newStartingPrice,
        uint256 newMinimumBidStep,
        uint256 newMinimumDuration,
        uint256 newKeeperMinimumDuration,
        uint256 newBidExtension
    ) external virtual onlyOwner onlyCreatorControlled {
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

    /// @dev     Minimum bid that would currently be accepted by `bid()`. `auctionStartingPrice` if no bids were made,
    ///          otherwise the leading bid increased by `auctionMinimumBidStep`.
    /// @return  auctionMinimumBid  Minimum bid required for `bid()`.
    function _minimumBid() internal view virtual returns (uint256 auctionMinimumBid) {
        if (leadingBid == 0) {
            return auctionStartingPrice;
        } else {
            unchecked {
                return leadingBid + auctionMinimumBidStep;
            }
        }
    }

    /// @notice  Bids the provided amount, if there's enough funds across funds on contract and transaction value.
    ///          Might extend the auction if bidding close to auction end. Important: the leading bidder will not be
    ///          able to withdraw any funds until someone outbids them or the auction is finalized.
    /// @dev     Emits `AuctionBid`.
    /// @param   amount      The value to bid.
    /// @param   priceIfWon  Price if the bid wins. Must be less than `MAXIMUM_PRICE`.
    function bid(uint256 amount, uint256 priceIfWon) external payable virtual {
        if (!_auctionRunning()) {
            revert AuctionNotRunning();
        }

        if (msg.sender == beneficiary) {
            revert NotPermitted();
        }

        uint256 totalFunds = fundsOf[msg.sender] + msg.value;

        if (amount < _minimumBid()) {
            revert InsufficientBid(amount, _minimumBid());
        }

        if (totalFunds < amount) {
            revert InsufficientFunds(totalFunds, amount);
        }

        if (priceIfWon > _MAXIMUM_PRICE) {
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
}
