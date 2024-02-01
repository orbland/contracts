// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";

contract Conveyor is OwnableUpgradeable {
    event Forwarded(address, address, uint256);
    event PaymentReleased(address, uint256);
    event ERC20PaymentReleased(IERC20, address, uint256);
    event DestinationChanged(address);

    address payable public destination;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address payable _destination) public initializer {
        transferOwnership(_owner);
        destination = _destination;
    }

    receive() external payable {
        Address.sendValue(destination, msg.value);
        emit Forwarded(msg.sender, destination, msg.value);
    }

    function release() public {
        uint256 payment = address(this).balance;
        Address.sendValue(destination, payment);
        emit PaymentReleased(destination, payment);
    }

    function release(IERC20 token) public {
        uint256 payment = token.balanceOf(address(this));
        SafeERC20.safeTransfer(token, destination, payment);
        emit ERC20PaymentReleased(token, destination, payment);
    }

    function setDestination(address payable _destination) public onlyOwner {
        destination = _destination;
        emit DestinationChanged(_destination);
    }
}
