// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {DelegationMethod} from "./DelegationMethod.sol";
import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Address} from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";

contract EnglishAuctionDelegation is DelegationMethod, OwnableUpgradeable, UUPSUpgradeable {
    // Auction Events

    event AuctionBid(uint256 indexed orbId, address indexed bidder, uint256 indexed bid);
    event AuctionExtension(uint256 indexed orbId, uint256 indexed auctionEndTime);
    event EnglishAuctionParametersUpdate(
        uint256 indexed orbId,
        uint256 indexed startingPrice,
        uint256 minimumBidStep,
        uint256 indexed minimumDuration,
        uint256 bidExtension
    );

    error NotPermittedForLeadingBidder();
    error InsufficientBid(uint256 bidProvided, uint256 bidRequired);
    error InsufficientFunds(uint256 fundsAvailable, uint256 fundsRequired);
    error InvalidAuctionDuration(uint256 auctionDuration);

    /// Version. Value: 1.
    uint256 private constant _VERSION = 1;

    // Auction State Variables

    /// Auction starting price. Initial value is 0 - allows any bid.
    mapping(uint256 orbId => uint256) public startingPrice;
    /// Auction minimum bid step: required increase between bids. Each bid has to increase over previous bid by at
    /// least this much. If trying to set as zero, will be set to 1 (wei). Initial value is also 1 wei, to disallow
    /// equal value bids.
    mapping(uint256 orbId => uint256) public nextBidIncrease;
    /// Auction minimum duration: the auction will run for at least this long. Initial value is 1 day, and this value
    /// cannot be set to zero, as it would prevent any bids from being made.
    mapping(uint256 orbId => uint256) public minimumDuration;
    /// Auction bid extension: if auction remaining time is less than this after a bid is made, auction will continue
    /// for at least this long. Can be set to zero, in which case the auction will always be `auctionMinimumDuration`
    /// long. Initial value is 5 minutes.
    mapping(uint256 orbId => uint256) public bidExtension;
    /// Auction start time
    mapping(uint256 orbId => uint256) public startTime;
    /// Auction end time: timestamp when the auction ends, can be extended by late bids. 0 not during the auction.
    mapping(uint256 orbId => uint256) public endTime;
    /// Leading bidder: address that currently has the highest bid. 0 not during the auction and before first bid.
    mapping(uint256 orbId => address) public leadingBidder;
    /// Leading bid: highest current bid. 0 not during the auction and before first bid.
    mapping(uint256 orbId => uint256) public leadingBid;

    mapping(uint256 orbId => mapping(address user => uint256)) public fundsOf;

    function initializeOrb(uint256 orbId) public override onlyInvocationRegistry {
        if (minimumDuration[orbId] > 0) {
            return;
        }

        startingPrice[orbId] = 0.01 ether;
        nextBidIncrease[orbId] = 0.01 ether;
        minimumDuration[orbId] = 1 days;
        bidExtension[orbId] = 4 minutes;
    }

    function isActive(uint256 orbId) public view virtual override returns (bool) {
        return endTime[orbId] > 0;
    }

    function isCancelable(uint256 orbId) public view virtual override returns (bool) {
        return leadingBidder[orbId] == address(0);
    }

    function isFinalizable(uint256 orbId) public view virtual override returns (bool) {
        return endTime[orbId] > 0 && endTime[orbId] < block.timestamp;
    }

    /// @notice  Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.
    /// @dev     Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
    ///          after auction is finalized. Emits `AuctionStart`.
    ///          V2 adds `onlyHonored` modifier to require active Oath to start auction.
    function start(uint256 orbId) public virtual override onlyKeeper(orbId) onlyInactive(orbId) {
        if (endTime[orbId] > 0) {
            revert DelegationActive();
        }

        super.start(orbId);

        startTime[orbId] = block.timestamp;
        endTime[orbId] = block.timestamp + minimumDuration[orbId];
        delegationExpiration[orbId] = block.timestamp + _expirationDuration(orbId);

        emit DelegationStart(orbId, block.timestamp, endTime[orbId]);
    }

    function _reset(uint256 orbId) internal virtual {
        startTime[orbId] = 0;
        endTime[orbId] = 0;

        leadingBidder[orbId] = address(0);
        leadingBid[orbId] = 0;

        delegationHash[orbId] = 0;
        delegationExpiration[orbId] = 0;
    }

    function cancel(uint256 orbId) external virtual onlyKeeper(orbId) onlyActive(orbId) {
        if (endTime[orbId] == 0) {
            revert DelegationNotActive();
        }
        if (leadingBidder[orbId] != address(0)) {
            revert NotCancelable();
        }

        emit DelegationCancellation(orbId);
        _reset(orbId);
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
    function finalize(uint256 orbId) external virtual onlyFinalizable(orbId) {
        address _leadingBidder = leadingBidder[orbId];
        uint256 _leadingBid = leadingBid[orbId];

        fundsOf[orbId][_leadingBidder] -= _leadingBid;
        _addEarnings(os.ownership().keeper(orbId), _leadingBid);

        os.invocations().invokeDelegated(orbId, _leadingBidder, delegationHash[orbId]);

        emit DelegationFinalization(orbId, _leadingBidder, _leadingBid);
        _reset(orbId);
    }

    /// @notice  Allows the Orb creator to set the auction parameters. This function can only be called by the Orb
    ///          creator when the Orb is in their control.
    /// @dev     Emits `AuctionParametersUpdate`.
    /// @param   orbId                   ID of the Orb to set the auction parameters for.
    /// @param   startingPrice_          New starting price for the auction. Can be 0.
    /// @param   nextBidIncrease_        New minimum bid step for the auction. Will always be set to at least 1.
    /// @param   minimumDuration_        New minimum duration for the auction. Must be > 0.
    /// @param   bidExtension_           New bid extension for the auction. Can be 0.
    function setParameters(
        uint256 orbId,
        uint256 startingPrice_,
        uint256 nextBidIncrease_,
        uint256 minimumDuration_,
        uint256 bidExtension_
    ) external virtual onlyKeeper(orbId) onlyInactive(orbId) {
        if (minimumDuration_ == 0) {
            revert InvalidAuctionDuration(minimumDuration_);
        }
        if (minimumDuration_ > os.invocations().invocationPeriod(orbId)) {
            revert InvalidAuctionDuration(minimumDuration_);
        }

        startingPrice[orbId] = startingPrice_;
        nextBidIncrease[orbId] = nextBidIncrease_ > 0 ? nextBidIncrease_ : 1;
        minimumDuration[orbId] = minimumDuration_;
        bidExtension[orbId] = bidExtension_;

        emit EnglishAuctionParametersUpdate(orbId, startingPrice_, nextBidIncrease_, minimumDuration_, bidExtension_);
    }

    /// @dev     Minimum bid that would currently be accepted by `bid()`. `auctionStartingPrice` if no bids were made,
    ///          otherwise the leading bid increased by `auctionMinimumBidStep`.
    /// @return  auctionMinimumBid  Minimum bid required for `bid()`.
    function _minimumBid(uint256 orbId) internal view virtual returns (uint256 auctionMinimumBid) {
        if (leadingBid[orbId] == 0) {
            return startingPrice[orbId];
        } else {
            unchecked {
                return leadingBid[orbId] + nextBidIncrease[orbId];
            }
        }
    }

    /// @notice  Bids the provided amount, if there's enough funds across funds on contract and transaction value.
    ///          Might extend the auction if bidding close to auction end. Important: the leading bidder will not be
    ///          able to withdraw any funds until someone outbids them or the auction is finalized.
    /// @dev     Emits `AuctionBid`.
    /// @param   orbId        The ID of the Orb to bid on.
    /// @param   amount_      The value to bid.
    /// @param   delegationHash_  The hash of the delegation data.
    function bid(uint256 orbId, uint256 amount_, bytes32 delegationHash_) external payable virtual {
        if (isActive(orbId) == false) {
            revert DelegationNotActive();
        }

        uint256 totalFunds = fundsOf[orbId][_msgSender()] + msg.value;

        if (amount_ < _minimumBid(orbId)) {
            revert InsufficientBid(amount_, _minimumBid(orbId));
        }
        if (totalFunds < amount_) {
            revert InsufficientFunds(totalFunds, amount_);
        }

        fundsOf[orbId][_msgSender()] = totalFunds;
        leadingBidder[orbId] = _msgSender();
        leadingBid[orbId] = amount_;
        delegationHash[orbId] = delegationHash_;

        emit AuctionBid(orbId, _msgSender(), amount_);

        if (block.timestamp + bidExtension[orbId] > endTime[orbId]) {
            endTime[orbId] = block.timestamp + bidExtension[orbId];
            emit AuctionExtension(orbId, endTime[orbId]);
        }
    }

    function withdrawAll(uint256 orbId) external virtual {
        _withdrawAll(_msgSender(), orbId);
    }

    function withdrawAllFor(uint256[] memory orbIds) external virtual {
        for (uint256 index = 0; index < orbIds.length; index++) {
            _withdrawAll(_msgSender(), orbIds[index]);
        }
    }

    function _withdrawAll(address user, uint256 orbId) public virtual {
        uint256 funds = fundsOf[orbId][user];
        if (funds == 0) {
            revert NoFundsAvailable();
        }
        if (leadingBidder[orbId] == user) {
            if (block.timestamp < delegationExpiration[orbId]) {
                revert NotPermittedForLeadingBidder();
            }
            _reset(orbId);
        }

        fundsOf[orbId][user] = 0;
        Address.sendValue(payable(user), funds);

        emit Withdrawal(orbId, user, funds);
    }

    /// @dev  Authorizes owner address to upgrade the contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address) internal virtual override onlyOwner {}

    /// @dev     Returns the version of the English Auction Allocation contract.
    /// @return  versionNumber  Version of the contract.
    function version() public view virtual override returns (uint256 versionNumber) {
        return _VERSION;
    }
}
