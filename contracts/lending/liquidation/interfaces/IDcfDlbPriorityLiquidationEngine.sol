// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";

/// @notice Struct that represents the liquidable position of a user
struct LiquidablePosition {
    bool tagged;
    address tagger;
    uint256 timestamp;
}

/// @notice Struct that represents the liquidation configuration of a market
struct LiquidationConfiguration {
    /// @notice LLTV - LTV that position has to reach to be allowed for liquidation
    uint256 maxLiquidationLtv;
    /// @notice max bonus liquidator fee percentage that can be applied to the liquidation
    uint256 dynamicBonusFeeStart;
    /// @notice tLLTV - LTV that position has to reach to be fully liquidated
    uint256 ltvForCompleteLiquidation;
    /// @notice steepness of the dynamic bonus fee decay curve
    uint256 dynamicBonusFeeDecaySteepness;
    /// @notice base liquidator fee percentage for the liquidation
    /// @dev both dynamicBonusFeeStart and liquidationBaseFee will be set reasonably high to
    /// avoid excessive bad debt generation caused by incurring high liquidation fees.
    uint256 liquidationBaseFee;
    /// @notice min penalty percentage applied to the user's position LTV after liquidation
    uint256 minPenaltyPercentage;
    /// @notice protocol fee percentage applied to the liquidator's reward fee (percentage of sum of bonus fee and base fee)
    uint256 protocolFeePercentage;
    /// @notice if true enables priority liquidation
    bool isEnabledPriorityLiquidation;
    /// @notice disable priority liquidation when position LTV is above this LTV
    uint256 disablePriorityLiquidationAbovePositionLtv;
    /// @notice grace period for the priority liquidator to liquidate a position
    uint32 priorityLiquidationGracePeriod;
    /// @notice grace period for the tagger liquidator to liquidate a position
    uint32 taggerLiquidationGracePeriod;
    /// @notice duration when tagged position is considered tagged
    uint32 liquidationWindowTag;
}

/// @notice Struct used for liquidation calculations
struct LiquidationCalculation {
    uint256 collateralPrice;
    uint256 currentLtv;
    uint256 positionCollateralValue;
    uint256 positionBorrowedAssets;
    uint256 liquidationPercentage;
    uint256 liquidationFee;
    uint256 newLtv;
    uint256 liquidatorBonusFee;
    uint256 protocolFee;
    uint256 remainingCollateralAfterFeeInBorrowAssets;
    uint256 collateralToSellInBorrowAssets;
}

interface IDcfDlbPriorityLiquidationEngineErrors {
    /// @notice Error thrown when the input is invalid
    error DcfDlbPriorityLiquidationEngineInvalidInput();

    /// @notice Error thrown when the market is already set and caller is not the same market
    error DcfDlbPriorityLiquidationEngineMarketAlreadySet();

    /// @notice Error thrown when trying to liquidate a solvent position
    error DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition();

    /// @notice Error thrown when executor is not allowed to perform liquidation at this time
    error DcfDlbPriorityLiquidationEnginePriorityLiquidationDisabled();

    /// @notice Error thrown when executor is not allowed to perform liquidation at this time
    error DcfDlbPriorityLiquidationEngineLiquidationUnauthorized();

    /// @notice Error thrown when trying to tag a position that is already tagged
    error DcfDlbPriorityLiquidationEngineLiquidationAlreadyTagged();
}

interface IDcfDlbPriorityLiquidationEngineEvents {
    /// @notice Emitted when a priority liquidator is updated
    /// @param liquidator The address of the liquidator
    /// @param status The status of the liquidator
    event PriorityLiquidatorUpdated(address indexed liquidator, bool status);

    /// @notice Emitted when the liquidation configuration is set
    /// @param oldLiquidationConfiguration The old liquidation configuration
    /// @param newLiquidationConfiguration The new liquidation configuration
    event SetLiquidationConfiguration(
        LiquidationConfiguration oldLiquidationConfiguration, LiquidationConfiguration newLiquidationConfiguration
    );

    /// @notice Emitted when a position is tagged for liquidation
    /// @param user The address of the user whose position was tagged
    /// @param tagger The address of the liquidator who tagged the position
    /// @param timestamp The timestamp when the position was tagged
    event PositionTagged(address indexed user, address indexed tagger, uint256 timestamp);
}

interface IDcfDlbPriorityLiquidationEngineBase is
    IAltoLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineEvents,
    IDcfDlbPriorityLiquidationEngineErrors
{
    /// @notice Sets the priority liquidator
    /// @param liquidator The address of the liquidator
    /// @param status The status of the liquidator
    function setPriorityLiquidator(address liquidator, bool status) external;

    /// @notice Sets the liquidation configuration
    /// @param _liquidationConfiguration The new liquidation configuration
    function setLiquidationConfiguration(LiquidationConfiguration memory _liquidationConfiguration) external;

    /// @notice Returns the status of the priority liquidator
    /// @param liquidator The address of the liquidator
    /// @return status The status of the priority liquidator
    function priorityLiquidators(address liquidator) external view returns (bool);

    /// @notice Function to tag a position for liquidation.
    /// @param user The address of the user whose position is being tagged
    /// @param liquidator The address of the liquidator that tagged the position
    function tagLiquidablePosition(address user, address liquidator) external;

    /// @notice Function to delete a tagged position.
    /// @dev This function needs to be called to delete tagged position when the position is liquidated using governance liquidation on market of this contract.
    /// @param user The address of the user whose position is being deleted
    function deleteLiquidablePosition(address user) external;
}

interface IDcfDlbPriorityLiquidationEngine is IDcfDlbPriorityLiquidationEngineBase {
    /// @notice Returns the liquidation configuration
    /// @return liquidationConfiguration The liquidation configuration
    function liquidationConfiguration() external view returns (LiquidationConfiguration memory);

    /// @notice Liquidation state of the user's position in market.
    /// @param user The address of the user whose position is being queried
    /// @dev Used for handling priority liquidators.
    function liquidablePositions(address user) external view returns (LiquidablePosition memory);
}

interface IDcfDlbPriorityLiquidationEngineStaticTypes is IDcfDlbPriorityLiquidationEngineBase {
    /// @notice Returns the liquidation configuration
    /// @return maxLiquidationLtv The maximum liquidation LTV
    /// @return dynamicBonusFeeStart The dynamic bonus fee start
    /// @return ltvForCompleteLiquidation The LTV for complete liquidation
    /// @return dynamicBonusFeeDecaySteepness The dynamic bonus fee decay steepness
    /// @return liquidationBaseFee The liquidation base fee
    /// @return minPenaltyPercentage The minimum penalty percentage
    /// @return protocolFeePercentage The protocol fee percentage
    /// @return isEnabledPriorityLiquidation The flag to enable priority liquidation
    /// @return disablePriorityLiquidationAbovePositionLtv The LTV to disable priority liquidation above
    /// @return priorityLiquidationGracePeriod The priority liquidation grace period
    /// @return taggerLiquidationGracePeriod The tagger liquidation grace period
    /// @return liquidationWindowTag The liquidation window tag
    function liquidationConfiguration()
        external
        view
        returns (
            uint256 maxLiquidationLtv,
            uint256 dynamicBonusFeeStart,
            uint256 ltvForCompleteLiquidation,
            uint256 dynamicBonusFeeDecaySteepness,
            uint256 liquidationBaseFee,
            uint256 minPenaltyPercentage,
            uint256 protocolFeePercentage,
            bool isEnabledPriorityLiquidation,
            uint256 disablePriorityLiquidationAbovePositionLtv,
            uint32 priorityLiquidationGracePeriod,
            uint32 taggerLiquidationGracePeriod,
            uint32 liquidationWindowTag
        );

    /// @notice Liquidation state of the user's position in market.
    /// @param user The address of the user whose position is being queried
    /// @dev Used for handling priority liquidators.
    function liquidablePositions(address user) external view returns (bool tagged, address tagger, uint256 timestamp);
}
