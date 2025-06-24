// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev This mock is used to test protocol ownership via smart contract (safe multisig, governance executor)
contract OwnerContract {
    function delegateCall(address target, bytes memory data) public returns (bytes memory) {
        (bool success, bytes memory returnData) = target.delegatecall(data);
        require(success, "Delegate call failed");
        return returnData;
    }

    function call(address target, bytes memory data) public {
        (bool success, bytes memory returnData) = target.call(data);
        require(success, "Call failed");
    }
}
