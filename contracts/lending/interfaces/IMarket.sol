// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

/// @notice Struct that represents the balance of a token
struct Balance {
    uint128 assets;
    uint128 shares;
}

/// @notice Struct that represents the position of a user
struct Position {
    uint128 supplyShares;
    uint128 borrowShares;
    uint128 collateralAssets;
}

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

struct LiquidationCalculationResult {
    uint256 collateralAmount;
    uint256 collateralAmountToSend;
    uint256 repayAmount;
    uint256 repayShares;
}

interface IMarketErrors {
    /// @notice Error thrown when the input is invalid
    error AltoBaseMarketInvalidInput();

    /// @notice Error thrown when the user is trying to remove more collateral then allowed
    error AltoBaseMarketInsufficientUserCollateral();

    /// @notice Error thrown when the user is trying to borrow more than they are allowed
    error AltoBaseMarketBorrowingTooMuch();

    /// @notice Error thrown when the market has insufficient liquidity for the borrow
    error AltoBaseMarketInsufficientMarketLiquidity();

    /// @notice Error thrown when trying to liquidate a solvent position
    error AltoBaseMarketLiquidatingSolventPosition();

    /// @notice Error thrown when executor is not allowed to perform the action on behalf of another user
    error AltoBaseMarketUnauthorized();

    /// @notice Error thrown when executor is not allowed to perform liquidation at this time
    error AltoBaseMarketPriorityLiquidationDisabled();

    /// @notice Error thrown when executor is not allowed to perform liquidation at this time
    error AltoBaseMarketLiquidationUnauthorized();

    /// @notice Error thrown when trying to tag a position that is already tagged
    error AltoBaseMarketLiquidationAlreadyTagged();
}

interface IMarketEvents {
    /// @notice Emitted when the IRM contract is set
    /// @param oldAddr The address of the old IRM contract
    /// @param newAddr The address of the new IRM contract
    event SetIrm(address indexed oldAddr, address indexed newAddr);

    /// @notice Emitted when the oracle contract is set
    /// @param oldAddr The address of the old oracle contract
    /// @param newAddr The address of the new oracle contract
    event SetOracle(address indexed oldAddr, address indexed newAddr);

    /// @notice Emitted when the max LTV is set
    /// @param oldMaxLtv The address of the old max LTV
    /// @param newMaxLtv The address of the new max LTV
    event SetMaxLtv(uint256 oldMaxLtv, uint256 newMaxLtv);

    /// @notice Emitted when the liquidation configuration is set
    /// @param oldLiquidationConfiguration The address of the old liquidation configuration
    /// @param newLiquidationConfiguration The address of the new liquidation configuration
    event SetLiquidationConfiguration(
        LiquidationConfiguration oldLiquidationConfiguration, LiquidationConfiguration newLiquidationConfiguration
    );

    /// @notice Emitted when the borrow opening fee is set
    /// @param oldBorrowOpeningFee The address of the old borrow opening fee
    /// @param newBorrowOpeningFee The address of the new borrow opening fee
    event SetBorrowOpeningFee(uint256 oldBorrowOpeningFee, uint256 newBorrowOpeningFee);

    /// @notice Emitted when the fee recipient is set
    /// @param oldAddr The address of the old fee recipient
    /// @param newAddr The address of the new fee recipient
    event SetFeeRecipient(address indexed oldAddr, address indexed newAddr);

    /// @notice Emitted when the authorized callback is set
    /// @param callback The address of the authorized callback
    /// @param isAuthorized If set to true, the callback contract will be allowed as an authorized callback.
    /// If set to false, the callback contract will be disallowed as an authorized callback.
    event SetAuthorizedCallback(address indexed callback, bool isAuthorized);

    /// @notice Emitted when a user supplies tokens to the lending market
    /// @param caller The address of the caller who is supplying tokens
    /// @param onBehalf The address of the user who is receiving the ownership of supplied tokens
    /// @param assets The amount of assets supplied
    /// @param shares The amount of shares minted
    event AddSupply(address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);

    /// @notice Emitted when a user withdraws tokens from the lending market
    /// @param caller The address of the caller who is withdrawing tokens on behalf
    /// @param onBehalf The address of the user who is the owner of withdrawn tokens
    /// @param receiver The address of the user who is receiving the withdrawn tokens
    /// @param assets The amount of assets withdrawn
    /// @param shares The amount of shares burned
    event RemoveSupply(
        address indexed caller, address indexed onBehalf, address indexed receiver, uint256 assets, uint256 shares
    );

    /// @notice Emitted when a user borrows tokens from the lending market
    /// @param caller The address of the caller who is borrowing tokens
    /// @param onBehalf The address of the user who is the owner of borrowed tokens
    /// @param receiver The address of the user who is receiving the borrowed tokens
    /// @param assets The amount of assets borrowed
    /// @param shares The amount of shares minted
    /// @param feeAmount The amount of assets paid as opening fee
    /// @param feeSupplyShares The amount of supply shares given to the fee recipient
    event Borrow(
        address indexed caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 feeAmount,
        uint256 feeSupplyShares
    );

    /// @notice Emitted when a user repays borrowed tokens
    /// @param caller The address of the caller who is repaying tokens
    /// @param onBehalf The address of the user who is the owner of the borrow position
    /// @param assets The amount of assets repaid
    /// @param shares The amount of shares burned
    event Repay(address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);

    /// @notice Emitted when a user deposits collateral
    /// @param caller The address of the caller who is supplying collateral
    /// @param onBehalf The address of the user who is the owner of supplied collateral
    /// @param amount The amount of collateral supplied
    event AddCollateral(address indexed caller, address indexed onBehalf, uint256 amount);

    /// @notice Emitted when a user withdraws collateral
    /// @param caller The address of the caller who is withdrawing collateral
    /// @param onBehalf The address of the owner of collateral being withdrawn
    /// @param receiver The address of the user who is receiving the withdrawn collateral
    /// @param amount The amount of collateral withdrawn
    event RemoveCollateral(address indexed caller, address indexed onBehalf, address indexed receiver, uint256 amount);

    /// @notice Emitted when interest is accrued
    /// @param borrowRate The average rate
    /// @param interest The amount of interest accrued
    /// @param totalBorrowAssets The total borrow assets
    /// @param totalSupplyAssets The total supply assets
    event AccrueInterest(uint256 borrowRate, uint256 interest, uint128 totalBorrowAssets, uint128 totalSupplyAssets);

    /// @notice Emitted when a position is tagged for liquidation
    /// @param user The address of the user whose position was tagged
    /// @param tagger The address of the liquidator who tagged the position
    /// @param timestamp The timestamp when the position was tagged
    event PositionTagged(address indexed user, address indexed tagger, uint256 timestamp);

    /// @notice Emitted when a priority liquidator's status is updated
    /// @param liquidator The address of the liquidator
    /// @param status The new status of the liquidator
    event PriorityLiquidatorUpdated(address indexed liquidator, bool status);

    // add liquidation event
    /// @notice Emitted when a liquidation occurs
    /// @param user The address of the user whose position was liquidated
    /// @param collateralToken The address of the collateral token
    /// @param borrowToken The address of the borrow token
    /// @param liquidator The address of the liquidator
    /// @param liquidatedCollateral The amount of collateral that was liquidated
    /// @param protocolFee The amount of protocol fee credited to the fee recipient
    /// @param liquidatorFee The amount of liquidator fee credited to the liquidator before the protocol fee is deducted
    /// @param repaidBorrow The amount of borrow tokens that were repaid
    /// @param repaidBorrowShares The amount of borrow shares that were repaid
    /// @param badDebtClearedAssets The amount of bad debt cleared
    /// @param badDebtClearedShares The amount of bad debt shares cleared
    event Liquidation(
        address indexed user,
        address collateralToken,
        address borrowToken,
        address liquidator,
        uint256 liquidatedCollateral,
        uint256 protocolFee,
        uint256 liquidatorFee,
        uint256 repaidBorrow,
        uint256 repaidBorrowShares,
        uint256 badDebtClearedAssets,
        uint256 badDebtClearedShares
    );
}

interface IMarketBase is IMarketErrors, IMarketEvents, IAuth, IPausable {
    /// @notice The address of the borrow token.
    function borrowToken() external view returns (address);

    /// @notice The address of the collateral token.
    function collateralToken() external view returns (address);

    /// @notice Authorized contracts to be called by `borrow` and `removeCollateral`.
    /// @dev This is used to allow for leverage and deleverage.
    function authorizedCallbacks(address callback) external view returns (bool);

    /// @notice Map of priority liquidators that can liquidate positions right after they are tagged.
    function priorityLiquidators(address liquidator) external view returns (bool);

    /// @notice Contract used for Interest Rate Model calculation when market needs to accrue interest.
    function irm() external view returns (address);

    /// @notice Oracle used to determine the collateral to borrow price.
    function oracle() external view returns (address);

    /// @notice Max position's LTV for the market.
    /// @dev This is used to determine the max amount of borrow that can be taken for a given collateral.
    function maxLtv() external view returns (uint256);

    /// @notice Fee percentage added to the borrow amount when borrowing.
    /// @dev User is charged this fee on the top of their requested borrow amount.
    function borrowOpeningFee() external view returns (uint256);

    /// @notice Address that receives the opening fee
    /// @dev This is used to send the opening fee to the fee recipient
    function feeRecipient() external view returns (address);

    /// @notice Setter of the IRM contract for the market
    /// @dev This setter accrues the interest using the previous IRM contract and sets up the new IRM contract.
    /// This can be also used to disable the interest accrual by setting the IRM to zero address..
    function setIrm(address irm) external;

    /// @notice setter of the oracle contract for the market
    function setOracle(address oracle) external;

    /// @notice setter of the max LTV for the market
    /// @dev This will be used in rare scenarios - usually when increasing the max LTV to avoid
    /// This should always be considered to be used in tandem with `setLiquidationConfiguration` as
    /// liquidation calculation depends on the max LTV.
    function setMaxLtv(uint256 maxLtv) external;

    /// @notice Setter of the liquidation configuration for the market.
    /// @dev Warning: This setter will overwrite the existing liquidation configuration.
    function setLiquidationConfiguration(LiquidationConfiguration memory _liquidationConfiguration) external;

    /// @notice Setter of the borrow opening fee for the market.
    /// @dev Fee can be set to 0 to disable the opening fee.
    function setBorrowOpeningFee(uint256 borrowOpeningFee) external;

    /// @notice Setter of the fee recipient for the market.
    function setFeeRecipient(address feeRecipient) external;

    /// @notice Function to set an authorized callback contract.
    /// @param callback The address of the callback contract
    /// @param isAuthorized If set to true, the callback contract will be allowed as an authorized callback.
    /// If set to false, the callback contract will be disallowed as an authorized callback.
    /// @dev This is used to allow for leverage and deleverage.
    function setAuthorizedCallback(address callback, bool isAuthorized) external;

    /// @notice Function to supply the borrow token to the market and make it available for borrowing.
    /// @param assets The amount of assets supplied
    /// @param shares The amount of shares to supply
    /// @param onBehalf The address of the user who will become the owner of the supply position
    /// @return assets The amount of assets supplied
    /// @return shares The amount of shares supplied
    /// @dev This increases the `totalSupply` of the market and the `supplyShares` of the `onBehalf` user.
    /// @dev Either assets or shares can be provided but not both.
    /// Providing `assets` will supply exact amount of assets to the market on behalf of `onBehalf`.
    /// Providing `shares` will supply shares to the market on behalf of `onBehalf`. `assets` should be used in majority
    /// of the cases. Specifying `shares` may end up depositing more or less assets than expected because of the
    /// slippage. See AltoAdapter.sol for an example on how to handle slippage.
    function addSupply(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256);

    /// @notice Function to remove the borrow token from the market, make it unavailable for borrowing and remove the shares.
    /// @param assets The amount of assets to remove
    /// @param shares The amount of shares to remove
    /// @param onBehalf The address of the user who is the owner of the supply position
    /// @param receiver The address of the user who is receiving the withdrawn assets
    /// @return assets The amount of assets withdrawn
    /// @return shares The amount of shares withdrawn
    /// @dev This decreases the `totalSupply` of the market and the `supplyShares` of the `onBehalf` user.
    /// @dev Either assets or shares can be provided but not both.
    /// Providing `assets` will remove exact amount of assets from the market on behalf of `onBehalf`.
    /// Providing `shares` will remove shares from the market on behalf of `onBehalf`. `assets` should be used in majority
    /// of the cases. Specifying `shares` may end up withdrawing more or less assets than expected because of the
    /// slippage. But, in the case of when user wants to withdraw all their assets, `shares` should be used.
    /// See AltoAdapter.sol for an example on how to handle slippage.
    /// @dev This function will revert if there are currenly not enough assets in the market to remove. This can
    /// happen if utilization is high or trying to withdraw more than globally available for borrow in the market.
    function removeSupply(uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256, uint256);

    /// @notice Function to deposit collateral token to the market as a collateral for borrowing.
    /// @param assets The amount of collateral supplied
    /// @param onBehalf The address of the user who will become the owner of the collateral position
    /// @return assets The amount of collateral supplied
    /// @dev This increases the `totalCollateral` of the market and the `collateralAssets` of the `onBehalf` user.
    function addCollateral(uint256 assets, address onBehalf) external returns (uint256);

    /// @notice Function to withdraw collateral token from the market and make it unavailable to be used as collateral
    /// for borrowing.
    /// @param assets The amount of collateral to remove
    /// @param onBehalf The address of the user who is the owner of the collateral position
    /// @param receiver The address of the user who is receiving the withdrawn collateral
    /// @param swapParams ABI-encoded swap parameter (see `SwapParams` struct for details)
    /// @return assets The amount of collateral withdrawn
    /// @dev This decreases the `totalCollateral` of the market and the `collateralAssets` of the `onBehalf` user.
    /// @dev This function will revert if this would leave `onBehalf`'s position insolvent after the withdrawal.
    /// @dev When `swapParams` is provided `receiver` should be an authorized callback contract implementing `IRemoveCollateralCallback`.
    /// This is used to allow for deleverage. Authorized callback contracts would be able to perform a swap and
    /// prepare enough funds to repay `onBehalf`'s position using collateral.
    function removeCollateral(uint256 assets, address onBehalf, address receiver, bytes calldata swapParams)
        external
        returns (uint256);

    /// @notice Function to borrow the borrow token from the market.
    /// @param assets The amount of assets to borrow
    /// @param shares The amount of shares to borrow
    /// @param onBehalf The address of the user who will become the owner of the borrow position
    /// @param receiver The address of the user who is receiving the borrowed tokens
    /// @param swapParams ABI-encoded swap parameter (see `SwapParams` struct for details)
    /// @return assets The amount of assets borrowed
    /// @return shares The amount of shares borrowed
    /// @return openingFeeAssets The amount of opening borrow fee paid for this borrow
    /// @dev This increases the `totalBorrowed` of the market and the `borrowShares` of the `onBehalf` user.
    /// @dev Either assets or shares can be provided but not both.
    /// Providing `assets` will borrow exact amount of assets from the market on behalf of `onBehalf`.
    /// Providing `shares` will borrow shares from the market on behalf of `onBehalf`. `assets` should be used in majority
    /// of the cases. Specifying `shares` may end up borrowing more or less assets than expected because of the
    /// slippage. See AltoAdapter.sol for an example on how to handle slippage.
    /// @dev When `swapParams` is provided `receiver` should be an authorized callback contract implementing `IBorrowCallback`.
    /// This is used to allow for leverage. Authorized callback contracts would be able to perform a swap and
    /// prepare enough collateral to borrow `assets` from the market.
    /// @dev This function can only borrow up to to the max LTV of the market for given collateral by `onBehalf`.
    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata swapParams)
        external
        returns (uint256, uint256, uint256);

    /// @notice Function to repay the borrow token to the market.
    /// @param assets The amount of assets to repay
    /// @param shares The amount of shares to repay
    /// @param onBehalf The address of the user who is the owner of the borrow position
    /// @return assets The amount of assets repaid
    /// @return shares The amount of shares burned
    /// @dev This decreases the `totalBorrowed` of the market and the `borrowShares` of the `onBehalf` user.
    /// @dev Either assets or shares can be provided but not both.
    /// Providing `assets` will repay exact amount of assets from the market on behalf of `onBehalf`.
    /// Providing `shares` will repay shares from the market on behalf of `onBehalf`. `assets` should be used in majority
    /// of the cases. Specifying `shares` may end up repaying more or less assets than expected because of the
    /// slippage. But in the case of when user wants to repay all of their borrowed assets, `shares` should be used.
    /// See AltoAdapter.sol for an example on how to handle slippage.
    /// @dev This function will revert if `onBehalf`'s position is not solvent after the repayment.
    function repay(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256);

    /// @notice Function to accrue interest for the market.
    /// @dev This function is called by the market when it needs to accrue interest.
    /// It increases the `totalBorrowed` and `totalSupply` assets of the market.
    /// @dev If `irm` is set to zero address, this function does nothing.
    function accrueInterest() external;

    /// @notice Function to liquidate an insolvent position.
    /// @param borrower The address of the borrower being liquidated
    /// @param data Additional data for the liquidator contract
    /// @return repaidBorrow The amount of borrow token repaid
    /// @return repaidBorrowShares The amount of borrow shares repaid
    /// @return protocolFee The amount of protocol credited to the fee recipient
    /// @dev This function will calculate the liquidation amount and fee by itself. Liquidator
    /// can't specify the amount of assets to repay.
    /// @dev This function will revert if `borrower`'s position is not insolvent on not tagged.
    /// @dev When `data` is provided `msg.sender` should be a contract implementing `ILiquidateCallback`.
    /// This is used to perform a potential swap and to enough funds to repay the `borrower`'s position.
    /// @dev Position has to be first tagged for liquidation using `tagLiquidablePosition` function.
    /// This will start the timer in which the position can be liquidated in by the `priorityLiquidator` first.
    /// Afterwards, if `priorityLiquidationGracePeriod` expired and position is not liquidated,
    /// the liqudator that tagged the position can liquidate it. If `taggerLiquidationGracePeriod` expired
    /// and position is not liquidated, anyone can liquidate it. If position becomes solvent and is not liquidated
    /// after it was tagged, the tag will expire in `liquidationWindowTag` seconds after the tag was set.
    /// @dev The underlying liquidation logic is well described in the docs.
    function liquidate(address borrower, bytes calldata data) external returns (uint256, uint256, uint256);

    /// @notice Function to set a priority liquidator.
    /// @param liquidator The address of the liquidator
    /// @param status If set to true, the liquidator will be allowed to liquidate positions right after
    /// position is tagged. If set to false, the liquidator will not be allowed to do so.
    function setPriorityLiquidator(address liquidator, bool status) external;

    /// @notice Function to tag a position for liquidation.
    /// @param user The address of the user whose position is being tagged
    /// @param liquidator The address of the liquidator that tagged the position
    function tagLiquidablePosition(address user, address liquidator) external;
}

interface IMarket is IMarketBase {
    /// @notice State of the user's position in market.
    /// @param user The address of the user whose position is being queried
    function position(address user) external view returns (Position memory);

    /// @notice Total supply of borrow token of the market provided by the lenders.
    function totalSupply() external view returns (Balance memory);

    /// @notice Total borrowed assets of the market currently borrowed.
    function totalBorrowed() external view returns (Balance memory);

    /// @notice Liquidation state of the user's position in market.
    /// @param user The address of the user whose position is being queried
    /// @dev Used for handling priority liquidators.
    function liquidablePositions(address user) external view returns (LiquidablePosition memory);

    /// @notice Liquidation configuration of the market.
    function liquidationConfiguration() external view returns (LiquidationConfiguration memory);
}

interface IMarketStaticTypes is IMarketBase {
    /// @notice State of the user's position in market.
    /// @param user The address of the user whose position is being queried
    function position(address user)
        external
        view
        returns (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets);

    /// @notice Total supply of borrow token of the market provided by the lenders.
    function totalSupply() external view returns (uint128 assets, uint128 shares);

    /// @notice Total borrowed assets of the market currently borrowed.
    function totalBorrowed() external view returns (uint128 assets, uint128 shares);

    /// @notice Liquidation state of the user's position in market.
    /// @dev Used for handling priority liquidators.
    function liquidablePositions(address user) external view returns (bool tagged, address tagger, uint256 timestamp);

    /// @notice Liquidation configuration of the market.
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
}
