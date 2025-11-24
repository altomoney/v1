// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IStableTokenFacilitator} from "@alto/usm/interfaces/IStableTokenFacilitator.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";

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

/// @title IDUSDFlashMinter
/// @notice Defines the behavior of the DUSD Flash Minter
/// @author Pearl Labs
/// @author Adapted from Aave (https://github.com/aave/gho-core/)
interface IDUSDFlashMinter is IERC3156FlashLender, IStableTokenFacilitator {
    /// @notice Event emitted when the flash mint fee is updated
    /// @param oldFlashMintFee The old flash mint fee struct
    /// @param newFlashMintFee The new flash mint fee struct
    event SetFlashMintFee(FlashFee oldFlashMintFee, FlashFee newFlashMintFee);

    /// @notice Event emitted when a FlashMint occurs
    /// @param receiver The receiver of the FlashMinted tokens (it is also the receiver of the callback)
    /// @param initiator The address initiating the FlashMint
    /// @param asset The asset being FlashMinted. Always DUSD.
    /// @param amount The principal being FlashMinted
    /// @param fee The fee returned on top of the principal
    event FlashMint(
        address indexed receiver, address indexed initiator, address asset, uint256 indexed amount, uint256 fee
    );

    /// @notice Returns the required return value for a successful flash mint callback
    /// @return The keccak256 hash of 'ERC3156FlashBorrower.onFlashLoan', which must be returned by the callback
    function CALLBACK_SUCCESS() external view returns (bytes32);

    /// @notice Returns the address of the DUSD token contract
    /// @return The address of the DUSD token contract
    function DUSD() external view returns (IDUSD);

    /// @notice returns the min and max flash fee
    /// @return minFlashFee The minimum flash fee in percent represented as MATH_PRECISION
    /// @return maxFlashFee The maximum flash fee in percent represented as MATH_PRECISION
    function flashMintFee() external view returns (uint128 minFlashFee, uint128 maxFlashFee);

    /// @notice Updates the flash mint fee
    /// @param _newFlashMintFee The new flash mint fee struct
    function updateFlashMintFee(FlashFee memory _newFlashMintFee) external;

    /// @notice Returns the flash mint fee
    /// @return The flash mint fee struct
    function getFlashMintFee() external view returns (FlashFee memory);
}
