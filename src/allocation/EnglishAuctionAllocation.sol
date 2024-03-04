// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AllocationMethod} from "./AllocationMethod.sol";
import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Orbs} from "../Orbs.sol";

contract EnglishAuctionAllocation is AllocationMethod, OwnableUpgradeable, UUPSUpgradeable {
    // Auction Events

    event AuctionBid(address indexed bidder, uint256 indexed bid);
    event AuctionExtension(uint256 indexed newAuctionEndTime);
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

    error NotPermittedForLeadingBidder();
    error InsufficientBid(uint256 bidProvided, uint256 bidRequired);
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);
    error InvalidAuctionDuration(uint256 auctionDuration);

    // Auction State Variables

    /// Auction starting price. Initial value is 0 - allows any bid.
    mapping(uint256 ordId => uint256) public auctionStartingPrice;
    /// Auction minimum bid step: required increase between bids. Each bid has to increase over previous bid by at
    /// least this much. If trying to set as zero, will be set to 1 (wei). Initial value is also 1 wei, to disallow
    /// equal value bids.
    mapping(uint256 ordId => uint256) public auctionNextBidIncrease;
    /// Auction minimum duration: the auction will run for at least this long. Initial value is 1 day, and this value
    /// cannot be set to zero, as it would prevent any bids from being made.
    mapping(uint256 ordId => uint256) public auctionMinimumDuration;
    /// Keeper's Auction minimum duration: auction started by the keeper via `relinquish(true)` will run for at least
    /// this long. Initial value is 1 day, and this value cannot be set to zero, as it would prevent any bids from being
    /// made.
    mapping(uint256 ordId => uint256) public auctionKeeperMinimumDuration;
    /// Auction bid extension: if auction remaining time is less than this after a bid is made, auction will continue
    /// for at least this long. Can be set to zero, in which case the auction will always be `auctionMinimumDuration`
    /// long. Initial value is 5 minutes.
    mapping(uint256 ordId => uint256) public auctionBidExtension;
    /// Auction end time: timestamp when the auction ends, can be extended by late bids. 0 not during the auction.
    mapping(uint256 ordId => uint256) public auctionEndTime;
    /// Leading bidder: address that currently has the highest bid. 0 not during the auction and before first bid.
    mapping(uint256 ordId => address) public leadingBidder;
    /// Leading bid: highest current bid. 0 not during the auction and before first bid.
    mapping(uint256 ordId => uint256) public leadingBid;

    mapping(uint256 orbId => mapping(address user => uint256)) public fundsOf;
    mapping(uint256 orbId => uint256) public initialPrice;

    function initializeOrb(uint256 orbId) public override {
        auctionStartingPrice[orbId] = 0.05 ether;
        auctionNextBidIncrease[orbId] = 0.05 ether;
        auctionMinimumDuration[orbId] = 1 days;
        auctionKeeperMinimumDuration[orbId] = 1 days;
        auctionBidExtension[orbId] = 4 minutes;
    }

    function allocationActive(uint256 orbId) public view virtual returns (bool) {
        // TODO
        return true;
    }

    /// @notice  Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.
    /// @dev     Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
    ///          after auction is finalized. Emits `AuctionStart`.
    ///          V2 adds `onlyHonored` modifier to require active Oath to start auction.
    function startAllocation(uint256 orbId, bool reallocation)
        external
        virtual
        override
        onlyOrbsContract
        notDuringAllocation(orbId)
    {
        if (address(this) != Orbs(orbsContract).keeper(orbId)) {
            revert ContractDoesNotHoldOrb();
        }

        // if (auctionEndTime > 0) {
        //     revert AuctionRunning();
        // }

        auctionEndTime[orbId] = block.timestamp + auctionMinimumDuration[orbId];

        emit AuctionStart(block.timestamp, auctionEndTime[orbId], address(0)); // TODO
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
    function finalizeAllocation(uint256 orbId) external virtual override notDuringAllocation(orbId) {
        if (auctionEndTime[orbId] == 0) {
            revert AllocationNotStarted();
        }

        address _leadingBidder = leadingBidder[orbId];
        uint256 _leadingBid = leadingBid[orbId];

        Orbs(orbsContract).finalizeAllocation(
            orbId, _leadingBid, 0, _leadingBidder, fundsOf[orbId][_leadingBidder], initialPrice[orbId]
        ); // TODO add duration

        emit AuctionFinalization(address(0), 0);
        leadingBidder[orbId] = address(0);
        leadingBid[orbId] = 0;
        auctionEndTime[orbId] = 0;
    }

    /// @notice  Allows the Orb creator to set the auction parameters. This function can only be called by the Orb
    ///          creator when the Orb is in their control.
    /// @dev     Emits `AuctionParametersUpdate`.
    /// @param   orbId                     ID of the Orb to set the auction parameters for.
    /// @param   newStartingPrice          New starting price for the auction. Can be 0.
    /// @param   newNextBidIncrease        New minimum bid step for the auction. Will always be set to at least 1.
    /// @param   newMinimumDuration        New minimum duration for the auction. Must be > 0.
    /// @param   newKeeperMinimumDuration  New minimum duration for the auction is started by the keeper via
    ///                                    `relinquish(true)`. Setting to 0 effectively disables keeper auctions.
    /// @param   newBidExtension           New bid extension for the auction. Can be 0.
    function setAuctionParameters(
        uint256 orbId,
        uint256 newStartingPrice,
        uint256 newNextBidIncrease,
        uint256 newMinimumDuration,
        uint256 newKeeperMinimumDuration,
        uint256 newBidExtension
    ) external virtual onlyCreator(orbId) onlyCreatorControlled(orbId) {
        if (newMinimumDuration == 0) {
            revert InvalidAuctionDuration(newMinimumDuration);
        }

        uint256 previousStartingPrice = auctionStartingPrice[orbId];
        auctionStartingPrice[orbId] = newStartingPrice;

        uint256 previousNextBidIncrease = auctionNextBidIncrease[orbId];
        auctionNextBidIncrease[orbId] = newNextBidIncrease > 0 ? newNextBidIncrease : 1;

        uint256 previousMinimumDuration = auctionMinimumDuration[orbId];
        auctionMinimumDuration[orbId] = newMinimumDuration;

        uint256 previousKeeperMinimumDuration = auctionKeeperMinimumDuration[orbId];
        auctionKeeperMinimumDuration[orbId] = newKeeperMinimumDuration;

        uint256 previousBidExtension = auctionBidExtension[orbId];
        auctionBidExtension[orbId] = newBidExtension;

        emit AuctionParametersUpdate(
            previousStartingPrice,
            newStartingPrice,
            previousNextBidIncrease,
            newNextBidIncrease,
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
    function _minimumBid(uint256 orbId) internal view virtual returns (uint256 auctionMinimumBid) {
        if (leadingBid[orbId] == 0) {
            return auctionStartingPrice[orbId];
        } else {
            unchecked {
                return leadingBid[orbId] + auctionNextBidIncrease[orbId];
            }
        }
    }

    /// @notice  Bids the provided amount, if there's enough funds across funds on contract and transaction value.
    ///          Might extend the auction if bidding close to auction end. Important: the leading bidder will not be
    ///          able to withdraw any funds until someone outbids them or the auction is finalized.
    /// @dev     Emits `AuctionBid`.
    /// @param   amount      The value to bid.
    /// @param   priceIfWon  Price if the bid wins. Must be less than `MAXIMUM_PRICE`.
    function bid(uint256 orbId, uint256 amount, uint256 priceIfWon) external payable virtual {
        if (!allocationActive(orbId)) {
            revert AllocationNotAcitve();
        }

        uint256 totalFunds = fundsOf[orbId][msg.sender] + msg.value;

        if (amount < _minimumBid(orbId)) {
            revert InsufficientBid(amount, _minimumBid(orbId));
        }

        if (totalFunds < amount) {
            revert InsufficientFunds(totalFunds, amount);
        }

        if (priceIfWon > _MAXIMUM_PRICE) {
            revert InvalidPrice(priceIfWon);
        }

        fundsOf[orbId][msg.sender] = totalFunds;
        leadingBidder[orbId] = msg.sender;
        leadingBid[orbId] = amount;
        initialPrice[orbId] = priceIfWon;

        emit AuctionBid(msg.sender, amount);

        if (block.timestamp + auctionBidExtension[orbId] > auctionEndTime[orbId]) {
            auctionEndTime[orbId] = block.timestamp + auctionBidExtension[orbId];
            emit AuctionExtension(auctionEndTime[orbId]);
        }
    }

    /// @dev  Authorizes owner address to upgrade the contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
