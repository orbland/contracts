// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {DeployBase} from "./DeployBase.s.sol";

contract DeployGoerli is DeployBase {
    address[] private contributorWallets = [
        0xE48C655276C23F1534AE2a87A2bf8A8A6585Df70, // ercwl.eth
        0x9F49230672c52A2b958F253134BB17Ac84d30833, // jonas.eth
        0xf374CE39E4dB1697c8D0D77F91A9234b2Fd55F62 // odysseas
    ];
    uint256[] private contributorShares = [65, 20, 15];

    // our test issuer
    address private immutable creatorAddress = 0xC0A00c8c9EF6fe6F0a79B8a616183384dbaf8EC8;
    uint256 private immutable tokenId = 1;

    constructor() DeployBase(contributorWallets, contributorShares, creatorAddress, tokenId) 
    /* solhint-disable no-empty-blocks */
    {}
    /* solhint-enable no-empty-blocks */
}
