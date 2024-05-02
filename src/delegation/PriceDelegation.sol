// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {DelegationMethod} from "./DelegationMethod.sol";
import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";

contract PriceDelegation is DelegationMethod, OwnableUpgradeable, UUPSUpgradeable {
    // Custom Events
    event DelegationPurchase(uint256 indexed orbId, address indexed purchaser, uint256 indexed price);
    event PriceDelegationParametersUpdate(uint256 orbId, uint256 indexed newPrice);

    // Custom Errors
    error IncorrectPrice(uint256 fundsProvided, uint256 price);
    error PriceNotSet();

    /// Version. Value: 1.
    uint256 private constant _VERSION = 1;

    // Custom Storage
    /// Delegation price for each Orb
    mapping(uint256 orbId => uint256) public price;
    mapping(uint256 orbId => bool) public active;

    mapping(uint256 orbId => mapping(address user => uint256)) public fundsOf;

    // all variables are in good initial condition
    // solhint-disable-next-line no-empty-blocks
    function initializeOrb(uint256 orbId) public override onlyInvocationRegistry {}

    function isActive(uint256 orbId) public view virtual override returns (bool) {
        return active[orbId] && price[orbId] > 0;
    }

    function isCancelable(uint256 orbId) public view virtual override returns (bool) {
        return active[orbId] && delegateAddress[orbId] != address(0);
    }

    function isFinalizable(uint256 orbId) public view virtual override returns (bool) {
        return delegateAddress[orbId] != address(0);
    }

    function setPrice(uint256 orbId, uint256 price_) external virtual onlyKeeper(orbId) onlyInactive(orbId) {
        _setPrice(orbId, price_);
    }

    function _setPrice(uint256 orbId, uint256 price_) internal virtual {
        if (price[orbId] == 0) {
            revert InvalidPrice(price_);
        }
        price[orbId] = price_;
        emit PriceDelegationParametersUpdate(orbId, price_);
    }

    function _reset(uint256 orbId) internal virtual {
        active[orbId] = false;
        delegateAddress[orbId] = address(0);
        delegationHash[orbId] = 0;
        delegationExpiration[orbId] = 0;
    }

    function purchase(uint256 orbId, bytes32 delegationHash_) external payable virtual onlyActive(orbId) {
        if (delegateAddress[orbId] != address(0)) {
            revert Delegated();
        }
        if (msg.value != price[orbId]) {
            revert IncorrectPrice(msg.value, price[orbId]);
        }

        fundsOf[orbId][_msgSender()] += price[orbId];
        delegateAddress[orbId] = _msgSender();
        delegationHash[orbId] = delegationHash_;
        delegationExpiration[orbId] = block.timestamp + delegationExpiration[orbId];

        emit DelegationPurchase(orbId, _msgSender(), price[orbId]);
        if (invocations.isInvokable(orbId)) {
            finalize(orbId);
        }
    }

    function start(uint256 orbId) public virtual override onlyKeeper(orbId) onlyInactive(orbId) {
        if (price[orbId] == 0) {
            revert PriceNotSet();
        }

        super.start(orbId);
        active[orbId] = true;
        // setting duration, but not expiration timestamp — to be set on purchase
        delegationExpiration[orbId] = _expirationDuration(orbId);

        emit DelegationStart(orbId, block.timestamp, 0);
    }

    function startWithPrice(uint256 orbId, uint256 price_) public virtual onlyKeeper(orbId) onlyInactive(orbId) {
        super.start(orbId);
        _setPrice(orbId, price_);
        active[orbId] = true;
        emit DelegationStart(orbId, block.timestamp, 0);
    }

    function cancel(uint256 orbId) public virtual override onlyKeeper(orbId) onlyCancelable(orbId) {
        if (active[orbId] == false) {
            revert DelegationNotStarted();
        }
        if (delegateAddress[orbId] != address(0)) {
            revert Delegated();
        }

        emit DelegationCancellation(orbId);
        _reset(orbId);
    }

    function finalize(uint256 orbId) public virtual override onlyFinalizable(orbId) {
        uint256 _price = price[orbId];
        if (active[orbId] == false) {
            revert DelegationNotStarted();
        }

        address delegate = delegateAddress[orbId];

        fundsOf[orbId][delegate] -= _price;
        _addEarnings(ownership.keeper(orbId), _price);

        invocations.invokeDelegated(orbId, delegate, delegationHash[orbId]);

        emit DelegationFinalization(orbId, delegate, _price);
        _reset(orbId);
    }

    function withdrawAll(uint256 orbId) external virtual {
        _withdrawAll(_msgSender(), orbId);
    }

    function _withdrawAll(address user, uint256 orbId) public virtual {
        uint256 funds = fundsOf[orbId][user];
        if (funds == 0) {
            revert NoFundsAvailable();
        }
        if (user == delegateAddress[orbId]) {
            if (block.timestamp < delegationExpiration[orbId]) {
                revert DelegationActive();
            }
            _reset(orbId);
        }

        fundsOf[orbId][user] = 0;
        Address.sendValue(payable(user), funds);

        emit Withdrawal(orbId, user, funds);
    }

    /// @dev  Authorizes owner address to upgrade the contract.
    // solhint-disable no-empty-blocks
    function _authorizeUpgrade(address) internal virtual override onlyOwner {}

    /// @dev     Returns the version of the English Auction Allocation contract.
    /// @return  versionNumber  Version of the contract.
    function version() public view virtual override returns (uint256 versionNumber) {
        return _VERSION;
    }
}
