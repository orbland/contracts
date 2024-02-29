// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC1967Proxy} from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Clones} from "../../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";

import {PaymentSplitter} from "./CustomPaymentSplitter.sol";
import {OrbPond} from "./OrbPond.sol";
import {IOwnershipTransferrable} from "./IOwnershipTransferrable.sol";
import {Orb} from "./Orb.sol";

/// @title   Orb Pond - The Orb Factory
/// @author  Jonas Lekevicius
/// @notice  Orbs come from a Pond. The Orb Pond is used to efficiently create new Orbs, and track “official” Orbs,
///          supported by the Orb Land system. The Orb Pond is also used to register allowed Orb upgrade
///          implementations, and keeps a reference to an Orb Invocation Registry used by all Orbs created with this
///          Orb Pond.
/// @dev     Uses `Ownable`'s `owner()` to limit the creation of new Orbs to the administrator and for upgrades.
///          V2 adds these changes:
///          - `orbInitialVersion` field for new Orb creation and `setOrbInitialVersion()` function to set it. This
///            allows to specify which version of the Orb implementation to use for new Orbs.
///          - `beneficiaryWithdrawalAddresses` mapping to authorize addresses to be used as
///            `beneficiaryWithdrawalAddress` on Orbs, `authorizeWithdrawalAddress()` function to set it, and
///            `beneficiaryWithdrawalAddressPermitted()` function to check if address is authorized.
/// @custom:security-contact security@orb.land
contract OrbPondV2 is OrbPond {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  EVENTS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event OrbInitialVersionUpdate(uint256 previousInitialVersion, uint256 indexed newInitialVersion);
    event WithdrawalAddressAuthorization(address indexed withdrawalAddress, bool indexed authorized);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  STORAGE
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// Orb Pond version. Value: 2.
    uint256 private constant _VERSION = 2;

    /// New Orb version
    uint256 public orbInitialVersion;

    /// Addresses authorized to be used as beneficiaryWithdrawal address
    mapping(address withdrawalAddress => bool isPermitted) public beneficiaryWithdrawalAddresses;

    /// Gap used to prevent storage collisions.
    uint256[100] private __gap;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  INITIALIZER
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice  Reinitializes the contract with provided initial value for `orbInitialVersion`.
    /// @param   orbInitialVersion_  Registered Orb implementation version to be used for new Orbs.
    function initializeV2(uint256 orbInitialVersion_) public reinitializer(2) {
        orbInitialVersion = orbInitialVersion_;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS: ORB CREATION
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice  Creates a new Orb together with a PaymentSplitter, and emits an event with the Orb's address.
    /// @param   payees_       Beneficiaries of the Orb's PaymentSplitter.
    /// @param   shares_       Shares of the Orb's PaymentSplitter.
    /// @param   name          Name of the Orb, used for display purposes. Suggestion: "NameOrb".
    /// @param   symbol        Symbol of the Orb, used for display purposes. Suggestion: "ORB".
    /// @param   tokenURI      Initial tokenURI of the Orb, used as part of ERC-721 tokenURI.
    function createOrb(
        address[] memory payees_,
        uint256[] memory shares_,
        string memory name,
        string memory symbol,
        string memory tokenURI
    ) external virtual override onlyOwner {
        address beneficiary = Clones.clone(paymentSplitterImplementation);
        PaymentSplitter(payable(beneficiary)).initialize(payees_, shares_);

        bytes memory initializeCalldata = abi.encodeCall(Orb.initialize, (beneficiary, name, symbol, tokenURI));
        ERC1967Proxy proxy = new ERC1967Proxy(versions[orbInitialVersion], initializeCalldata);
        orbs[orbCount] = address(proxy);
        IOwnershipTransferrable(orbs[orbCount]).transferOwnership(msg.sender);

        emit OrbCreation(orbCount, address(proxy));

        orbCount++;
    }

    /// @notice  Sets the registered Orb implementation version to be used for new Orbs.
    /// @param   orbInitialVersion_  Registered Orb implementation version number to be used for new Orbs.
    function setOrbInitialVersion(uint256 orbInitialVersion_) external virtual onlyOwner {
        if (orbInitialVersion_ > latestVersion) {
            revert InvalidVersion();
        }
        uint256 previousInitialVersion = orbInitialVersion;
        orbInitialVersion = orbInitialVersion_;
        emit OrbInitialVersionUpdate(previousInitialVersion, orbInitialVersion_);
    }

    /// @notice  Returns the version of the Orb Pond. Internal constant `_VERSION` will be increased with each upgrade.
    /// @return  orbPondVersion  Version of the Orb Pond contract.
    function version() public view virtual override returns (uint256 orbPondVersion) {
        return _VERSION;
    }

    /// @notice Returns if address can be used as beneficiary withdrawal address on Orbs.
    /// @param beneficiaryWithdrawalAddress Address to check. Zero address is always permitted.
    function beneficiaryWithdrawalAddressPermitted(address beneficiaryWithdrawalAddress)
        external
        virtual
        returns (bool isBeneficiaryWithdrawalAddressPermitted)
    {
        return
            beneficiaryWithdrawalAddress == address(0) || beneficiaryWithdrawalAddresses[beneficiaryWithdrawalAddress];
    }

    /// @notice  Allows the owner to authorize permitted beneficiary withdrawal addresses.
    /// @param   addressToAuthorize  Address to authorize (likely contract).
    /// @param   authorizationValue  Boolean value to set the authorization to.
    function authorizeWithdrawalAddress(address addressToAuthorize, bool authorizationValue)
        external
        virtual
        onlyOwner
    {
        beneficiaryWithdrawalAddresses[addressToAuthorize] = authorizationValue;
        emit WithdrawalAddressAuthorization(addressToAuthorize, authorizationValue);
    }
}
