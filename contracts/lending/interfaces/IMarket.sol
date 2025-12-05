// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAuth} from "@alto/utils/interfaces/IAuth.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

/// @notice The type of the market
enum MarketType {
    BORROW, // AltoBorrowMarket
    MINT, // AltoMintMarket
    DAO_MINT // AltoDaoMintMarket
}

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

/// @notice Struct that represents the parameters for initializing a base market
struct BaseMarketInitParams {
    /// @notice The address of the borrow token.
    address borrowToken;
    /// @notice The address of the collateral token.
    address collateralToken;
    /// @notice The address of the IRM contract.
    address irm;
    /// @notice The address of the owner.
    address owner;
    /// @notice The address of the oracle contract.
    address oracle;
    /// @notice The max LTV for the market.
    uint256 maxLtv;
    /// @notice The address of the fee recipient.
    address feeRecipient;
    /// @notice The address of the liquidation engine.
    address liquidationEngine;
}

/// @notice Struct that represents the parameters for initializing a borrow market
struct BorrowMarketInitParams {
    /// @notice The parameters for initializing a base market.
    BaseMarketInitParams baseMarketInitParams;
    /// @notice The initial borrow opening fee.
    uint256 initialBorrowOpeningFee;
    /// @notice The maximum amount of assets that can be supplied to the market.
    uint128 supplyCapAssets;
    /// @notice The initial interest fee.
    uint256 initialInterestFee;
}

/// @notice Struct that represents the parameters for initializing a mint market
struct MintMarketInitParams {
    /// @notice The parameters for initializing a base market.
    BaseMarketInitParams baseMarketInitParams;
    /// @notice The debt ceiling of mint market.
    uint256 debtCeiling;
    /// @notice The initial borrow opening fee.
    uint256 initialBorrowOpeningFee;
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

    /// @notice Error thrown when executor is not allowed to perform the action on behalf of another user
    error AltoBaseMarketUnauthorized();
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

    /// @notice Emitted when the liquidation engine is set
    /// @param oldLiquidationEngine The address of the old liquidation engine
    /// @param newLiquidationEngine The address of the new liquidation engine
    event SetLiquidationEngine(address indexed oldLiquidationEngine, address indexed newLiquidationEngine);

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

    // add liquidation event
    /// @notice Emitted when a liquidation occurs
    /// @param user The address of the user whose position was liquidated
    /// @param liquidator The address of the liquidator
    /// @param liquidatedCollateral The amount of collateral that was liquidated
    /// @param protocolFee The amount of protocol fee credited to the fee recipient
    /// @param repaidBorrow The amount of borrow tokens that were repaid
    /// @param repaidBorrowShares The amount of borrow shares that were repaid
    /// @param badDebtClearedAssets The amount of bad debt cleared
    /// @param badDebtClearedShares The amount of bad debt shares cleared
    event Liquidation(
        address indexed user,
        address liquidator,
        uint256 liquidatedCollateral,
        uint256 protocolFee,
        uint256 repaidBorrow,
        uint256 repaidBorrowShares,
        uint256 badDebtClearedAssets,
        uint256 badDebtClearedShares
    );

    /// @notice Emitted when a liquidation is performed through governance
    /// @param user The address of the user whose position was liquidated
    /// @param liquidator The address of the liquidator
    /// @param liquidatedCollateral The amount of collateral that was seized
    /// @param badDebtClearedAssets The amount of bad debt cleared
    /// @param badDebtClearedShares The amount of bad debt shares cleared
    event GovernanceLiquidation(
        address indexed user,
        address liquidator,
        uint256 liquidatedCollateral,
        uint256 badDebtClearedAssets,
        uint256 badDebtClearedShares
    );
}

interface IMarketBase is IMarketErrors, IMarketEvents, IAuth, IPausable {
    /// @notice The type of the market.
    function MARKET_TYPE() external view returns (MarketType);

    /// @notice The address of the borrow token.
    function borrowToken() external view returns (address);

    /// @notice The address of the collateral token.
    function collateralToken() external view returns (address);

    /// @notice Authorized contracts to be called by `borrow` and `removeCollateral`.
    /// @dev This is used to allow for leverage and deleverage.
    function authorizedCallbacks(address callback) external view returns (bool);

    /// @notice Contract used for Interest Rate Model calculation when market needs to accrue interest.
    function irm() external view returns (address);

    /// @notice Oracle used to determine the collateral to borrow price.
    function oracle() external view returns (address);

    /// @notice Max position's LTV for the market.
    /// @dev This is used to determine the max amount of borrow that can be taken for a given collateral.
    function maxLtv() external view returns (uint256);

    /// @notice function to calculate the borrow opening fee while borrowing
    /// @dev The implementation used to calculate the borrow opening fee may differ for AltoBorrowMarket and AltoMintMarket
    /// @dev This function will be implemented by the AltoBorrowMarket and AltoMintMarket
    function borrowOpeningFee() external view returns (uint256);

    /// @notice Address that receives the opening fee
    /// @dev This is used to send the opening fee to the fee recipient
    function feeRecipient() external view returns (address);

    /// @notice Setter of the IRM contract for the market
    /// @dev This setter accrues the interest using the previous IRM contract and sets up the new IRM contract.
    /// This can be also used to disable the interest accrual by setting the IRM to zero address.
    /// @param irm The address of the new IRM contract
    /// @param skipAccrueInterest If set to true, the interest accrual will be skipped. This is useful when IRM
    /// has improper setup and accruing interest would either revert or cause unwanted interest rate calculation.
    function setIrm(address irm, bool skipAccrueInterest) external;

    /// @notice setter of the oracle contract for the market
    function setOracle(address oracle) external;

    /// @notice setter of the max LTV for the market
    /// @dev This will be used in rare scenarios - usually when increasing the max LTV to avoid
    /// This should always be considered to be used in tandem with `setLiquidationConfiguration` as
    /// liquidation calculation depends on the max LTV.
    function setMaxLtv(uint256 maxLtv) external;

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
    /// @param callbackData Additional data for the liquidator contract
    /// @param liquidationData Additional data for the liquidation engine
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
    function liquidate(address borrower, bytes calldata callbackData, bytes calldata liquidationData)
        external
        returns (uint256, uint256, uint256);

    /// @notice Function to liquidate an insolvent position which is not possible to liquidate using normal liquidation
    /// @dev Governance liquidation seizes full collateral of liquidated user and offsets the debt of the protocol
    /// generating bad debt
    /// @dev Market's liquidation engine should be reviewed before running this to ensure what implications does it have on the liquidation engine.
    /// governanceLiquidate​ is not aware of liquidation engine.
    /// @dev No fees are charged for this liquidation for the simplicity of implementation
    /// @dev This function will only be used if normal liquidation reverts caused by its complexity
    /// @param borrower The address of the borrower being liquidated
    /// @return sizedCollateral The amount of collateral that was seized
    /// @return badDebtAmount The amount of borrow token that was offset
    function governanceLiquidate(address borrower) external returns (uint256, uint256);

    /// @notice Function to set the liquidation engine for the market.
    /// @param liquidationEngine The address of the liquidation engine
    function setLiquidationEngine(address liquidationEngine) external;

    /// @notice Address of the liquidation engine for the market.
    /// @return The address of the liquidation engine for the market.
    function liquidationEngine() external view returns (address);
}

interface IMarket is IMarketBase {
    /// @notice State of the user's position in market.
    /// @param user The address of the user whose position is being queried
    function position(address user) external view returns (Position memory);

    /// @notice Total supply of borrow token of the market provided by the lenders.
    function totalSupply() external view returns (Balance memory);

    /// @notice Total borrowed assets of the market currently borrowed.
    function totalBorrowed() external view returns (Balance memory);
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
}
