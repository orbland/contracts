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

import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

import {Orb} from "./OrbV1Renamed.sol";
import {OrbPondV2} from "./OrbPondV2.sol";

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
/// @custom:security-contact security@orb.land
contract OrbV2 is Orb {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event OathSwearing(bytes32 indexed oathHash, uint256 indexed honoredUntil);
    event FeesUpdate(
        uint256 previousKeeperTaxNumerator,
        uint256 indexed newKeeperTaxNumerator,
        uint256 previousPurchaseRoyaltyNumerator,
        uint256 indexed newPurchaseRoyaltyNumerator,
        uint256 previousAuctionRoyaltyNumerator,
        uint256 indexed newAuctionRoyaltyNumerator
    );
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
    event BeneficiaryWithdrawalAddressUpdate(
        address previousBeneficiaryWithdrawalAddress, address indexed newBeneficiaryWithdrawalAddress
    );
    event Recall(address indexed formerKeeper);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error AddressNotPermitted(address unauthorizedAddress);
    error KeeperDoesNotHoldOrb();
    error NotHonored();
    error OathStillHonored();

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS

    /// Orb version. Value: 2.
    uint256 private constant _VERSION = 2;

    // STATE

    /// Secondary sale royalty paid to beneficiary, based on sale price. Initial value is 10.00%.
    uint256 public auctionRoyaltyNumerator;

    /// Address to withdraw beneficiary funds. If zero address, `beneficiary` is used. Can be set by Creator at any
    /// point using `setBeneficiaryWithdrawalAddress()`.
    address public beneficiaryWithdrawalAddress;

    /// Gap used to prevent storage collisions.
    uint256[100] private __gap;

    /// @dev    When deployed, contract mints the only token that will ever exist, to itself.
    ///         This token represents the Orb and is called the Orb elsewhere in the contract.
    ///         `Ownable` sets the deployer to be the `owner()`, and also the creator in the Orb context.
    ///         V2 changes initial values and sets `auctionKeeperMinimumDuration`.
    /// @param  beneficiary_   Address to receive all Orb proceeds.
    /// @param  name_          Orb name, used in ERC-721 metadata.
    /// @param  symbol_        Orb symbol or ticker, used in ERC-721 metadata.
    /// @param  tokenURI_      Initial value for tokenURI JSONs.
    function initialize(address beneficiary_, string memory name_, string memory symbol_, string memory tokenURI_)
        public
        virtual
        override
        reinitializer(2)
    {
        __Ownable_init(msg.sender);
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
    function initializeV2() public reinitializer(2) {
        auctionRoyaltyNumerator = purchaseRoyaltyNumerator;
        if (responsePeriod == 0) {
            responsePeriod = cooldown;
        }
    }

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
            // Creator CAN control Orb (does not revert) if any of these FALSE:
            // - Orb is not held by the contract itself
            // - Orb is not held by the creator
            // - Oath is still honored
            // Inverted, this means that the creator CAN control if any of these are TRUE:
            // - Orb is held by the contract itself
            // - Orb is held by the creator
            // - Oath is not honored (even if Orb is held by the Keeper)
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

    /// @notice  Allows the Orb creator to set the new keeper tax and royalty. This function can only be called by the
    ///          Orb creator when the Orb is in their control.
    /// @dev     Emits `FeesUpdate`.
    ///          V2 changes to allow setting Keeper auction royalty separately from purchase royalty, with releated
    ///          parameter and event changes.
    /// @param   newKeeperTaxNumerator        New keeper tax numerator, in relation to `feeDenominator()`.
    /// @param   newPurchaseRoyaltyNumerator  New royalty numerator for royalties from `purchase()`, in relation to
    ///                                       `feeDenominator()`. Cannot be larger than `feeDenominator()`.
    /// @param   newAuctionRoyaltyNumerator   New royalty numerator for royalties from keeper auctions, in relation to
    ///                                       `feeDenominator()`. Cannot be larger than `feeDenominator()`.
    function setFees(
        uint256 newKeeperTaxNumerator,
        uint256 newPurchaseRoyaltyNumerator,
        uint256 newAuctionRoyaltyNumerator
    ) external virtual onlyOwner onlyCreatorControlled {
        if (keeper != address(this)) {
            _settle();
        }
        if (newPurchaseRoyaltyNumerator > _FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(newPurchaseRoyaltyNumerator, _FEE_DENOMINATOR);
        }
        if (newAuctionRoyaltyNumerator > _FEE_DENOMINATOR) {
            revert RoyaltyNumeratorExceedsDenominator(newAuctionRoyaltyNumerator, _FEE_DENOMINATOR);
        }

        uint256 previousKeeperTaxNumerator = keeperTaxNumerator;
        keeperTaxNumerator = newKeeperTaxNumerator;

        uint256 previousPurchaseRoyaltyNumerator = purchaseRoyaltyNumerator;
        purchaseRoyaltyNumerator = newPurchaseRoyaltyNumerator;

        uint256 previousAuctionRoyaltyNumerator = auctionRoyaltyNumerator;
        auctionRoyaltyNumerator = newAuctionRoyaltyNumerator;

        emit FeesUpdate(
            previousKeeperTaxNumerator,
            newKeeperTaxNumerator,
            previousPurchaseRoyaltyNumerator,
            newPurchaseRoyaltyNumerator,
            previousAuctionRoyaltyNumerator,
            newAuctionRoyaltyNumerator
        );
    }

    /// @dev  Previous `setFees()` overriden to revert.
    function setFees(uint256, uint256) external pure override {
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

    /// @notice  Allows the Orb creator to set the new beneficiary withdrawal address, which can be different from
    ///          `beneficiary`, allowing Payment Splitter to be changed to a new version. Only addresses authorized on
    ///          the OrbPond (or the zero address, to reset to `beneficiary` value) can be set as the new withdrawal
    ///          address. This function can only be called anytime by the Orb Creator.
    /// @dev     Emits `BeneficiaryWithdrawalAddressUpdate`.
    /// @param   newBeneficiaryWithdrawalAddress  New beneficiary withdrawal address.
    function setBeneficiaryWithdrawalAddress(address newBeneficiaryWithdrawalAddress) external virtual onlyOwner {
        if (
            newBeneficiaryWithdrawalAddress == address(0)
                || OrbPondV2(pond).beneficiaryWithdrawalAddressPermitted(newBeneficiaryWithdrawalAddress)
        ) {
            address previousBeneficiaryWithdrawalAddress = beneficiaryWithdrawalAddress;
            beneficiaryWithdrawalAddress = newBeneficiaryWithdrawalAddress;
            emit BeneficiaryWithdrawalAddressUpdate(
                previousBeneficiaryWithdrawalAddress, newBeneficiaryWithdrawalAddress
            );
        } else {
            revert AddressNotPermitted(newBeneficiaryWithdrawalAddress);
        }
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
    ///          If the auction was started by previous Keeper with `relinquish(true)`, then most of the auction
    ///          proceeds (minus the royalty) will be sent to the previous Keeper. Sets `lastInvocationTime` so that
    ///          the Orb could be invoked immediately. The price has been set when bidding, now becomes relevant. If no
    ///          bids were made, resets the state to allow the auction to be started again later.
    /// @dev     Critical state transition function. Called after `auctionEndTime`, but only if it's not 0. Can be
    ///          called by anyone, although probably will be called by the creator or the winner. Emits `PriceUpdate`
    ///          and `AuctionFinalization`.
    ///          V2 fixes a bug with Keeper auctions changing lastInvocationTime, and uses `auctionRoyaltyNumerator`
    ///          instead of `purchaseRoyaltyNumerator` for auction royalty (only relevant for Keeper auctions).
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
    ) external payable virtual onlyKeeperHeld onlyKeeperSolvent {
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
            lastInvocationTime = block.timestamp - cooldown;
            fundsOf[beneficiary] += currentPrice;
        } else {
            _splitProceeds(currentPrice, _keeper, purchaseRoyaltyNumerator);
        }

        _setPrice(newPrice);

        emit Purchase(_keeper, msg.sender, currentPrice);

        _transferOrb(_keeper, msg.sender);
    }

    /// @dev  Previous `purchase()` overriden to revert.
    function purchase(uint256, uint256, uint256, uint256, uint256, uint256) external payable virtual override {
        revert NotSupported();
    }

    /// @notice  Allows the Orb creator to recall the Orb from the Keeper, if the Oath is no longer honored. This is an
    ///          alternative to just extending the Oath or swearing it while held by Keeper. It benefits the Orb creator
    ///          as they can set a new Oath and run a new auction. This acts as an alternative to just abandoning the
    ///          Orb after Oath expires.
    /// @dev     Emits `Recall`. Does not transfer remaining funds to the Keeper to allow recalling even if the Keeper
    ///          is a smart contract rejecting ether transfers.
    function recall() external virtual onlyOwner {
        address _keeper = keeper;
        if (address(this) == _keeper || owner() == _keeper) {
            revert KeeperDoesNotHoldOrb();
        }
        if (honoredUntil >= block.timestamp) {
            revert OathStillHonored();
        }
        // Auction cannot be running while held by Keeper, no check needed

        _settle();

        price = 0;
        emit Recall(_keeper);

        _transferOrb(_keeper, address(this));
    }

    /// @notice  Function to withdraw all beneficiary funds on the contract. Settles if possible.
    /// @dev     Allowed for anyone at any time, does not use `msg.sender` in its execution.
    ///          Emits `Withdrawal`.
    ///          V2 changes to withdraw to `beneficiaryWithdrawalAddress` if set to a non-zero address, and copies
    ///          `_withdraw()` functionality to this function, as it modifies funds of a different address (always
    ///          `beneficiary`) than the withdrawal destination (potentially `beneficiaryWithdrawalAddress`).
    function withdrawAllForBeneficiary() external virtual override {
        if (keeper != address(this)) {
            _settle();
        }
        address withdrawalAddress =
            beneficiaryWithdrawalAddress == address(0) ? beneficiary : beneficiaryWithdrawalAddress;
        uint256 amount = fundsOf[beneficiary];
        fundsOf[beneficiary] = 0;

        emit Withdrawal(withdrawalAddress, amount);
        Address.sendValue(payable(withdrawalAddress), amount);
    }
}
