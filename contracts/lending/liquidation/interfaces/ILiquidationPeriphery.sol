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
    /// @notice Emitted when the market registry is set.
    event MarketRegistrySet(address indexed oldMarketRegistry, address indexed newMarketRegistry);
    /// @notice Emitted when the USM is set.
    event UsmSet(address indexed oldUsm, address indexed newUsm);
}

interface ILiquidationPeripheryBase is ILiquidationPeripheryErrors, ILiquidationPeripheryEvents {
    /// @notice Liquidates a position in a market for specified borrower
    /// @dev if repayViaUsm is true, the borrow amount will be repaid via USM.
    /// In that case, it will fetch underlying asset from USM and sell it in USM to repay the borrow amount.
    /// Otherwise, it will repay the borrow amount directly from the liquidator's balance.
    /// @param market The address of the market to liquidate the position in
    /// @param borrower The address of the borrower to liquidate the position for
    /// @param repayViaUsm Whether to repay the borrow amount via USM
    /// @param liquidationData Additional data for the liquidation
    /// @param liquidationPeripheryCallbackData Additional data to passed to the callback receiver of liquidation periphery contract
    function liquidate(
        address market,
        address borrower,
        bool repayViaUsm,
        bytes calldata liquidationData,
        bytes calldata liquidationPeripheryCallbackData
    ) external returns (uint256 seizedCollateral, uint256 repaidBorrow, uint256 protocolFee);

    /// @notice Sets the market registry
    /// @param newMarketRegistry The address of the new market registry
    function setMarketRegistry(address newMarketRegistry) external;

    /// @notice Sets the USM
    /// @param newUsm The address of the new USM
    /// @dev The stable token of the USM must be the same as the borrow token of
    ///   LiquidationPeriphery which will be borrow token of Market.
    function setUsm(address newUsm) external;

    /// @notice Returns the address of the market registry
    function marketRegistry() external view returns (IMarketRegistry);

    /// @notice Returns the address of the USM
    function usm() external view returns (IAdvancedPermissionsUsm);

    /// @notice Returns the address of the borrow token
    function BORROW_TOKEN() external view returns (address);
}
