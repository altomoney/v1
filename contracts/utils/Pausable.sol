// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPausable} from "./interfaces/IPausable.sol";

abstract contract Pausable is IPausable {
    mapping(bytes32 => bool) public paused;
    mapping(address => mapping(bytes32 => bool)) public pausers;

    function setPauser(address pauser, bytes32 pauseType, bool status) external virtual;

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
        _onPause(pauseType, _paused);
        if (paused[pauseType] == _paused) {
            revert StateNotChanged(pauseType, paused[pauseType], _paused);
        }
        paused[pauseType] = _paused;
        emit Paused(msg.sender, pauseType, _paused);
    }

    /// @notice Virtual function to allow for custom logic when pausing/unpausing
    /// @param pauseType The type of pause
    /// @param _paused The new paused state
    /// @dev This function is called before the pause/unpause is applied to the paused state.
    function _onPause(bytes32 pauseType, bool _paused) internal virtual {}

    /// @param pauser The address of the pauser
    /// @param pauseType The type of pause
    /// @param status The new status of the pauser
    function _setPauser(address pauser, bytes32 pauseType, bool status) internal {
        pausers[pauser][pauseType] = status;
        emit PauserUpdated(pauser, pauseType, status);
    }
}
