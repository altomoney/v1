// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPausable {
    event PauserUpdated(address indexed pauser, bytes32 pauseType, bool status);
    event Paused(address indexed pauser, bytes32 pauseType, bool paused);

    error Unauthorized(address pauser, bytes32 pauseType);
    error IsPaused(bytes32 pauseType);
    error StateNotChanged(bytes32 pauseType, bool currentState, bool newState);

    function paused(bytes32 pauseType) external view returns (bool);
    function setPauser(address pauser, bytes32 pauseType, bool status) external;
    function pause(bytes32 pauseType, bool _paused) external;
}
