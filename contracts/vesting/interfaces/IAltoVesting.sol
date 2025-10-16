// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct VestingInfo {
    uint256 startAt; // The start time of the vesting
    uint256 vestingDuration; // The duration of the vesting
    uint256 totalVestingAmount; // The total amount of that is to be vested
}

interface IAltoVesting {
    error AltoVestingInvalidInput();
    error AltoVestingUnauthorized();
    error AltoVestingNotPaused();
    error AltoVestingAlreadyClaimed();
    error AltoVestingNotUpdatable();

    event ClaimVesting(address indexed caller, address indexed onBehalf, uint256 amount);

    event RescueVestingTokens(address indexed token, address indexed to, uint256 amount);

    /// @notice Claims the vested amount as per vesting schedule
    /// @param onBehalf The user's address that's eligible for the vesting
    /// @param vestingInfo The vesting information
    /// @param proof The merkle proof that validates this claim
    /// @return amount The amount of vested tokens claimed
    function claim(address onBehalf, VestingInfo memory vestingInfo, bytes32[] calldata proof)
        external
        returns (uint256 amount);

    /// @notice Withdraws tokens from the contract
    /// @dev It is used primarily to withdraw the vesting tokens in case of contract change or other reasons.
    /// @dev Contract has to be paused before calling this function.
    function rescueVestingTokens() external;

    /// @notice The `amount` of `vestingToken` already claimed by `user`.
    /// @param user The user's address
    /// @return The amount of `vestingToken` already claimed by `user`
    function claimed(address user) external view returns (uint256);

    /// @notice flag that indicates whether the vesting terms can be updated
    /// @return whether the vesting terms can be updated
    function IS_VESTING_UPDATABLE() external view returns (bool);

    /// @notice The address of the vesting token
    /// @return vesting token address
    function VESTING_TOKEN() external view returns (address);
}
