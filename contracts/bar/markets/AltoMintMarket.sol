// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {
    Id,
    IAltoLendingStaticTyping,
    IAltoLendingBase,
    MarketParams,
    Position,
    Market,
    Authorization,
    Signature,
    IUsdoToken
} from "./interfaces/IAltoLending.sol";
import {
    IMorphoLiquidateCallback,
    IMorphoRepayCallback,
    IMorphoSupplyCallback,
    IMorphoSupplyCollateralCallback
} from "morpho-blue/interfaces/IMorphoCallbacks.sol";
import {IIrm} from "morpho-blue/interfaces/IIrm.sol";
import {IERC20} from "morpho-blue/interfaces/IERC20.sol";
import {IOracle} from "morpho-blue/interfaces/IOracle.sol";

import "morpho-blue/libraries/ConstantsLib.sol";
import {UtilsLib} from "morpho-blue/libraries/UtilsLib.sol";
import {EventsLib} from "morpho-blue/libraries/EventsLib.sol";
import {ErrorsLib} from "morpho-blue/libraries/ErrorsLib.sol";
import {MathLib, WAD} from "morpho-blue/libraries/MathLib.sol";
import {SharesMathLib} from "morpho-blue/libraries/SharesMathLib.sol";
import {MarketParamsLib} from "morpho-blue/libraries/MarketParamsLib.sol";
import {SafeTransferLib} from "morpho-blue/libraries/SafeTransferLib.sol";
import {AltoBorrowMarket} from "./AltoBorrowMarket.sol";

/// @title AltoMintMarket
/// @author Alto
contract AltoMintMarket is AltoBorrowMarket {
    using MathLib for uint128;
    using MathLib for uint256;
    using UtilsLib for uint256;
    using SharesMathLib for uint256;
    using SafeTransferLib for IERC20;
    using MarketParamsLib for MarketParams;

    address public immutable usdo;
    uint256 public globalDebtCeiling;

    event SetGlobalDebtCeiling(uint256 newDebtCeiling);

    constructor(address newOwner, address usdoToken, uint256 debtCeiling) AltoBorrowMarket(newOwner) {
        require(usdoToken != address(0), ErrorsLib.ZERO_ADDRESS);
        usdo = usdoToken;
        globalDebtCeiling = debtCeiling;
    }

    
    /// @inheritdoc IAltoLendingBase
    function setMarket(MarketParams memory marketParams) external override onlyOwner {
        Id id = marketParams.id();
        
        marketParams.loanToken = usdo;

        // Safe "unchecked" cast.
        market[id].lastUpdate = uint128(block.timestamp);
        idToMarketParams[id] = marketParams;

        emit EventsLib.CreateMarket(id, marketParams);

        // Call to initialize the IRM in case it is stateful.
        if (marketParams.irm != address(0)) IIrm(marketParams.irm).borrowRate(marketParams, market[id]);
    }

    function setGlobalDebtCeiling(uint256 newDebtCeiling) external onlyOwner {
        globalDebtCeiling = newDebtCeiling;

        emit SetGlobalDebtCeiling(newDebtCeiling);
    }


    /// @inheritdoc IAltoLendingBase
    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external override returns (uint256, uint256) {
        revert(ErrorsLib.UNAUTHORIZED);

        return (0, 0);
    }

    /// @inheritdoc IAltoLendingBase
    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external override returns (uint256, uint256) {
        revert(ErrorsLib.UNAUTHORIZED);

        return (0, 0);
    }

    /// @inheritdoc IAltoLendingBase
    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external override returns (uint256, uint256) {
        Id id = marketParams.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        // No need to verify that onBehalf != address(0) thanks to the following authorization check.
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterest(marketParams, id);

        if (assets > 0) shares = assets.toSharesUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        else assets = shares.toAssetsDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);

        position[id][onBehalf].borrowShares += shares.toUint128();
        market[id].totalBorrowShares += shares.toUint128();
        market[id].totalBorrowAssets += assets.toUint128();

        require(_isHealthy(marketParams, id, onBehalf), ErrorsLib.INSUFFICIENT_COLLATERAL);
        require(market[id].totalBorrowAssets <= globalDebtCeiling, ErrorsLib.INSUFFICIENT_LIQUIDITY);

        emit EventsLib.Borrow(id, msg.sender, onBehalf, receiver, assets, shares);

        IUsdoToken(usdo).mint(receiver, assets);

        return (assets, shares);
    }

    /// @inheritdoc IAltoLendingBase
    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external override returns (uint256, uint256) {
        Id id = marketParams.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterest(marketParams, id);

        if (assets > 0) shares = assets.toSharesDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);
        else assets = shares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);

        position[id][onBehalf].borrowShares -= shares.toUint128();
        market[id].totalBorrowShares -= shares.toUint128();
        market[id].totalBorrowAssets = UtilsLib.zeroFloorSub(market[id].totalBorrowAssets, assets).toUint128();

        // `assets` may be greater than `totalBorrowAssets` by 1.
        emit EventsLib.Repay(id, msg.sender, onBehalf, assets, shares);

        if (data.length > 0) IMorphoRepayCallback(msg.sender).onMorphoRepay(assets, data);

        IUsdoToken(usdo).burn(msg.sender, assets);

        return (assets, shares);
    }

    /// @inheritdoc IAltoLendingBase
    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes calldata data
    ) external override returns (uint256, uint256) {
        Id id = marketParams.id();
        require(market[id].lastUpdate != 0, ErrorsLib.MARKET_NOT_CREATED);
        require(UtilsLib.exactlyOneZero(seizedAssets, repaidShares), ErrorsLib.INCONSISTENT_INPUT);

        _accrueInterest(marketParams, id);

        {
            uint256 collateralPrice = IOracle(marketParams.oracle).price();

            require(!_isHealthy(marketParams, id, borrower, collateralPrice), ErrorsLib.HEALTHY_POSITION);

            // The liquidation incentive factor is min(maxLiquidationIncentiveFactor, 1/(1 - cursor*(1 - lltv))).
            uint256 liquidationIncentiveFactor = UtilsLib.min(
                MAX_LIQUIDATION_INCENTIVE_FACTOR,
                WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - marketParams.lltv))
            );

            if (seizedAssets > 0) {
                uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);

                repaidShares = seizedAssetsQuoted.wDivUp(liquidationIncentiveFactor).toSharesUp(
                    market[id].totalBorrowAssets, market[id].totalBorrowShares
                );
            } else {
                seizedAssets = repaidShares.toAssetsDown(market[id].totalBorrowAssets, market[id].totalBorrowShares)
                    .wMulDown(liquidationIncentiveFactor).mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);
            }
        }
        uint256 repaidAssets = repaidShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);

        position[id][borrower].borrowShares -= repaidShares.toUint128();
        market[id].totalBorrowShares -= repaidShares.toUint128();
        market[id].totalBorrowAssets = UtilsLib.zeroFloorSub(market[id].totalBorrowAssets, repaidAssets).toUint128();

        position[id][borrower].collateral -= seizedAssets.toUint128();

        uint256 badDebtShares;
        uint256 badDebtAssets;
        if (position[id][borrower].collateral == 0) {
            badDebtShares = position[id][borrower].borrowShares;
            badDebtAssets = UtilsLib.min(
                market[id].totalBorrowAssets,
                badDebtShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares)
            );

            market[id].totalBorrowAssets -= badDebtAssets.toUint128();
            market[id].totalBorrowShares -= badDebtShares.toUint128();
            position[id][borrower].borrowShares = 0;
        }

        // `repaidAssets` may be greater than `totalBorrowAssets` by 1.
        emit EventsLib.Liquidate(
            id, msg.sender, borrower, repaidAssets, repaidShares, seizedAssets, badDebtAssets, badDebtShares
        );

        IERC20(marketParams.collateralToken).safeTransfer(msg.sender, seizedAssets);

        if (data.length > 0) IMorphoLiquidateCallback(msg.sender).onMorphoLiquidate(repaidAssets, data);
        
        IUsdoToken(usdo).burn(msg.sender, repaidAssets);

        return (seizedAssets, repaidAssets);
    }
}
