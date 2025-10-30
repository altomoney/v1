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

struct FlashFee {
    /// @notice The minimum flash fee in percent represented as MATH_PRECISION
    /// @dev This is the fee charged when the amount is flash minted is 0
    /// @dev minFlashFee does not have to be smaller than maxFlashFee
    uint128 minFlashFee;
    /// @notice The maximum flash fee in percent represented as MATH_PRECISION
    /// @dev This is the fee charged when the amount is flash minted is mint cap
    /// @dev maxFlashFee does not have to be greater than minFlashFee
    uint128 maxFlashFee;
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

    /// @notice Thrown when the amount exceeds the flash mint cap
    error DUSDExceededFlashMintCap();

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

    /// @notice Event emitted when the flash fee receiver is set
    /// @param _oldFeeReceiver The old flash fee receiver
    /// @param _newFeeReceiver The new flash fee receiver
    event SetFlashFeeReceiver(address indexed _oldFeeReceiver, address indexed _newFeeReceiver);

    /// @notice Event emitted when the flash fee is set
    /// @param _oldFlashFee The old flash fee struct
    /// @param _newFlashFee The new flash fee struct
    event SetFlashFee(FlashFee _oldFlashFee, FlashFee _newFlashFee);

    /// @notice Event emitted when the flash mint cap is set
    /// @param _oldCap The old flash mint cap
    /// @param _newCap The new flash mint cap
    event SetFlashMintCap(uint256 indexed _oldCap, uint256 indexed _newCap);

    /// @notice Returns the flash fee receiver
    /// @return The flash fee receiver
    function flashFeeReceiver() external view returns (address);

    /// @notice returns the min and max flash fee
    /// @return minFlashFee The minimum flash fee in percent represented as MATH_PRECISION
    /// @return maxFlashFee The maximum flash fee in percent represented as MATH_PRECISION
    function flashFee() external view returns (uint128 minFlashFee, uint128 maxFlashFee);

    /// @notice The flash mint cap is the maximum amount of DUSD that can be flash minted at one time
    /// @return The flash mint cap
    function flashMintCap() external view returns (uint256);

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

    /// @notice Sets the flash mint cap
    /// @param _newFlashMintCap The flash mint cap
    function setFlashMintCap(uint256 _newFlashMintCap) external;

    /// @notice Sets the flash fee is a percentage charged on the amount of flash loan
    /// @param _newFlashFee The flash fee struct
    /// @dev minFlashFee and maxFlashFee represent start and end of the flash fee curve
    /// @dev the flash fee curve is a linear interpolation between minFlashFee and maxFlashFee
    /// @dev minFlashFee does not have to be smaller than maxFlashFee
    /// @dev maxFlashFee does not have to be greater than minFlashFee
    /// @dev setting minFlashFee and maxFlashFee to the same value will result in a flat fee
    function setFlashFee(FlashFee calldata _newFlashFee) external;

    /// @notice Sets the flash fee receiver
    /// @param _newFlashFeeReceiver The flash fee receiver
    function setFlashFeeReceiver(address _newFlashFeeReceiver) external;

    /// @notice Mints DUSD to an address
    /// @param _to The address to mint DUSD to
    /// @param _amount The amount of DUSD to mint
    function mint(address _to, uint256 _amount) external;

    /// @notice Burns DUSD from an address
    /// @param _from The address to burn DUSD from
    /// @param _amount The amount of DUSD to burn
    function burn(address _from, uint256 _amount) external;
}
