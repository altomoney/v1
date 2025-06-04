// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPausable} from "./interfaces/IPausable.sol";

abstract contract Pausable is IPausable, Ownable {
    mapping(bytes32 => bool) public paused;
    mapping(address => mapping(bytes32 => bool)) public pausers;

    /// @notice Sets a pauser's status
    /// @param pauser The address of the pauser
    /// @param pauseType The type of pause
    /// @param status The new status of the pauser
    function setPauser(address pauser, bytes32 pauseType, bool status) public onlyOwner {
        pausers[pauser][pauseType] = status;
        emit PauserUpdated(pauser, pauseType, status);
    }

    /// @notice Modifier to check if the caller is a pauser
    modifier onlyPauser(bytes32 pauseType) {
        if (!pausers[msg.sender][pauseType]) revert Unauthorized(msg.sender, pauseType);
        _;
    }

    /// @notice Modifier to check if the market is not paused
    modifier whenNot(bytes32 pauseType) {
        if (paused[pauseType]) revert IsPaused(pauseType);
        _;
    }

    /// @notice Pauses or unpauses the market
    /// @param _paused The new paused state
    function pause(bytes32 pauseType, bool _paused) external onlyPauser(pauseType) {
        paused[pauseType] = _paused;
        emit Paused(msg.sender, pauseType, _paused);
    }
}
