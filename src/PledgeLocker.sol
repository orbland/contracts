// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {Orbs} from "./Orbs.sol";
import {InvocationRegistry, InvocationData} from "./InvocationRegistry.sol";
import {AllocationMethod} from "./allocation/AllocationMethod.sol";

/// @title   Orb Pledge Locker
/// @author  Jonas Lekevicius
/// @notice  The Orb is issued by a Creator: the user who swore an Orb Oath together with a date until which the Oath
///          will be honored. The Creator can list the Orb for sale at a fixed price, or run an auction for it. The user
///          acquiring the Orb is known as the Keeper. The Keeper always has an Orb sale price set and is paying
///          Harberger tax based on their set price and a tax rate set by the Creator. This tax is accounted for per
///          second, and the Keeper must have enough funds on this contract to cover their ownership; otherwise the Orb
///          is re-auctioned, delivering most of the auction proceeds to the previous Keeper. The Orb also has a
///          cooldown that allows the Keeper to invoke the Orb — ask the Creator a question and receive their response,
///          based on conditions set in the Orb Oath. Invocation and response hashes and timestamps are tracked in an
///          Orb Invocation Registry.
/// @dev     Does not support ERC-721 interface.
/// @custom:security-contact security@orb.land
contract PledgeLocker is OwnableUpgradeable, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STRUCTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    struct ERC20Pledge {
        address contractAddress;
        uint256 tokenAmount;
    }

    struct ERC721Pledge {
        address contractAddress;
        uint256 tokenId;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event NativeTokenPledge(uint256 indexed orbId, uint256 tokenAmount, uint256 pledgedUntil);
    event ERC20TokenPledge(
        uint256 indexed orbId, address indexed tokenContract, uint256 tokenAmount, uint256 pledgedUntil
    );
    event ERC721TokenPledge(
        uint256 indexed orbId, address indexed tokenContract, uint256 indexed tokenId, uint256 pledgedUntil
    );
    event PledgedUntilUpdate(uint256 indexed orbId, uint256 previousPledgedUntil, uint256 indexed newPledgedUntil);
    event PledgeClaimed(uint256 indexed orbId, address indexed claimer);
    event PledgeRetrieved(uint256 indexed orbId, address indexed retriever);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Orb Parameter Errors
    error PledgedUntilNotDecreasable();
    error TokenStillPledged();
    error NotInvoker();

    error NotCreatorControlled();

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS

    /// Orb version. Value: 1.
    uint256 private constant _VERSION = 1;

    // STATE

    /// Address of the `Orbs` contract. Used to verify Orb creation authorization.
    address public orbsContract;
    /// Address of the `OrbPond` that deployed this Orb. Pond manages permitted upgrades and provides Orb Invocation
    /// Registry address.
    address public registry;

    mapping(uint256 orbId => uint256) public pledgedNativeTokens;
    mapping(uint256 orbId => ERC20Pledge) public pledgedERC20Tokens;
    /// Pledged ERC-721 token. Orb creator can lock an ERC-721 token in the Orb, guaranteeing timely responses.
    mapping(uint256 orbId => ERC721Pledge) public pledgedERC721Token;
    /// Honored Until: timestamp until which the Orb Oath is honored for the keeper.
    mapping(uint256 orbId => uint256 pledgedUntil) public pledgedUntil;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initalize(address orbsContract_, address registry_) public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();

        orbsContract = orbsContract_;
        registry = registry_;
    }

    modifier onlyCreator(uint256 orbId) {
        _;
    }

    modifier onlyKeeper(uint256 orbId) {
        _;
    }

    modifier onlyKeeperSolvent(uint256 orbId) {
        _;
    }

    modifier onlyCreatorControlled(uint256 orbId) {
        if (!Orbs(orbsContract).isCreatorControlled(orbId)) {
            revert NotCreatorControlled();
        }
        _;
    }

    function isPledged(uint256 orbId) public view returns (bool) {
        return pledgedNativeTokens[orbId] > 0 || pledgedERC20Tokens[orbId].contractAddress != address(0)
            || pledgedERC721Token[orbId].contractAddress != address(0);
    }

    function isPledgeActive(uint256 orbId) public view returns (bool) {
        return pledgedUntil[orbId] > block.timestamp;
    }

    function isPledgeClaimable(uint256 orbId) public view returns (bool) {
        return canClaimPledge(orbId, address(0));
        // TODO

        // Meanings of isPledgeClaimable can differ:
        // - most of the time its about preventing some actions while
    }

    function canClaimPledge(uint256 orbId, address claimer_) public view returns (bool) {
        if (!isPledged(orbId)) {
            return false;
        }
        (bool hasExpiredInvocation, uint256 expiredPeriodInvocationId) =
            InvocationRegistry(registry).hasExpiredPeriodInvocation(orbId);
        if (hasExpiredInvocation) {
            (address _invoker,, uint256 _timestamp) =
                InvocationRegistry(registry).invocations(orbId, expiredPeriodInvocationId);
            // within 2 response periods since that invocation
            bool _isPledgeClaimable =
                block.timestamp < _timestamp + (2 * InvocationRegistry(registry).invocationPeriod(orbId));
            bool canClaim = claimer_ == _invoker || claimer_ == address(0);
            return _isPledgeClaimable && canClaim;
        }
        return false;
    }

    function canPledge(uint256 orbId) public view returns (bool) {
        return !canClaimPledge(orbId, address(0)) && InvocationRegistry(registry).expiredPeriodInvocation(orbId) == 0;
    }

    function isPledgeRetrievable(uint256 orbId) public view returns (bool) {
        // not claimable and not active
        return !canClaimPledge(orbId, address(0)) && !isPledgeActive(orbId);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: TOKEN LOCKING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function lockERC721Token(uint256 orbId, address tokenContract_, uint256 tokenId_)
        external
        virtual
        onlyCreator(orbId)
    {
        // require that locekdUntil is in the future
    }

    /// @notice  Allows re-swearing of the Orb Oath and set a new `honoredUntil` date. This function can only be called
    ///          by the Orb creator when the Orb is in their control. With `swearOath()`, `honoredUntil` date can be
    ///          decreased, unlike with the `extendHonoredUntil()` function.
    /// @dev     Emits `OathSwearing`.
    ///          V2 changes to allow re-swearing even during Keeper control, if Oath has expired, and moves
    ///          `responsePeriod` setting to `setInvocationParameters()`.
    /// @param   orbId        Orb id
    /// @param   tokenContract_ Address of the ERC-721 token contract.
    /// @param   tokenId_      ID of the ERC-721 token.
    /// @param   pledgedUntil_    Date until which the Orb creator will honor the Oath for the Orb keeper.
    function lockERC721TokenUntil(uint256 orbId, address tokenContract_, uint256 tokenId_, uint256 pledgedUntil_)
        external
        virtual
        onlyCreator(orbId)
    {
        pledgedUntil[orbId] = pledgedUntil_;
        emit ERC721TokenPledge(orbId, tokenContract_, tokenId_, pledgedUntil_);
    }

    /// @notice  Allows the Orb creator to extend the `honoredUntil` date. This function can be called by the Orb
    ///          creator anytime and only allows extending the `honoredUntil` date.
    /// @dev     Emits `HonoredUntilUpdate`.
    /// @param   newPledgedUntil  Date until which the Orb creator will honor the Oath for the Orb keeper. Must be
    ///                           greater than the current `honoredUntil` date.
    function extendPledgedUntil(uint256 orbId, uint256 newPledgedUntil) external virtual onlyCreator(orbId) {
        uint256 previousPledgedUntil = pledgedUntil[orbId];
        if (newPledgedUntil < previousPledgedUntil) {
            revert PledgedUntilNotDecreasable();
        }
        pledgedUntil[orbId] = newPledgedUntil;
        emit PledgedUntilUpdate(orbId, previousPledgedUntil, newPledgedUntil);
    }

    function _transferPledgeTo(uint256 orbId, address newOwner) internal virtual {
        uint256 _pledgedNativeTokens = pledgedNativeTokens[orbId];
        ERC20Pledge memory _pledgedERC20Tokens = pledgedERC20Tokens[orbId];
        ERC721Pledge memory _pledgedERC721Token = pledgedERC721Token[orbId];
        if (pledgedNativeTokens[orbId] > 0) {
            pledgedNativeTokens[orbId] = 0;
        }
        if (pledgedERC20Tokens[orbId].contractAddress != address(0)) {
            pledgedERC20Tokens[orbId] = ERC20Pledge(address(0), 0);
        }
        if (pledgedERC721Token[orbId].contractAddress != address(0)) {
            pledgedERC721Token[orbId] = ERC721Pledge(address(0), 0);
            // we are not using safeTransferFrom here, because we are not sure if the new owner is a contract
            // and if it has implemented onERC721Received. It means NFT can be lost, but it is more important to
            // enabled forced pledge claiming.
        }

        if (_pledgedERC721Token.contractAddress != address(0)) {
            IERC721(_pledgedERC721Token.contractAddress).safeTransferFrom(
                address(this), newOwner, _pledgedERC721Token.tokenId
            );
        }
        if (_pledgedERC20Tokens.contractAddress != address(0)) {
            IERC20(_pledgedERC20Tokens.contractAddress).transfer(newOwner, _pledgedERC20Tokens.tokenAmount);
        }
        if (_pledgedNativeTokens > 0) {
            Address.sendValue(payable(newOwner), _pledgedNativeTokens);
        }
    }

    function retrievePledge(uint256 orbId) external virtual onlyCreator(orbId) {
        if (isPledgeRetrievable(orbId)) {
            _transferPledgeTo(orbId, _msgSender());
        }
        emit PledgeRetrieved(orbId, _msgSender());
    }

    function claimPledge(uint256 orbId) external virtual {
        if (canClaimPledge(orbId, _msgSender())) {
            (, uint256 expiredPeriodInvocationId) = InvocationRegistry(registry).hasExpiredPeriodInvocation(orbId);
            (address _invoker,,) = InvocationRegistry(registry).invocations(orbId, expiredPeriodInvocationId);

            if (_msgSender() != _invoker) {
                revert NotInvoker();
            }

            _transferPledgeTo(orbId, _invoker);
            InvocationRegistry(registry).resetExpiredPeriodInvocation(orbId);

            emit PledgeClaimed(orbId, _invoker);
        }
    }

    function resetExpiredPeriodInvocation(uint256 orbId) external virtual {
        // TODO Pledge must not be claimable
        // TODO require that claiming window is over and does not have an expired period invocation apart from recorded
        // maybe same as "isCreatorControlled"
        InvocationRegistry(registry).resetExpiredPeriodInvocation(orbId);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: UPGRADING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Returns the version of the Orb. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbVersion  Version of the Orb.
    function version() public pure virtual returns (uint256) {
        return _VERSION;
    }

    /// @dev  Authorizes owner address to upgrade the contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address newImplementation_) internal virtual override onlyOwner {}
}

// TODOs:
// - indicate if discovery is initial or rediscovery
// - discovery running check
// - admin, upgrade functions
// - expose is creator controlled logic
// - establish is deadline missed logic

// - everything about token locking
// - documentation
//   - first, for myself: to understand when all actions can be taken
//   - particularly token and settings related
