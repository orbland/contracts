// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DeployBase} from "./DeployBase.s.sol";

contract DeployLocal is DeployBase {
    address[] public beneficiaryAddresses = [
        0xE48C655276C23F1534AE2a87A2bf8A8A6585Df70, // ercwl.eth
        0x9F49230672c52A2b958F253134BB17Ac84d30833, // jonas.eth
        0xf374CE39E4dB1697c8D0D77F91A9234b2Fd55F62 // odysseas
    ];
    uint256[] public beneficiaryShares = [65, 20, 15];

    address public immutable creatorAddress = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;

    string public orbName = "Test Orb";
    string public orbSymbol = "ORB";
    uint256 public immutable tokenId = 1;

    uint256 public immutable auctionStartingPrice = 0.1 ether;
    uint256 public immutable auctionMinimumBidStep = 0.1 ether;
    uint256 public immutable auctionMinimumDuration = 2 minutes;
    uint256 public immutable auctionKeeperMinimumDuration = 1 minutes;
    uint256 public immutable auctionBidExtension = 30 seconds;

    uint256 public immutable keeperTaxNumerator = 10_00;
    uint256 public immutable royaltyNumerator = 10_00;

    uint256 public immutable cooldown = 2 minutes;
    uint256 public immutable flaggingPeriod = 5 minutes;

    uint256 public immutable cleartextMaximumLength = 280;

    constructor()
        DeployBase(
            beneficiaryAddresses,
            beneficiaryShares,
            creatorAddress,
            orbName,
            orbSymbol,
            tokenId,
            auctionStartingPrice,
            auctionMinimumBidStep,
            auctionMinimumDuration,
            auctionKeeperMinimumDuration,
            auctionBidExtension,
            keeperTaxNumerator,
            royaltyNumerator,
            cooldown,
            flaggingPeriod,
            cleartextMaximumLength
        )
    /* solhint-disable no-empty-blocks */
    {}
    /* solhint-enable no-empty-blocks */
}
