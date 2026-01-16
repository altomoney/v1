// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AddressChange
/// @notice Allows users to register a one-time address change
contract AddressChange is Ownable {
    error ZeroAddress();
    error AlreadyChanged();
    error Stopped();

    event AddressChanged(address indexed oldAddress, address indexed newAddress);
    event AddressChangedByOwner(address indexed oldAddress, address indexed newAddress);
    event ContractStopped();

    /// @notice Maps original address to new address
    mapping(address => address) public addressChanges;

    /// @notice Whether the contract is stopped
    bool public stopped;

    constructor() Ownable(msg.sender) {}

    /// @notice Allows a user to change their address (one-time only)
    /// @param newAddress The new address to map to
    function changeAddress(address newAddress) external {
        if (stopped) revert Stopped();
        if (newAddress == address(0)) revert ZeroAddress();
        if (addressChanges[msg.sender] != address(0)) revert AlreadyChanged();

        addressChanges[msg.sender] = newAddress;

        emit AddressChanged(msg.sender, newAddress);
    }

    /// @notice Allows owner to change an address on behalf of a user
    /// @param oldAddress The original address
    /// @param newAddress The new address to map to
    function changeAddressByOwner(address oldAddress, address newAddress) external onlyOwner {
        if (oldAddress == address(0) || newAddress == address(0)) revert ZeroAddress();

        addressChanges[oldAddress] = newAddress;

        emit AddressChangedByOwner(oldAddress, newAddress);
    }

    /// @notice Stops the contract permanently
    function stop() external onlyOwner {
        stopped = true;
        emit ContractStopped();
    }
}
