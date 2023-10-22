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
pragma solidity 0.8.20;

import {Orb} from "./Orb.sol";

/// @title   Orb v2 - Oath-honored, Harberger-taxed NFT with built-in auction and on-chain invocations
/// @author  Jonas Lekevicius
/// @author  Eric Wall
/// @notice  The Orb is issued by a Creator: the user who swore an Orb Oath together with a date until which the Oath
///          will be honored. The Creator can list the Orb for sale at a fixed price, or run an auction for it. The user
///          acquiring the Orb is known as the Keeper. The Keeper always has an Orb sale price set and is paying
///          Harberger tax based on their set price and a tax rate set by the Creator. This tax is accounted for per
///          second, and the Keeper must have enough funds on this contract to cover their ownership; otherwise the Orb
///          is re-auctioned, delivering most of the auction proceeds to the previous Keeper. The Orb also has a
///          cooldown that allows the Keeper to invoke the Orb — ask the Creator a question and receive their response,
///          based on conditions set in the Orb Oath. Invocation and response hashes and timestamps are tracked in an
///          Orb Invocation Registry.
/// @dev     Supports ERC-721 interface, including metadata, but reverts on all transfers and approvals. Uses
///          `Ownable`'s `owner()` to identify the Creator of the Orb. Uses a custom `UUPSUpgradeable` implementation to
///          allow upgrades, if they are requested by the Creator and executed by the Keeper. The Orb is created as an
///          ERC-1967 proxy to an `Orb` implementation by the `OrbPond` contract, which is also used to track allowed
///          Orb upgrades and keeps a reference to an `OrbInvocationRegistry` used by this Orb.
///          V2 fixes a bug with Keeper auctions changing lastInvocationTime.
contract OrbV2 is Orb {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event OathSwearing(bytes32 indexed oathHash, uint256 indexed honoredUntil);
    event InvocationParametersUpdate(
        uint256 previousCooldown,
        uint256 indexed newCooldown,
        uint256 previousResponsePeriod,
        uint256 indexed newResponsePeriod,
        uint256 previousFlaggingPeriod,
        uint256 indexed newFlaggingPeriod,
        uint256 previousCleartextMaximumLength,
        uint256 newCleartextMaximumLength
    );

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error NotHonored();
    /// Orb version. Value: 2.
    uint256 private constant _VERSION = 2;

    /// @notice  Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbVersion  Version of the Orb.
    function version() public view virtual override returns (uint256 orbVersion) {
        return _VERSION;
    }

    /// @dev  Ensures that the Orb belongs to the contract itself or the creator, and the auction hasn't been started.
    ///       Most setting-adjusting functions should use this modifier. It means that the Orb properties cannot be
    ///       modified while it is held by the keeper or users can bid on the Orb.
    ///       V2 changes to allow setting parameters even during Keeper control, if Oath has expired.
    modifier onlyCreatorControlled() virtual override {
        if (address(this) != keeper && owner() != keeper && honoredUntil >= block.timestamp) {
            revert CreatorDoesNotControlOrb();
        }
        if (auctionEndTime > 0) {
            revert AuctionRunning();
        }
        _;
    }

    /// @dev  Ensures that the Orb Oath is still honored (`honoredUntil` is in the future). Used to enforce Oath
    ///       swearing before starting the auction or listing the Orb for sale.
    modifier onlyHonored() virtual {
        if (honoredUntil < block.timestamp) {
            revert NotHonored();
        }
        _;
    }

    /// @notice  Allows re-swearing of the Orb Oath and set a new `honoredUntil` date. This function can only be called
    ///          by the Orb creator when the Orb is in their control. With `swearOath()`, `honoredUntil` date can be
    ///          decreased, unlike with the `extendHonoredUntil()` function.
    /// @dev     Emits `OathSwearing`.
    ///          V2 changes to allow re-swearing even during Keeper control, if Oath has expired, and moves
    ///          `responsePeriod` setting to `setInvocationParameters()`.
    /// @param   oathHash           Hash of the Oath taken to create the Orb.
    /// @param   newHonoredUntil    Date until which the Orb creator will honor the Oath for the Orb keeper.
    function swearOath(bytes32 oathHash, uint256 newHonoredUntil) external virtual onlyOwner onlyCreatorControlled {
        honoredUntil = newHonoredUntil;
        emit OathSwearing(oathHash, newHonoredUntil);
    }

    /// @dev  Previous `swearOath()` overriden to revert.
    function swearOath(bytes32, uint256, uint256) external pure override {
        revert NotSupported();
    }

    /// @notice  Allows the Orb creator to set the new cooldown duration, response period, flagging period (duration for
    ///          how long Orb keeper may flag a response) and cleartext maximum length. This function can only be called
    ///          by the Orb creator when the Orb is in their control.
    /// @dev     Emits `InvocationParametersUpdate`.
    ///          V2 merges `setCooldown()` and `setCleartextMaximumLength()` into one function, and moves
    ///          `responsePeriod` setting here. Events `CooldownUpdate` and `CleartextMaximumLengthUpdate` are merged
    ///          into `InvocationParametersUpdate`.
    /// @param   newCooldown        New cooldown in seconds. Cannot be longer than `COOLDOWN_MAXIMUM_DURATION`.
    /// @param   newFlaggingPeriod  New flagging period in seconds.
    /// @param   newResponsePeriod  New flagging period in seconds.
    /// @param   newCleartextMaximumLength  New cleartext maximum length. Cannot be 0.
    function setInvocationParameters(
        uint256 newCooldown,
        uint256 newResponsePeriod,
        uint256 newFlaggingPeriod,
        uint256 newCleartextMaximumLength
    ) external virtual onlyOwner onlyCreatorControlled {
        if (newCooldown > _COOLDOWN_MAXIMUM_DURATION) {
            revert CooldownExceedsMaximumDuration(newCooldown, _COOLDOWN_MAXIMUM_DURATION);
        }
        if (newCleartextMaximumLength == 0) {
            revert InvalidCleartextMaximumLength(newCleartextMaximumLength);
        }

        uint256 previousCooldown = cooldown;
        cooldown = newCooldown;
        uint256 previousResponsePeriod = responsePeriod;
        responsePeriod = newResponsePeriod;
        uint256 previousFlaggingPeriod = flaggingPeriod;
        flaggingPeriod = newFlaggingPeriod;
        uint256 previousCleartextMaximumLength = cleartextMaximumLength;
        cleartextMaximumLength = newCleartextMaximumLength;
        emit InvocationParametersUpdate(
            previousCooldown,
            newCooldown,
            previousResponsePeriod,
            newResponsePeriod,
            previousFlaggingPeriod,
            newFlaggingPeriod,
            previousCleartextMaximumLength,
            newCleartextMaximumLength
        );
    }

    /// @dev  Previous `setCooldown()` overriden to revert.
    function setCooldown(uint256, uint256) external pure override {
        revert NotSupported();
    }

    /// @dev  Previous `setCleartextMaximumLength()` overriden to revert.
    function setCleartextMaximumLength(uint256) external pure override {
        revert NotSupported();
    }

    /// @notice  Allow the Orb creator to start the Orb auction. Will run for at least `auctionMinimumDuration`.
    /// @dev     Prevents repeated starts by checking the `auctionEndTime`. Important to set `auctionEndTime` to 0
    ///          after auction is finalized. Emits `AuctionStart`.
    ///          V2 adds `onlyHonored` modifier to require active Oath to start auction.
    function startAuction() external virtual override onlyOwner notDuringAuction onlyHonored {
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
    ///          If the auction was started by previous Keeper with `relinquishWithAuction()`, then most of the auction
    ///          proceeds (minus the royalty) will be sent to the previous Keeper. Sets `lastInvocationTime` so that
    ///          the Orb could be invoked immediately. The price has been set when bidding, now becomes relevant. If no
    ///          bids were made, resets the state to allow the auction to be started again later.
    /// @dev     Critical state transition function. Called after `auctionEndTime`, but only if it's not 0. Can be
    ///          called by anyone, although probably will be called by the creator or the winner. Emits `PriceUpdate`
    ///          and `AuctionFinalization`.
    ///          V2 fixes a bug with Keeper auctions changing lastInvocationTime.
    function finalizeAuction() external virtual override notDuringAuction {
        if (auctionEndTime == 0) {
            revert AuctionNotStarted();
        }

        address _leadingBidder = leadingBidder;
        uint256 _leadingBid = leadingBid;

        if (_leadingBidder != address(0)) {
            fundsOf[_leadingBidder] -= _leadingBid;

            uint256 auctionMinimumRoyaltyNumerator =
                (keeperTaxNumerator * auctionKeeperMinimumDuration) / _KEEPER_TAX_PERIOD;
            uint256 auctionRoyalty =
                auctionMinimumRoyaltyNumerator > royaltyNumerator ? auctionMinimumRoyaltyNumerator : royaltyNumerator;
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

    /// @notice  Lists the Orb for sale at the given price to buy directly from the Orb creator. This is an alternative
    ///          to the auction mechanism, and can be used to simply have the Orb for sale at a fixed price, waiting
    ///          for the buyer. Listing is only allowed if the auction has not been started and the Orb is held by the
    ///          contract. When the Orb is purchased from the creator, all proceeds go to the beneficiary and the Orb
    ///          comes fully charged, with no cooldown.
    /// @dev     Emits `Transfer` and `PriceUpdate`.
    ///          V2 adds `onlyHonored` modifier to require active Oath to list Orb for sale.
    /// @param   listingPrice  The price to buy the Orb from the creator.
    function listWithPrice(uint256 listingPrice) external virtual override onlyOwner onlyHonored {
        if (address(this) != keeper) {
            revert ContractDoesNotHoldOrb();
        }

        if (auctionEndTime > 0) {
            revert AuctionRunning();
        }

        _transferOrb(address(this), msg.sender);
        _setPrice(listingPrice);
    }
}
