// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";

struct MinterConfig {
    /// @notice The amount of DUSD minted by the minter
    uint256 minted;
    /// @notice The ceiling of DUSD to be minted by the minter
    /// @dev This is the maximum amount of DUSD that can be minted by the minter
    uint256 ceiling;
}

/**
 * @title IDUSD Interface
 * @notice Interface for the DUSD stablecoin contract
 */
interface IDUSD is IOFT, IMintableERC20 {
    /// @notice Thrown when the caller is not authorized to perform the action
    error DUSDNotAuthorized();

    /// @notice Thrown when the input is invalid
    error DUSDInvalidInput();

    /// @notice Event emitted when the minter status is set
    /// @param _for The address of the minter
    /// @param _status The status of the minter
    event SetMinterStatus(address indexed _for, bool _status);

    /// @notice Event emitted when the minter ceiling is set
    /// @param _for The address of the minter
    /// @param _ceiling The ceiling of DUSD to be minted by the minter
    event SetMinterCeiling(address indexed _for, uint256 _ceiling);

    /// @notice Event emitted when the burner status is set
    /// @param _for The address of the burner
    /// @param _status The status of the burner
    event SetBurnerStatus(address indexed _for, bool _status);

    /// @notice Returns the allowed minter status for an address
    /// @param minter The address of the minter
    /// @return The allowed minter status
    function allowedMinter(address minter) external view returns (bool);

    /// @notice Returns the minter config for an address
    /// @param _for The address of the minter
    /// @return minted The amount of DUSD minted by the minter
    /// @return ceiling The ceiling of DUSD to be minted by the minter
    function minterConfig(address _for) external view returns (uint256 minted, uint256 ceiling);

    /// @notice Returns the allowed burner status for an address
    /// @param burner The address of the burner
    /// @return The allowed burner status
    function allowedBurner(address burner) external view returns (bool);

    /// @notice Sets the allowed minter status for an address
    /// @param _for The address of the minter
    /// @param _status The status of the minter
    function setMinterStatus(address _for, bool _status) external;

    /// @notice Sets the ceiling of DUSD to be minted by an address
    /// @param _for The address of the minter
    /// @param _ceiling The ceiling of DUSD to be minted by the minter
    /// @dev This is the maximum amount of DUSD that can be minted by the minter at the time
    function setMinterCeiling(address _for, uint256 _ceiling) external;

    /// @notice Sets the allowed burner status for an address
    /// @param _for The address of the burner
    /// @param _status The status of the burner
    function setBurnerStatus(address _for, bool _status) external;

    /// @notice Mints DUSD to an address
    /// @param _to The address to mint DUSD to
    /// @param _amount The amount of DUSD to mint
    function mint(address _to, uint256 _amount) external;

    /// @notice Burns DUSD from an address
    /// @param _from The address to burn DUSD from
    /// @param _amount The amount of DUSD to burn
    function burn(address _from, uint256 _amount) external;
}
