// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Balance, Position} from "@alto/lending/interfaces/IMarket.sol";

/// @notice The type of the market
enum LiquidationEngineType {
    DLB_DCF_PRIORITY // DlbDcfPriorityLiquidationEngine
}

/// @notice Struct for the liquidation engine result
/// @param seizedCollateralAssets The amount of collateral assets that were seized from the borrower
/// excluding protocol fee but including liquidator fee
/// @param repaidBorrowShares The amount of borrow shares that were repaid on borrower's position
/// @param repaidBorrowAmount The amount of borrow amount that was repaid on borrower's position
/// @param protocolSeizedCollateralFee The amount of protocol fee that should be deducted from the seized collateral
/// and transferred to the fee collector
struct LiquidationEngineResult {
    uint256 seizedCollateralAssets;
    uint256 repaidBorrowShares;
    uint256 repaidBorrowAmount;
    uint256 protocolSeizedCollateralFee;
}

/// @notice Struct for the liquidation engine input
/// @param borrower The address of the borrower
/// @param liquidator The address of the liquidator
/// @param totalSupply The total supply struct(assets, shares) of the market
/// @param totalBorrowed The total borrowed amount struct(assets, shares) of the market
/// @param position The position struct(supplyShares, borrowShares, collateralAssets) of the borrower
/// @param maxLtv The maximum LTV for the market
/// @param collateralPrice The price of the collateral token
/// @param liquidationData The liquidation data
struct LiquidationEngineInput {
    address borrower;
    address liquidator;
    Balance totalSupply;
    Balance totalBorrowed;
    Position position;
    uint256 maxLtv;
    uint256 collateralPrice;
    bytes liquidationData;
}

/// @notice Interface for the liquidation engine
/// @dev When implementing this contract, we need to take care of the following:
/// - data provided to `calculateLiquidation` are post interest accrual
/// - retrieving of any additional data not provided to `calculateLiquidation` should be handled by this contract
/// - this contract handles liquidation eligibility check by itself (insolvency checks are handled by this contract)
/// - if potential liqudation configuration is tied to market's parameters, this should be documented and if possible
/// validated in this contract
/// - this contract can have its own state variables and swapping this contract should be handled with care
/// and proper migration plan should be implemented
/// - this contract is market aware and allows only market contract to execute calculateLiquidation
interface IAltoLiquidationEngine {
    /// @notice Emitted when the market is set
    /// @param market The address of the market
    event SetMarketOnce(address market);

    /// @notice The type of the liquidation engine
    /// @dev This is used to identify the type of the liquidation engine during indexing
    function LIQUIDATION_ENGINE_TYPE() external view returns (LiquidationEngineType);

    /// @notice The address of the market that this liquidation engine is tied to
    function market() external view returns (address);

    /// @notice Sets the market address to which this liquidation engine is tied to
    /// @param _market The market to set
    /// @dev Used for the first time by the market to set itself to the liquidation engine
    function setMarketOnce(address _market) external;

    /// @notice Calculates liquidation amounts and fees
    /// @dev This function is only callable by the market contract
    /// @param input The input data for the liquidation calculation
    /// @return result The liquidation calculation result
    function prepareLiquidation(LiquidationEngineInput memory input)
        external
        returns (LiquidationEngineResult memory result);

    /// @notice Returns the minimum LLTV
    /// @dev LLTV is the minimum LTV that a position has to reach to be allowed for liquidation
    /// @dev Represents the earliest hypothetical LLTV at which the position could be liquidated, assuming the liquidation conditions defined by the engine are met.
    ///      In case of dynamic LLTV this should be the lowest possible LLTV
    /// @return minLltv The minimum LLTV
    function minLltv() external view returns (uint256);

    /// @notice Returns the protocol fee percentage
    /// @dev protocol fee percentage applied to the liquidator's reward fee (percentage of sum of bonus fee and base fee).
    ///      The precision is in MATH_PRECISION
    function protocolFeePercentage() external view returns (uint256);
}
