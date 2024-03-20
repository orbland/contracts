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

import {OrbV2} from "./OrbV2.sol";

/// @title   Orb v3 - Oath-honored, Harberger-taxed NFT with built-in auction and on-chain invocations
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
///          V2 adds these changes:
///          - Fixes a bug with Keeper auctions changing `lastInvocationTime`. Now only creator auctions charge the Orb.
///          - Allows setting Keeper auction royalty as different from purchase royalty.
///          - Purchase function requires to provide Keeper auction royalty in addition to other parameters.
///          - Response period setting moved from `swearOath` to `setCooldown` and renamed to `setInvocationParameters`.
///          - Active Oath is now required to start Orb auction or list Orb for sale.
///          - Orb parameters can now be updated even during Keeper control, if Oath has expired.
///          - `beneficiaryWithdrawalAddress` can now be set by the Creator to withdraw funds to a different address, if
///            the address is authorized on the OrbPond.
///          - `recall()` allows Orb creator to transfer the Orb from the Keeper back to the contract, if Oath has
///            expired, allowing for re-auctioning.
///          - Overriden `initialize()` to allow using V2 as initial implementation, with new default values.
///          - Event changes: `OathSwearing` parameter change, `InvocationParametersUpdate` added (replaces
///            `CooldownUpdate` and `CleartextMaximumLengthUpdate`), `FeesUpdate` parameter change,
///            `BeneficiaryWithdrawalAddressUpdate`, `Recall` added.
///          V3 adds these changes:
///          - Adds `minimumPrice` and `setMinimumPrice` to allow the Creator to set a minimum price for the Orb,
///            ensuring a floor for Orb tax revenue.
///          - Changing `finalizeAuction` and `purchase` to only charge the Orb the first time.
///          - Overriden `initialize()` to allow using V3 as initial implementation, with new default values.
///          - Event changes: `MinimumPriceUpdate` added.
/// @custom:security-contact security@orb.land
contract OrbV3 is OrbV2 {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event MinimumPriceUpdate(uint256 previousMinimumPrice, uint256 indexed newMinimumPrice);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error PriceTooLow(uint256 priceProvided, uint256 minimumPrice);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS

    /// Orb version. Value: 3.
    uint256 private constant _VERSION = 3;

    // STATE

    /// Minimum price allowed for the Orb
    uint256 public minimumPrice;

    /// Gap used to prevent storage collisions.
    uint256[100] private __gap;

    /// @dev    When deployed, contract mints the only token that will ever exist, to itself.
    ///         This token represents the Orb and is called the Orb elsewhere in the contract.
    ///         `Ownable` sets the deployer to be the `owner()`, and also the creator in the Orb context.
    ///         V2 changes initial values and sets `auctionKeeperMinimumDuration`.
    ///         V3 just changes reinitializer value
    /// @param  beneficiary_   Address to receive all Orb proceeds.
    /// @param  name_          Orb name, used in ERC-721 metadata.
    /// @param  symbol_        Orb symbol or ticker, used in ERC-721 metadata.
    /// @param  tokenURI_      Initial value for tokenURI JSONs.
    function initialize(address beneficiary_, string memory name_, string memory symbol_, string memory tokenURI_)
        public
        virtual
        override
        reinitializer(3)
    {
        __Ownable_init();
        __UUPSUpgradeable_init();

        name = name_;
        symbol = symbol_;
        beneficiary = beneficiary_;
        _tokenURI = tokenURI_;

        keeper = address(this);
        pond = msg.sender;

        // Initial values. Can be changed by creator before selling the Orb.

        keeperTaxNumerator = 120_00;
        purchaseRoyaltyNumerator = 10_00;
        auctionRoyaltyNumerator = 30_00;

        auctionStartingPrice = 0.05 ether;
        auctionMinimumBidStep = 0.05 ether;
        auctionMinimumDuration = 1 days;
        auctionKeeperMinimumDuration = 1 days;
        auctionBidExtension = 4 minutes;

        cooldown = 7 days;
        responsePeriod = 7 days;
        flaggingPeriod = 7 days;
        cleartextMaximumLength = 300;

        emit Creation();
    }

    /// @notice  Re-initializes the contract after upgrade, sets initial `auctionRoyaltyNumerator` value and sets
    ///          `responsePeriod` to `cooldown` if it was not set before.
    function initializeV3() public reinitializer(3) {}

    /// @notice  Allows the Orb creator to set minimum price Orb can be sold at. This function can only be called by the
    ///          Orb creator when the Orb is in their control. Setting the minimum price does not adjust the current
    ///          price, even if it's invalid: rule will apply on future Orb price settings.
    /// @dev     Emits `FeesUpdate`.
    ///          V3 adds this function to set the new minimum price. Setting the
    /// @param   newMinimumPrice  New minimum price
    function setMinimumPrice(uint256 newMinimumPrice) external virtual onlyOwner onlyCreatorControlled {
        if (newMinimumPrice > _MAXIMUM_PRICE) {
            revert InvalidNewPrice(newMinimumPrice);
        }

        uint256 previousMinimumPrice = minimumPrice;
        minimumPrice = newMinimumPrice;

        emit MinimumPriceUpdate(previousMinimumPrice, newMinimumPrice);
    }

    /// @dev    Does not check if the new price differs from the previous price: no risk. Limits the price to
    ///         MAXIMUM_PRICE to prevent potential overflows in math. Confirms that the price is above `minimumPrice`.
    ///         Emits `PriceUpdate`.
    /// @param  newPrice_  New price for the Orb.
    function _setPrice(uint256 newPrice_) internal virtual override {
        if (newPrice_ > _MAXIMUM_PRICE) {
            revert InvalidNewPrice(newPrice_);
        }
        if (newPrice_ < minimumPrice) {
            revert PriceTooLow(newPrice_, minimumPrice);
        }

        uint256 previousPrice = price;
        price = newPrice_;

        emit PriceUpdate(previousPrice, newPrice_);
    }

    /// @notice  Bids the provided amount, if there's enough funds across funds on contract and transaction value.
    ///          Might extend the auction if bidding close to auction end. Important: the leading bidder will not be
    ///          able to withdraw any funds until someone outbids them or the auction is finalized.
    /// @dev     Emits `AuctionBid`.
    /// @param   amount      The value to bid.
    /// @param   priceIfWon  Price if the bid wins. Must be less than `MAXIMUM_PRICE`.
    function bid(uint256 amount, uint256 priceIfWon) public payable virtual override {
        if (priceIfWon < minimumPrice) {
            revert PriceTooLow(priceIfWon, minimumPrice);
        }
        super.bid(amount, priceIfWon);
    }

    /// @notice  Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbVersion  Version of the Orb.
    function version() public view virtual override returns (uint256 orbVersion) {
        return _VERSION;
    }
}
