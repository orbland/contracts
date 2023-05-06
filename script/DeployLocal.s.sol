// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DeployBase} from "./DeployBase.s.sol";

contract DeployLocal is DeployBase {
    address[] public contributorWallets = [
        0xE48C655276C23F1534AE2a87A2bf8A8A6585Df70, // ercwl.eth
        0x9F49230672c52A2b958F253134BB17Ac84d30833, // jonas.eth
        0xf374CE39E4dB1697c8D0D77F91A9234b2Fd55F62 // odysseas
    ];
    uint256[] public contributorShares = [65, 20, 15];

    // would be ercwl.eth for mainnet
    address public immutable issuerWallet = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    uint256 public immutable cooldown = 2 minutes;
    uint256 public immutable auctionMinimumDuration = 2 minutes;
    uint256 public immutable auctionBidExtension = 30 seconds;
    uint256 private immutable auctionStartingPrice = 0.1 ether;
    uint256 private immutable auctionMinimumBidStep = 0.1 ether;

    constructor()
        DeployBase(
            contributorWallets,
            contributorShares,
            issuerWallet,
            cooldown,
            auctionMinimumDuration,
            auctionBidExtension,
            auctionStartingPrice,
            auctionMinimumBidStep
        )
    /* solhint-disable no-empty-blocks */
    {}
    /* solhint-enable no-empty-blocks */
}
