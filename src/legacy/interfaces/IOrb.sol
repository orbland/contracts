// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC165} from "../../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

interface IOrb is IERC165 {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Auction View Functions
    function auctionEndTime() external view returns (uint256);
    function leadingBidder() external view returns (address);
    function leadingBid() external view returns (uint256);
    function auctionBeneficiary() external view returns (address);
    function auctionStartingPrice() external view returns (uint256);
    function auctionMinimumBidStep() external view returns (uint256);
    function auctionMinimumDuration() external view returns (uint256);
    function auctionKeeperMinimumDuration() external view returns (uint256);
    function auctionBidExtension() external view returns (uint256);

    // Funding View Functions
    function fundsOf(address owner) external view returns (uint256);
    function lastSettlementTime() external view returns (uint256);
    function keeperSolvent() external view returns (bool);
    function keeperTaxNumerator() external view returns (uint256);
    function feeDenominator() external view returns (uint256);
    function keeperTaxPeriod() external view returns (uint256);

    // Purchasing View Functions
    function keeper() external view returns (address);
    function keeperReceiveTime() external view returns (uint256);
    function price() external view returns (uint256);
    function royaltyNumerator() external view returns (uint256);

    // Invoking and Responding View Functions
    function cooldown() external view returns (uint256);
    function flaggingPeriod() external view returns (uint256);
    function lastInvocationTime() external view returns (uint256);
    function cleartextMaximumLength() external view returns (uint256);

    // Orb Parameter View Functions
    function pond() external view returns (address);
    function creator() external view returns (address);
    function beneficiary() external view returns (address);
    function honoredUntil() external view returns (uint256);
    function responsePeriod() external view returns (uint256);

    // Upgrading View Functions
    function version() external view returns (uint256);
    function requestedUpgradeImplementation() external view returns (address);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function initialize(address beneficiary_, string memory name_, string memory symbol_, string memory tokenURI_)
        external;

    // Auction Functions
    function startAuction() external;
    function bid(uint256 amount, uint256 priceIfWon) external payable;
    function finalizeAuction() external;

    // Funding Functions
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function withdrawAll() external;
    function withdrawAllForBeneficiary() external;
    function settle() external;

    // Purchasing Functions
    function listWithPrice(uint256 listingPrice) external;
    function setPrice(uint256 newPrice) external;
    function purchase(
        uint256 newPrice,
        uint256 currentPrice,
        uint256 currentKeeperTaxNumerator,
        uint256 currentRoyaltyNumerator,
        uint256 currentCooldown,
        uint256 currentCleartextMaximumLength
    ) external payable;

    // Orb Ownership Functions
    function relinquish(bool withAuction) external;
    function foreclose() external;

    // Invoking Functions
    function setLastInvocationTime(uint256 timestamp) external;

    // Orb Parameter Functions
    function swearOath(bytes32 oathHash, uint256 newHonoredUntil, uint256 newResponsePeriod) external;
    function extendHonoredUntil(uint256 newHonoredUntil) external;
    function setTokenURI(string memory newTokenURI) external;
    function setAuctionParameters(
        uint256 newStartingPrice,
        uint256 newMinimumBidStep,
        uint256 newMinimumDuration,
        uint256 newKeeperMinimumDuration,
        uint256 newBidExtension
    ) external;
    function setFees(uint256 newKeeperTaxNumerator, uint256 newRoyaltyNumerator) external;
    function setCooldown(uint256 newCooldown, uint256 newFlaggingPeriod) external;
    function setCleartextMaximumLength(uint256 newCleartextMaximumLength) external;

    // Upgrading Functions
    function requestUpgrade(address requestedImplementation) external;
    function upgradeToNextVersion() external;
}
