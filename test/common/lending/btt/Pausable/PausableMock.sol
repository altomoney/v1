// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Pausable} from "@alto/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title PausableMock
/// @notice Mock contract for testing Pausable functionality
contract PausableMock is Ownable, Pausable {
    constructor(address owner) Ownable(owner) {}

    /// @notice Test function to verify whenNot modifier
    /// @param pauseType The pause type to check
    function testWhenNotModifier(bytes32 pauseType) external view whenNot(pauseType) returns (bool) {
        return true;
    }

    /// @notice Test function to verify onlyPauser modifier
    /// @param pauseType The pause type to check
    function testOnlyPauserModifier(bytes32 pauseType) external view onlyPauser(pauseType) returns (bool) {
        return true;
    }

    function setPauser(address pauser, bytes32 pauseType, bool status) public override(Pausable) onlyOwner {
        _setPauser(pauser, pauseType, status);
    }
}
