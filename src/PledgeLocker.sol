// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {InvocationRegistry} from "./InvocationRegistry.sol";
import {OrbSystem} from "./OrbSystem.sol";

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

    event NativeTokenPledge(uint256 indexed orbId, uint256 tokenAmount, uint256 totalPledged);
    event ERC20TokenPledge(
        uint256 indexed orbId, address indexed tokenContract, uint256 tokenAmount, uint256 totalPledged
    );
    event ERC721TokenPledge(uint256 indexed orbId, address indexed tokenContract, uint256 indexed tokenId);
    event PledgedUntilUpdate(uint256 indexed orbId, uint256 indexed newPledgedUntil);
    event PledgeClaimed(uint256 indexed orbId, address indexed claimer);
    event PledgeRetrieved(uint256 indexed orbId, address indexed retriever);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  ERRORS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // Orb Parameter Errors
    error PledgedUntilNotDecreasable();
    error TokenStillPledged();
    error NotInvoker();
    error PledgedUntilInThePast();
    error NotCreator();
    error InsufficientPledge();
    error NoPledge();
    error NoClaimablePledge();
    error NotRetrievable();

    error NotCreatorControlled();

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // CONSTANTS

    /// Orb version. Value: 1.
    uint256 private constant _VERSION = 1;

    // STATE

    /// Addresses of all system contracts
    OrbSystem public os;

    /// Honored Until: timestamp until which the Orb Oath is honored for the keeper.
    mapping(uint256 orbId => uint256 pledgedUntil) public pledgedUntil;

    /// Pledged chain native tokens (likely ETH)
    mapping(uint256 orbId => uint256) public pledgedNativeTokens;
    /// Pledged ERC-20 token (contract address and amount).
    mapping(uint256 orbId => ERC20Pledge) public pledgedERC20Tokens;
    /// Pledged ERC-721 token. Orb creator can lock an ERC-721 token in the Orb, guaranteeing timely responses.
    mapping(uint256 orbId => ERC721Pledge) public pledgedERC721Token;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER AND INTERFACE SUPPORT
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initalize(address os_) external initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();

        os = OrbSystem(os_);
    }

    modifier onlyCreator(uint256 orbId) {
        if (_msgSender() != os.ownership().creator(orbId)) {
            revert NotCreator();
        }
        _;
    }

    modifier onlyActivePledge(uint256 orbId) {
        if (!_isActive(orbId)) {
            revert PledgedUntilInThePast();
        }
        _;
    }

    modifier onlyCreatorControlled(uint256 orbId) {
        if (os.isCreatorControlled(orbId) == false) {
            revert NotCreatorControlled();
        }
        _;
    }

    function hasPledge(uint256 orbId) external view returns (bool) {
        return _hasPledge(orbId);
    }

    function hasClaimablePledge(uint256 orbId) external view returns (bool) {
        return _hasClaimablePledge(orbId);
    }

    function _isActive(uint256 orbId) internal view returns (bool) {
        return pledgedUntil[orbId] > block.timestamp;
    }

    function _hasPledge(uint256 orbId) internal view returns (bool) {
        return pledgedNativeTokens[orbId] > 0 || pledgedERC20Tokens[orbId].contractAddress != address(0)
            || pledgedERC721Token[orbId].contractAddress != address(0);
    }

    function _isClaimable(uint256 orbId) internal view returns (bool) {
        InvocationRegistry _invocations = os.invocations();

        uint256 lastInvocationTime = _invocations.lastInvocationTime(orbId);
        // The invocation must have been made before "pledged until" date expired.
        // So, if made after, pledge is not claimable.
        // If pledgedUntil is 0, then this is an early return.
        if (lastInvocationTime > pledgedUntil[orbId]) {
            return false;
        }

        // There has to be a late response (either already made but late, or missing and late).
        // If there is no late response, pledge is not claimable.
        // Note that lastInvocationResponseWasLate gets reset after a new invocation is made, so we are not letting the
        // Keeper to invoke again before claiming the pledge.
        if (_invocations.hasLateResponse(orbId) == false) {
            return false;
        }

        uint256 invocationPeriod = _invocations.invocationPeriod(orbId);
        // Claiming window of one additional invocation period mustn’t have expired
        // (if invocation period is 7 days, then pledge is claimable on days 7th to 14th since invocation was made)
        if (block.timestamp > lastInvocationTime + invocationPeriod * 2) {
            return false;
        }

        // Let's claim that pledge!
        // Invoker / msgSender check is done in the claimPledge function
        return true;
    }

    function _hasClaimablePledge(uint256 orbId) internal view returns (bool) {
        return _isClaimable(orbId) && _hasPledge(orbId);
    }

    function _isPledgeable(uint256 orbId) internal view returns (bool) {
        return !_isClaimable(orbId) && _isActive(orbId);
    }

    function _isRetrievable(uint256 orbId) internal view returns (bool) {
        return !_isClaimable(orbId) && !_isActive(orbId);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: PLEDGING
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function pledgeNativeToken(uint256 orbId) external payable virtual onlyCreator(orbId) {
        _pledgeNativeToken(orbId);
    }

    function pledgeERC20Token(uint256 orbId, address tokenContract_, uint256 tokenAmount_)
        external
        virtual
        onlyCreator(orbId)
    {
        _pledgeERC20Token(orbId, tokenContract_, tokenAmount_);
    }

    function pledgeERC721Token(uint256 orbId, address tokenContract_, uint256 tokenId_)
        external
        virtual
        onlyCreator(orbId)
    {
        _pledgeERC721Token(orbId, tokenContract_, tokenId_);
    }

    function pledgeNativeTokenUntil(uint256 orbId, uint256 pledgedUntil_) external payable virtual onlyCreator(orbId) {
        _pledgeUntil(orbId, pledgedUntil_);
        _pledgeNativeToken(orbId);
    }

    function pledgeERC20TokenUntil(uint256 orbId, address tokenContract_, uint256 tokenAmount_, uint256 pledgedUntil_)
        external
        virtual
        onlyCreator(orbId)
    {
        _pledgeUntil(orbId, pledgedUntil_);
        _pledgeERC20Token(orbId, tokenContract_, tokenAmount_);
    }

    function pledgeERC721TokenUntil(uint256 orbId, address tokenContract_, uint256 tokenId_, uint256 pledgedUntil_)
        external
        virtual
        onlyCreator(orbId)
    {
        _pledgeUntil(orbId, pledgedUntil_);
        _pledgeERC721Token(orbId, tokenContract_, tokenId_);
    }

    function pledgeUntil(uint256 orbId, uint256 pledgedUntil_) external virtual onlyCreator(orbId) {
        _pledgeUntil(orbId, pledgedUntil_);
    }

    function _pledgeUntil(uint256 orbId, uint256 pledgedUntil_) internal virtual {
        if (os.isCreatorControlled(orbId)) {
            // If creator controlled, can be zero or anything in the future
            if (pledgedUntil_ > 0 && pledgedUntil_ < block.timestamp) {
                revert PledgedUntilInThePast();
            }
        } else {
            // If keeper controlled, must be greater than current
            if (pledgedUntil_ <= pledgedUntil[orbId]) {
                revert PledgedUntilNotDecreasable();
            }
        }

        pledgedUntil[orbId] = pledgedUntil_;
        emit PledgedUntilUpdate(orbId, pledgedUntil_);
    }

    function _pledgeNativeToken(uint256 orbId) internal virtual onlyActivePledge(orbId) {
        if (msg.value == 0) {
            revert InsufficientPledge();
        }

        pledgedNativeTokens[orbId] += msg.value;

        emit NativeTokenPledge(orbId, msg.value, pledgedNativeTokens[orbId]);
    }

    function _pledgeERC20Token(uint256 orbId, address tokenContract_, uint256 tokenAmount_)
        internal
        virtual
        onlyActivePledge(orbId)
    {
        address currentERC20Token = pledgedERC20Tokens[orbId].contractAddress;
        uint256 currentERC20TokenAmount = pledgedERC20Tokens[orbId].tokenAmount;

        if (currentERC20Token == tokenContract_ && currentERC20Token != address(0)) {
            // topping up the pledge
            IERC20(tokenContract_).transferFrom(_msgSender(), address(this), tokenAmount_);
            pledgedERC20Tokens[orbId] = ERC20Pledge(tokenContract_, tokenAmount_ + currentERC20TokenAmount);
            emit ERC20TokenPledge(orbId, tokenContract_, tokenAmount_, tokenAmount_ + currentERC20TokenAmount);
        } else if (currentERC20Token != address(0)) {
            // pledging a different token -- not supported
            revert TokenStillPledged();
        } else {
            // pledging fresh
            IERC20(tokenContract_).transferFrom(_msgSender(), address(this), tokenAmount_);
            pledgedERC20Tokens[orbId] = ERC20Pledge(tokenContract_, tokenAmount_);
            emit ERC20TokenPledge(orbId, tokenContract_, tokenAmount_, tokenAmount_);
        }
    }

    function _pledgeERC721Token(uint256 orbId, address tokenContract_, uint256 tokenId_)
        internal
        virtual
        onlyActivePledge(orbId)
    {
        if (pledgedERC721Token[orbId].contractAddress != address(0)) {
            revert TokenStillPledged();
        }

        IERC721(tokenContract_).transferFrom(_msgSender(), address(this), tokenId_);
        pledgedERC721Token[orbId] = ERC721Pledge(tokenContract_, tokenId_);

        emit ERC721TokenPledge(orbId, tokenContract_, tokenId_);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: RETRIEVING AND CLAIMING PLEDGES
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function retrievePledge(uint256 orbId) external virtual onlyCreator(orbId) {
        if (_isRetrievable(orbId) == false) {
            revert NotRetrievable();
        }
        if (_hasPledge(orbId) == false) {
            revert NoPledge();
        }

        _transferPledgeTo(orbId, _msgSender());

        emit PledgeRetrieved(orbId, _msgSender());
    }

    function claimPledge(uint256 orbId) external virtual {
        if (_hasClaimablePledge(orbId) == false) {
            revert NoClaimablePledge();
        }

        uint256 lastInvocationId = os.invocations().invocationCount(orbId);
        (address _invoker,,) = os.invocations().invocations(orbId, lastInvocationId);
        if (_msgSender() != _invoker) {
            revert NotInvoker();
        }

        _transferPledgeTo(orbId, _invoker);

        emit PledgeClaimed(orbId, _invoker);
    }

    function _transferPledgeTo(uint256 orbId, address newOwner_) internal virtual {
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
        }

        if (_pledgedERC721Token.contractAddress != address(0)) {
            IERC721(_pledgedERC721Token.contractAddress).transferFrom(
                address(this), newOwner_, _pledgedERC721Token.tokenId
            );
        }
        if (_pledgedERC20Tokens.contractAddress != address(0)) {
            IERC20(_pledgedERC20Tokens.contractAddress).transfer(newOwner_, _pledgedERC20Tokens.tokenAmount);
        }
        if (_pledgedNativeTokens > 0) {
            Address.sendValue(payable(newOwner_), _pledgedNativeTokens);
        }
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
