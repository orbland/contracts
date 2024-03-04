// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC165} from "../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {ContextUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {Orbs} from "../Orbs.sol";

contract AllocationMethod is IERC165, ContextUpgradeable {
    event AuctionStart(
        uint256 indexed auctionStartTime, uint256 indexed auctionEndTime, address indexed auctionBeneficiary
    );
    event AuctionFinalization(address indexed winner, uint256 indexed winningBid);

    error InvalidPrice(uint256 priceProvided);

    error AllocationActive();
    error AllocationNotAcitve();
    error AllocationNotStarted();
    error ContractDoesNotHoldOrb();
    error NotOrbsContract();
    error NotCreator();

    /// Maximum Orb price, limited to prevent potential overflows.
    uint256 internal constant _MAXIMUM_PRICE = 2 ** 128;

    // only Orbs contract can start allocation, and Orbs contract is called upon finalization
    address public orbsContract;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    modifier notDuringAllocation(uint256 orbId) virtual {
        if (isAllocationActive(orbId)) {
            revert AllocationActive();
        }
        _;
    }

    modifier onlyCreator(uint256 orbId) virtual {
        if (_msgSender() != Orbs(orbsContract).creator(orbId)) {
            revert NotCreator();
        }
        _;
    }

    modifier onlyCreatorControlled(uint256 orbId) virtual {
        _;
    }

    modifier onlyOrbsContract() virtual {
        if (_msgSender() != orbsContract) {
            revert NotOrbsContract();
        }
        _;
    }

    function supportsInterface(bytes4 interfaceId) external view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }

    function initializeOrb(uint256 orbId) public virtual {}

    function version() external view virtual returns (uint256) {}

    function isAllocationActive(uint256 orbId) public view virtual returns (bool) {
        return false;
    }

    function startAllocation(uint256 orbId, bool reallocation) external virtual {}

    function cancelAllocation(uint256 orbId) external virtual {}

    function finalizeAllocation(uint256 orbId) external virtual {}

    function isReallocationEnabled(uint256 orbId) external view virtual returns (bool) {}

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
}
