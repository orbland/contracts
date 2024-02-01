// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ClonesUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/ClonesUpgradeable.sol";

import {Conveyor} from "./Conveyor.sol";

contract ConveyorCrafter {
    event ConveyorCreated(address indexed conveyorAddress);

    /// The address of the PaymentSplitter implementation contract, used to create new PaymentSplitters.
    address public immutable conveyorImplementation;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address conveyorImplementation_) {
        conveyorImplementation = conveyorImplementation_;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ORB CREATION
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Creates a new Orb together with a PaymentSplitter, and emits an event with the Orb's address.
    /// @param   initialDestination  Initial destination of the Conveyor.
    function createConveyor(address payable initialDestination) external {
        address conveyor = ClonesUpgradeable.clone(conveyorImplementation);
        Conveyor(payable(conveyor)).initialize(msg.sender, initialDestination);
        emit ConveyorCreated(conveyor);
    }
}
