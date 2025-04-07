// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";

// Tapioca
import {
    SGLLiquidation,
    SGLCollateral,
    Singularity,
    SGLLeverage,
    SGLCommon,
    SGLBorrow
} from "./singularity/Singularity.sol";
import {IMarketLiquidatorReceiver} from "tap-utils/interfaces/bar/IMarketLiquidatorReceiver.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {ISingularity} from "tap-utils/interfaces/bar/ISingularity.sol";
import {IMarketHelper} from "tap-utils/interfaces/bar/IMarketHelper.sol";
import {IMarket, Module} from "tap-utils/interfaces/bar/IMarket.sol";

contract MarketHelper is IMarketHelper {
    using RebaseLibrary for Rebase;

    uint256 internal constant FEE_PRECISION = 1e5;

    error ExchangeRateNotValid();
    error Solvent();
    error BadDebt();
    error InsufficientLiquidationBonus();
    error NotEnoughCollateral();

    /// @notice checks if a liquidatable position is in bad debt state
    /// @param market the SGL/BB address
    function isPositionInBadDebt(IMarket market, uint256 _exchangeRate, address _user) external view returns (bool) {
        uint256 borrowPart = market._userBorrowPart(_user);
        if (borrowPart == 0) return false;
        uint256 collateralShare = market.balanceOf(_user);
        if (collateralShare == 0) return false;

        uint256 exchangeRatePrecision = market._exchangeRatePrecision();

        // get collateral amount for total share
        uint256 collateralPartInAsset =
            (market.convertToAssets(collateralShare) * exchangeRatePrecision) / _exchangeRate;

        // limit liquidable amount before bonus to the current debt
        Rebase memory _totalBorrow = market._totalBorrow();
        uint256 userTotalBorrowAmount = _totalBorrow.toElastic(borrowPart, true);

        return collateralPartInAsset < userTotalBorrowAmount;
    }

    /// @notice returns the solvency status of a market's position
    /// @param _market the BB or SGL market
    function isPositionSolvent(address _market, address _user, uint256 _exchangeRate, bool _forLiquidation)
        external
        view
        returns (bool)
    {
        IMarket market = IMarket(_market);

        uint256 borrowPart = market._userBorrowPart(_user);
        if (borrowPart == 0) return true;
        uint256 collateralShare = market.balanceOf(_user);
        if (collateralShare == 0) return false;

        Rebase memory _totalBorrow = market._totalBorrow();

        uint256 collateralAmount = market.convertToAssets(collateralShare);
        return collateralAmount * (market._exchangeRatePrecision() / FEE_PRECISION)
            * (_forLiquidation ? market._liquidationCollateralizationRate() : market._collateralizationRate())
        // Moved exchangeRate here instead of dividing the other side to preserve more precision
        >= (borrowPart * _totalBorrow.elastic * _exchangeRate) / _totalBorrow.base;
    }

    /// @notice transforms amount to shares for a market's permit operation
    /// @param amount the amount to transform
    /// @return share amount transformed into shares
    function computeAllowedLendShare(address sglAddress, uint256 amount) external view returns (uint256 share) {
        ISingularity sgl = ISingularity(sglAddress);

        Rebase memory _totalAsset = sgl.totalAsset();
        Rebase memory _totalBorrow = sgl._totalBorrow();

        uint256 allShare = _totalAsset.elastic + _totalBorrow.elastic;
        share = (amount * allShare) / _totalAsset.base;
    }

    /// @notice returns the collateral amount used in a liquidation
    /// @dev useful to compute minAmountOut for collateral to asset swap
    /// @param user the user to liquidate
    /// @param maxBorrowPart max borrow part for user
    /// @param minLiquidationBonus minimum liquidation bonus to accept
    /// @param exchangeRatePrecision the precision of the exchange rate. Typically 1e18
    /// @param feeDecimalsPrecision the precision of the fee decimals. Typically 1e5
    function getLiquidationCollateralAmount(
        address sglAddress,
        address user,
        uint256 maxBorrowPart,
        uint256 minLiquidationBonus,
        uint256 exchangeRatePrecision,
        uint256 feeDecimalsPrecision
    ) external view returns (uint256 collateralShare) {
        ISingularity sgl = ISingularity(sglAddress);

        (bool updated, uint256 _exchangeRate) = ITapiocaOracle(sgl._oracle()).peek(sgl._oracleData());
        if (!updated || _exchangeRate == 0) {
            _exchangeRate = sgl._exchangeRate(); //use stored rate
        }
        if (_exchangeRate == 0) revert ExchangeRateNotValid();

        (,, collateralShare) = sgl.viewLiquidationBorrowAndCollateralShare(
            user, maxBorrowPart, minLiquidationBonus, exchangeRatePrecision, _exchangeRate, feeDecimalsPrecision
        );
    }

    /// @notice Adds `collateral` from msg.sender to the account `to`.
    /// @param from Account to transfer shares from.
    /// @param to The receiver of the tokens.
    /// False if tokens from msg.sender  should be transferred.
    /// @param share The amount of shares to add for `to`.
    function addCollateral(address from, address to, uint256 amount, uint256 share)
        external
        pure
        returns (Module[] memory modules, bytes[] memory calls)
    {
        modules = new Module[](1);
        calls = new bytes[](1);
        modules[0] = Module.Collateral;
        calls[0] = abi.encodeWithSelector(SGLCollateral.addCollateral.selector, from, to, amount, share);
    }

    /// @notice Removes `share` amount of collateral and transfers it to `to`.
    /// @param from Account to debit collateral from.
    /// @param to The receiver of the shares.
    /// @param share Amount of shares to remove.
    function removeCollateral(address from, address to, uint256 share)
        external
        pure
        returns (Module[] memory modules, bytes[] memory calls)
    {
        modules = new Module[](1);
        calls = new bytes[](1);
        modules[0] = Module.Collateral;
        calls[0] = abi.encodeWithSelector(SGLCollateral.removeCollateral.selector, from, to, share);
    }

    /// @notice Sender borrows `amount` and transfers it to `to`.
    /// @param from Account to borrow for.
    /// @param to The receiver of borrowed tokens.
    /// @param amount Amount to borrow.
    function borrow(address from, address to, uint256 amount)
        external
        pure
        returns (Module[] memory modules, bytes[] memory calls)
    {
        modules = new Module[](1);
        calls = new bytes[](1);
        modules[0] = Module.Borrow;
        calls[0] = abi.encodeWithSelector(SGLBorrow.borrow.selector, from, to, amount);
    }

    /// @notice View the result of a borrow operation.
    function borrowView(bytes calldata result) external pure returns (uint256 part, uint256 share) {
        (part, share) = abi.decode(result, (uint256, uint256));
    }

    /// @notice Repays a loan.
    /// @param from Address to repay from.
    /// @param to Address of the user this payment should go.
    /// @param part The amount to repay. See `userBorrowPart`.
    function repay(address from, address to, uint256 part)
        external
        pure
        returns (Module[] memory modules, bytes[] memory calls)
    {
        modules = new Module[](1);
        calls = new bytes[](1);
        modules[0] = Module.Borrow;
        calls[0] = abi.encodeWithSelector(SGLBorrow.repay.selector, from, to, part);
    }

    /// @notice view the result of a repay operation.
    function repayView(bytes calldata result) external pure returns (uint256 amount) {
        amount = abi.decode(result, (uint256));
    }

    /// @notice Lever down: Sell collateral to repay debt; excess goes to YB
    /// @param from The user who sells
    /// @param share Collateral  to sell
    /// @param data LeverageExecutor data
    function sellCollateral(address from, uint256 share, bytes calldata data)
        external
        pure
        returns (Module[] memory modules, bytes[] memory calls)
    {
        modules = new Module[](1);
        calls = new bytes[](1);
        modules[0] = Module.Leverage;
        calls[0] = abi.encodeWithSelector(SGLLeverage.sellCollateral.selector, from, share, data);
    }

    /// @notice view the result of a sellCollateral operation.
    function sellCollateralView(bytes calldata result) external pure returns (uint256 amountOut) {
        amountOut = abi.decode(result, (uint256));
    }

    /// @notice Lever up: Borrow more and buy collateral with it.
    /// @param from The user who buys
    /// @param borrowAmount Amount of extra asset borrowed
    /// @param supplyAmount Amount of asset supplied (down payment)
    /// @param data LeverageExecutor data
    function buyCollateral(address from, uint256 borrowAmount, uint256 supplyAmount, bytes calldata data)
        external
        pure
        returns (Module[] memory modules, bytes[] memory calls)
    {
        modules = new Module[](1);
        calls = new bytes[](1);
        modules[0] = Module.Leverage;
        calls[0] = abi.encodeWithSelector(SGLLeverage.buyCollateral.selector, from, borrowAmount, supplyAmount, data);
    }

    /// @notice view the result of a buyCollateral operation.
    function buyCollateralView(bytes calldata result) external pure returns (uint256 amountOut) {
        amountOut = abi.decode(result, (uint256));
    }

    /// @notice liquidates a position for which the collateral's value is less than the borrowed value
    /// @dev liquidation bonus is included in the computation
    /// @param user the address to liquidate
    /// @param from the address to extract from
    /// @param receiver the address which receives the output
    /// @param liquidatorReceiver the IMarketLiquidatorReceiver executor
    /// @param liquidatorReceiverData the IMarketLiquidatorReceiver executor data
    /// @param swapCollateral true/false
    function liquidateBadDebt(
        address user,
        address from,
        address receiver,
        IMarketLiquidatorReceiver liquidatorReceiver,
        bytes calldata liquidatorReceiverData,
        bool swapCollateral
    ) external pure returns (Module[] memory modules, bytes[] memory calls) {
        modules = new Module[](1);
        calls = new bytes[](1);
        modules[0] = Module.Liquidation;
        calls[0] = abi.encodeWithSelector(
            SGLLiquidation.liquidateBadDebt.selector,
            user,
            from,
            receiver,
            liquidatorReceiver,
            liquidatorReceiverData,
            swapCollateral
        );
    }

    /// @notice Entry point for liquidations.
    /// @dev Will call `closedLiquidation()` if not LQ exists or no LQ bid avail exists. Otherwise use LQ.
    /// @param users An array of user addresses.
    /// @param maxBorrowParts A one-to-one mapping to `users`, contains maximum (partial) borrow amounts (to liquidate) of the respective user
    /// @param minLiquidationBonuses minimum liquidation bonus acceptable
    /// @param liquidatorReceivers IMarketLiquidatorReceiver array
    /// @param liquidatorReceiverDatas IMarketLiquidatorReceiver datas
    function liquidate(
        address[] calldata users,
        uint256[] calldata maxBorrowParts,
        uint256[] calldata minLiquidationBonuses,
        IMarketLiquidatorReceiver[] calldata liquidatorReceivers,
        bytes[] calldata liquidatorReceiverDatas
    ) external pure returns (Module[] memory modules, bytes[] memory calls) {
        modules = new Module[](1);
        calls = new bytes[](1);
        modules[0] = Module.Liquidation;
        calls[0] = abi.encodeWithSelector(
            SGLLiquidation.liquidate.selector,
            users,
            maxBorrowParts,
            minLiquidationBonuses,
            liquidatorReceivers,
            liquidatorReceiverDatas
        );
    }
}
