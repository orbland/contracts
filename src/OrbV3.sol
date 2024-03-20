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

        auctionStartingPrice = 0.01 ether;
        auctionMinimumBidStep = 0.01 ether;
        auctionMinimumDuration = 1 days;
        auctionKeeperMinimumDuration = 1 days;
        auctionBidExtension = 4 minutes;

        cooldown = 7 days;
        responsePeriod = 7 days;
        flaggingPeriod = 7 days;
        cleartextMaximumLength = 280;

        emit Creation();
    }

    /// @notice  Re-initializes the contract after upgrade. Only updates the reinitializer value, to prevent
    ///          re-initializing with the new `initialize` function.
    // solhint-disable-next-line no-empty-blocks
    function initializeV3() public reinitializer(3) {}

    /// @notice  Allows the Orb creator to set minimum price Orb can be sold at. This function can only be called by the
    ///          Orb creator when the Orb is in their control. Setting the minimum price does not adjust the current
    ///          price, even if it's invalid: rule will apply on future Orb price settings.
    /// @dev     Emits `MinimumPriceUpdate`.
    ///          V3 adds this function to set the new minimum price.
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
    ///          V3 changes to only change `lastInvocationTime` if the auction was started by the creator, and to only
    ///          the first time.
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
            uint256 auctionRoyalty = auctionMinimumRoyaltyNumerator > auctionRoyaltyNumerator
                ? auctionMinimumRoyaltyNumerator
                : auctionRoyaltyNumerator;
            _splitProceeds(_leadingBid, auctionBeneficiary, auctionRoyalty);

            lastSettlementTime = block.timestamp;
            if (auctionBeneficiary == beneficiary && lastInvocationTime == 0) {
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

    /// @notice  Purchasing is the mechanism to take over the Orb. With Harberger tax, the Orb can always be purchased
    ///          from its keeper. Purchasing is only allowed while the keeper is solvent. If not, the Orb has to be
    ///          foreclosed and re-auctioned. This function does not require the purchaser to have more funds than
    ///          required, but purchasing without any reserve would leave the new owner immediately foreclosable.
    ///          Beneficiary receives either just the royalty, or full price if the Orb is purchased from the creator.
    /// @dev     Requires to provide key Orb parameters (current price, Harberger tax rate, royalty, cooldown and
    ///          cleartext maximum length) to prevent front-running: without these parameters Orb creator could
    ///          front-run purcaser and change Orb parameters before the purchase; and without current price anyone
    ///          could purchase the Orb ahead of the purchaser, set the price higher, and profit from the purchase.
    ///          Does not modify `lastInvocationTime` unless buying from the creator.
    ///          Does not allow settlement in the same block before `purchase()` to prevent transfers that avoid
    ///          royalty payments. Does not allow purchasing from yourself. Emits `PriceUpdate` and `Purchase`.
    ///          V2 changes to require providing Keeper auction royalty to prevent front-running.
    ///          V3 changes to only change `lastInvocationTime` if the auction was started by the creator, and to only
    ///          the first time.
    /// @param   newPrice                         New price to use after the purchase.
    /// @param   currentPrice                     Current price, to prevent front-running.
    /// @param   currentKeeperTaxNumerator        Current keeper tax numerator, to prevent front-running.
    /// @param   currentPurchaseRoyaltyNumerator  Current royalty numerator, to prevent front-running.
    /// @param   currentAuctionRoyaltyNumerator   Current keeper auction royalty numerator, to prevent front-running.
    /// @param   currentCooldown                  Current cooldown, to prevent front-running.
    /// @param   currentCleartextMaximumLength    Current cleartext maximum length, to prevent front-running.
    /// @param   currentHonoredUntil              Current honored until timestamp, to prevent front-running.
    function purchase(
        uint256 newPrice,
        uint256 currentPrice,
        uint256 currentKeeperTaxNumerator,
        uint256 currentPurchaseRoyaltyNumerator,
        uint256 currentAuctionRoyaltyNumerator,
        uint256 currentCooldown,
        uint256 currentCleartextMaximumLength,
        uint256 currentHonoredUntil
    ) external payable virtual override onlyKeeperHeld onlyKeeperSolvent {
        if (currentPrice != price) {
            revert CurrentValueIncorrect(currentPrice, price);
        }
        if (currentKeeperTaxNumerator != keeperTaxNumerator) {
            revert CurrentValueIncorrect(currentKeeperTaxNumerator, keeperTaxNumerator);
        }
        if (currentPurchaseRoyaltyNumerator != purchaseRoyaltyNumerator) {
            revert CurrentValueIncorrect(currentPurchaseRoyaltyNumerator, purchaseRoyaltyNumerator);
        }
        if (currentAuctionRoyaltyNumerator != auctionRoyaltyNumerator) {
            revert CurrentValueIncorrect(currentAuctionRoyaltyNumerator, auctionRoyaltyNumerator);
        }
        if (currentCooldown != cooldown) {
            revert CurrentValueIncorrect(currentCooldown, cooldown);
        }
        if (currentCleartextMaximumLength != cleartextMaximumLength) {
            revert CurrentValueIncorrect(currentCleartextMaximumLength, cleartextMaximumLength);
        }
        if (currentHonoredUntil != honoredUntil) {
            revert CurrentValueIncorrect(currentHonoredUntil, honoredUntil);
        }

        if (lastSettlementTime >= block.timestamp) {
            revert PurchasingNotPermitted();
        }

        _settle();

        address _keeper = keeper;

        if (msg.sender == _keeper) {
            revert AlreadyKeeper();
        }
        if (msg.sender == beneficiary) {
            revert NotPermitted();
        }

        fundsOf[msg.sender] += msg.value;
        uint256 totalFunds = fundsOf[msg.sender];

        if (totalFunds < currentPrice) {
            revert InsufficientFunds(totalFunds, currentPrice);
        }

        fundsOf[msg.sender] -= currentPrice;
        if (owner() == _keeper) {
            if (lastInvocationTime == 0) {
                lastInvocationTime = block.timestamp - cooldown;
            }
            fundsOf[beneficiary] += currentPrice;
        } else {
            _splitProceeds(currentPrice, _keeper, purchaseRoyaltyNumerator);
        }

        _setPrice(newPrice);

        emit Purchase(_keeper, msg.sender, currentPrice);

        _transferOrb(_keeper, msg.sender);
    }

    /// @notice  Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbVersion  Version of the Orb.
    function version() public view virtual override returns (uint256 orbVersion) {
        return _VERSION;
    }
}
