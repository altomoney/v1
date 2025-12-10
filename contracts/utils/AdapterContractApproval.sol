// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";

/// @title AdapterContractApproval
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice A contract that allows for approval of contracts to be used in the adapter.
/// @dev This was created as a separate contract to easily distinguish differences
/// between Morpho's GeneralAdapter1 (https://github.com/morpho-org/bundler3) and Alto's AltoAdapter.
abstract contract AdapterContractApproval is AltoOwnable2Step {
    /// @notice The error thrown when a contract is not approved to be used in the adapter.
    error AdapterContractApprovalUnapprovedContract();

    /// @notice The error thrown when the input is invalid.
    error AdapterContractApprovalInvalidInput();

    event AdapterContractApproved(address indexed contractAddress);
    event AdapterContractRevoked(address indexed contractAddress);

    /// @notice The mapping of the approved contracts.
    /// @dev address => is approved
    mapping(address => bool) public isApprovedContract;

    /// @notice The modifier to check if a contract is approved to be used in the adapter.
    /// @param contractAddress The address of the contract to check.
    modifier onlyApprovedContract(address contractAddress) {
        require(isApprovedContract[contractAddress], AdapterContractApprovalUnapprovedContract());
        _;
    }

    constructor(address _owner) Ownable(_owner) {}

    /// @notice The function to approve a contract to be used in the adapter.
    /// @param contractAddress The address of the contract to approve.
    function approveContract(address contractAddress) external onlyOwner {
        if (contractAddress == address(0) || isApprovedContract[contractAddress]) {
            revert AdapterContractApprovalInvalidInput();
        }

        isApprovedContract[contractAddress] = true;

        emit AdapterContractApproved(contractAddress);
    }

    /// @notice The function to revoke a contract's approval to be used in the adapter.
    /// @param contractAddress The address of the contract to revoke approval for.
    function revokeContract(address contractAddress) external onlyOwner {
        if (contractAddress == address(0) || !isApprovedContract[contractAddress]) {
            revert AdapterContractApprovalInvalidInput();
        }

        isApprovedContract[contractAddress] = false;

        emit AdapterContractRevoked(contractAddress);
    }
}
