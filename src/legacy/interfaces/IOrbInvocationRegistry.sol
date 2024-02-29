// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC165} from "../../../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

interface IOrbInvocationRegistry is IERC165 {
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function invocations(address orb, uint256 invocationId)
        external
        view
        returns (address invoker, bytes32 contentHash, uint256 timestamp);
    function invocationCount(address orb) external view returns (uint256);

    function responses(address orb, uint256 invocationId)
        external
        view
        returns (bytes32 contentHash, uint256 timestamp);
    function responseFlagged(address orb, uint256 invocationId) external view returns (bool);
    function flaggedResponsesCount(address orb) external view returns (uint256);

    function authorizedContracts(address contractAddress) external view returns (bool);

    function version() external view returns (uint256);

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //  FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function invokeWithCleartext(address orb, string memory cleartext) external;
    function invokeWithCleartextAndCall(
        address orb,
        string memory cleartext,
        address addressToCall,
        bytes memory dataToCall
    ) external;
    function invokeWithHash(address orb, bytes32 contentHash) external;
    function invokeWithHashAndCall(address orb, bytes32 contentHash, address addressToCall, bytes memory dataToCall)
        external;
    function respond(address orb, uint256 invocationId, bytes32 contentHash) external;
    function flagResponse(address orb, uint256 invocationId) external;
}
