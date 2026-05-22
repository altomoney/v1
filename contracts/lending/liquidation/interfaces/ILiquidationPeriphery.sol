// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IAdvancedPermissionsUsm} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";

interface ILiquidationPeripheryErrors {
    /// @notice Thrown when the address passed is the zero address.
    error ZeroAddress();
    /// @notice Thrown when the input is invalid.
    error InvalidInput();
    /// @notice Thrown when the address passed is already set.
    error AlreadySet();
}

interface ILiquidationPeripheryEvents {
    /// @notice Emitted when the supported market is set.
    event SupportedMarketSet(address indexed market, bool isSupported);

    /// @notice Emitted when a liquidation occurs
    /// @param market The address of the market that was liquidated
    /// @param liquidator The address of the liquidator that performed the liquidation
    /// @param user The address of the user that was liquidated
    /// @param liquidatedCollateral The amount of collateral that was liquidated
    /// @param protocolFee The amount of protocol fee that was paid
    /// @param repaidBorrow The amount of borrow that was repaid
    event Liquidation(
        address indexed market,
        address indexed liquidator,
        address indexed user,
        uint256 liquidatedCollateral,
        uint256 protocolFee,
        uint256 repaidBorrow
    );

    /// @notice Emitted when the USM registry is set
    event UsmRegistrySet(address indexed oldUsmRegistry, address indexed newUsmRegistry);
}

interface ILiquidationPeripheryBase is ILiquidationPeripheryErrors, ILiquidationPeripheryEvents {
    /// @notice Liquidates a position in a market for specified borrower
    /// @param market The address of the market to liquidate the position in
    /// @param borrower The address of the borrower to liquidate the position for
    /// @param usm The address of the USM to use for the liquidation
    /// @param liquidationData Additional data for the liquidation
    /// @param liquidationPeripheryCallbackData Additional data to passed to the callback receiver of liquidation periphery contract
    function liquidate(
        address market,
        address borrower,
        address usm,
        bytes calldata liquidationData,
        bytes calldata liquidationPeripheryCallbackData
    ) external returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee);

    /// @notice Sets the supported market
    /// @param market The address of the market to set
    /// @param isSupported Whether the market is supported
    function setSupportedMarket(address market, bool isSupported) external;

    /// @notice Returns the address of the borrow token
    function BORROW_TOKEN() external view returns (address);

    /// @notice Returns the address of the supported markets
    function supportedMarkets(address market) external view returns (bool);

    /// @notice Returns the address of the USM registry
    function usmRegistry() external view returns (address);

    /// @notice Sets the USM registry
    /// @param _usmRegistry The address of the USM registry
    function setUsmRegistry(address _usmRegistry) external;

    /// @notice Recovers ERC20 tokens from the contract
    /// @param tokenAddress The address of the token to recover
    /// @param tokenAmount The amount of tokens to recover
    /// @param recipient The recipient of the tokens
    function recoverERC20(address tokenAddress, uint256 tokenAmount, address recipient) external;
}
