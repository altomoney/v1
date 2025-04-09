// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {IERC4626} from "../../utils/interfaces/common/IERC4626.sol";
import {IMarket} from "../interfaces/bar/IMarket.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/
error ExchangeRateNotValid();
error Solvent();
error BadDebt();
error InsufficientLiquidationBonus();
error NotEnoughCollateral();

struct ViewLiquidation {
    address user;
    uint256 maxBorrowPart;
    uint256 minLiquidationBonus;
    uint256 exchangeRate;
    uint256 userCollateralShare;
    uint256 userBorrowPart;
    Rebase totalBorrow;
    uint256 liquidationBonusAmount;
    uint256 liquidationCollateralizationRate;
    uint256 liquidationMultiplier;
    uint256 exchangeRatePrecision;
    uint256 feeDecimalsPrecision;
}

library MarketLib {
    using RebaseLibrary for Rebase;

    function getCallerReward(
        IMarket _market,
        address user,
        uint256 _exchangeRate,
        uint256 _feePrecision
    ) public view returns (uint256) {
        uint256 userShares = IERC4626(address(_market)).balanceOf(user);
        (uint256 startTVLInAsset, uint256 maxTVLInAsset) = computeMaxAndMinLTVInAsset(
            _market,
            userShares,
            _exchangeRate,
            _feePrecision
        );

        uint256 borrowed = _market._userBorrowPart(user);
        if (borrowed == 0) return 0;
        if (startTVLInAsset == 0) return 0;

        Rebase memory totalBorrow = _market._totalBorrow();
        borrowed = (borrowed * totalBorrow.elastic) / totalBorrow.base;

        uint256 minLiquidatorReward = _market._minLiquidatorReward();
        uint256 maxLiquidatorReward = _market._maxLiquidatorReward();

        if (borrowed < startTVLInAsset) return 0;
        if (borrowed >= maxTVLInAsset) return minLiquidatorReward;

        uint256 rewardPercentage = ((borrowed - startTVLInAsset) * _feePrecision) / (maxTVLInAsset - startTVLInAsset);

        int256 diff = int256(minLiquidatorReward) - int256(maxLiquidatorReward);
        int256 reward = (diff * int256(rewardPercentage)) / int256(_feePrecision) + int256(maxLiquidatorReward);

        if (reward < int256(minLiquidatorReward)) {
            reward = int256(minLiquidatorReward);
        }

        return uint256(reward);
    }

    function computeMaxAndMinLTVInAsset(
        IMarket _market,
        uint256 _collateralShare,
        uint256 _exchangeRate,
        uint256 _feePrecision
    )
        public
        view
        returns (uint256 min, uint256 max)
    {
        require(_exchangeRate > 0, "Market: exchangeRate not valid");
        uint256 collateralAmount = IERC4626(address(_market)).convertToAssets(_collateralShare);

        max = (collateralAmount * _market._exchangeRatePrecision()) / _exchangeRate;
        min = (max * _market._liquidationCollateralizationRate()) / _feePrecision;
    }

    /// @notice Concrete implementation of `isSolvent`. Includes a parameter to allow caching `exchangeRate`.
    /// @param _exchangeRate The exchange rate. Used to cache the `exchangeRate` between calls.
    function isSolvent(
        IMarket _market,
        address user,
        uint256 _exchangeRate,
        bool _liquidation,
        uint256 _feePrecision
    ) public view returns (bool) {
        // accrue must have already been called!
        uint256 borrowPart = _market._userBorrowPart(user);
        if (borrowPart == 0) return true;
        uint256 collateralShare = IERC4626(address(_market)).balanceOf(user);
        if (collateralShare == 0) return false;

        Rebase memory _totalBorrow = _market._totalBorrow();

        uint256 collateralAmount = IERC4626(address(_market)).maxWithdraw(user);
        return (collateralAmount * _market._exchangeRatePrecision() / _feePrecision)
            * (_liquidation ? _market._liquidationCollateralizationRate() : _market._collateralizationRate())
        // Moved exchangeRate here instead of dividing the other side to preserve more precision
        >= (borrowPart * _totalBorrow.elastic * _exchangeRate) / _totalBorrow.base;
    }

    function computeClosingFactor(
        IMarket _market,
        uint256 borrowPart,
        uint256 collateralPartInAsset,
        uint256 ratesPrecision,
        uint256 _liquidationCollateralizationRate,
        uint256 _liquidationMultiplier,
        Rebase memory _totalBorrow
    ) public pure returns (uint256) {
        // Obviously it's not `borrowPart` anymore but `borrowAmount`
        borrowPart = (borrowPart * _totalBorrow.elastic) / _totalBorrow.base;

        //borrowPart and collateralPartInAsset should already be scaled due to the exchange rate computation
        uint256 liquidationStartsAt =
            (collateralPartInAsset * _liquidationCollateralizationRate) / (10 ** ratesPrecision);

        if (borrowPart < liquidationStartsAt) return 0;

        //compute numerator
        uint256 numerator = borrowPart - liquidationStartsAt;
        //compute denominator
        uint256 diff = (_liquidationCollateralizationRate * ((10 ** ratesPrecision) + _liquidationMultiplier))
            / (10 ** ratesPrecision);
        int256 denominator = (int256(10 ** ratesPrecision) - int256(diff)) * int256(1e13);

        //compute closing factor
        int256 x = (int256(numerator) * int256(1e18)) / denominator;
        int256 xPos = x < 0 ? -x : x;

        //assure closing factor validity
        if (uint256(xPos) > borrowPart) return borrowPart;

        return uint256(xPos);
    }

    function viewLiquidationBorrowAndCollateralShare(
        IMarket market,
        address _user,
        uint256 _maxBorrowPart,
        uint256 _minLiquidationBonus,
        uint256 _exchangeRatePrecision,
        uint256 _exchangeRate,
        uint256 _feeDecimalsPrecision,
        uint256 _feePrecision
    ) public view returns (uint256 borrowAmount, uint256 borrowPart, uint256 collateralShare) {
        ViewLiquidation memory data;
        data.user = _user;
        data.maxBorrowPart = _maxBorrowPart;
        data.minLiquidationBonus = _minLiquidationBonus;
        data.exchangeRate = _exchangeRate;
        data.exchangeRatePrecision = _exchangeRatePrecision;
        data.feeDecimalsPrecision = _feeDecimalsPrecision;
        data.userCollateralShare = IERC4626(address(market)).balanceOf(_user);
        data.userBorrowPart = market._userBorrowPart(_user);
        data.totalBorrow = market._totalBorrow();
        data.liquidationBonusAmount = market._liquidationBonusAmount();
        data.liquidationCollateralizationRate = market._liquidationCollateralizationRate();
        data.liquidationMultiplier = market._liquidationMultiplier();
        return _viewLiquidationBorrowAndCollateralShare(market, data, _feePrecision);
    }

    function _viewLiquidationBorrowAndCollateralShare(IMarket market, ViewLiquidation memory _data, uint256 feePrecision)
        private
        view
        returns (uint256 borrowAmount, uint256 borrowPart, uint256 collateralShare)
    {
        if (_data.exchangeRate == 0) revert ExchangeRateNotValid();

        // get collateral amount in asset's value
        uint256 collateralPartInAsset = (
            IERC4626(address(market)).convertToAssets(_data.userCollateralShare) * _data.exchangeRatePrecision
        ) / _data.exchangeRate;

        // compute closing factor (liquidatable amount)
        uint256 borrowPartWithBonus = market.computeClosingFactor(_data.userBorrowPart, collateralPartInAsset);

        // limit liquidable amount before bonus to the current debt
        uint256 userTotalBorrowAmount = _data.totalBorrow.toElastic(_data.userBorrowPart, true);
        borrowPartWithBonus = borrowPartWithBonus > userTotalBorrowAmount ? userTotalBorrowAmount : borrowPartWithBonus;

        // make sure liquidator cannot bypass bad debt handling
        if (collateralPartInAsset < borrowPartWithBonus) revert BadDebt();

        // check the amount to be repaid versus liquidator supplied limit
        borrowPartWithBonus = borrowPartWithBonus > _data.maxBorrowPart ? _data.maxBorrowPart : borrowPartWithBonus;
        borrowAmount = borrowPartWithBonus;

        // compute part units, preventing rounding dust when liquidation is full
        borrowPart = borrowAmount == userTotalBorrowAmount
            ? _data.userBorrowPart
            : _data.totalBorrow.toBase(borrowPartWithBonus, false);
        if (borrowPart == 0) revert Solvent();

        if (_data.liquidationBonusAmount > 0) {
            borrowPartWithBonus =
                borrowPartWithBonus + (borrowPartWithBonus * _data.liquidationBonusAmount) / feePrecision;
        }

        if (collateralPartInAsset < borrowPartWithBonus) {
            if (collateralPartInAsset <= userTotalBorrowAmount) {
                revert BadDebt();
            }
            // If current debt is covered by collateral fully
            // then there is some liquidation bonus,
            // so liquidation can proceed if liquidator's minimum is met
            if (_data.minLiquidationBonus > 0) {
                // `collateralPartInAsset > borrowAmount` as `borrowAmount <= userTotalBorrowAmount`
                uint256 effectiveBonus = ((collateralPartInAsset - borrowAmount) * feePrecision) / borrowAmount;
                if (effectiveBonus < _data.minLiquidationBonus) {
                    revert InsufficientLiquidationBonus();
                }
                collateralShare = _data.userCollateralShare;
            } else {
                revert InsufficientLiquidationBonus();
            }
        } else {
            collateralShare = IERC4626(address(market)).convertToShares(
                (borrowPartWithBonus * _data.exchangeRate) / _data.exchangeRatePrecision
            );
            if (collateralShare > _data.userCollateralShare) {
                revert NotEnoughCollateral();
            }
        }
    }

    /// @notice return the amount of collateral for a `user` to be solvent, min TVL and max TVL. Returns 0 if user already solvent.
    /// @dev we use a `CLOSED_COLLATERIZATION_RATE` that is a safety buffer when making the user solvent again,
    ///      to prevent from being liquidated. This function is valid only if user is not solvent by `_isSolvent()`.
    /// @param _accrueViewTotalBorrow The total borrow amount.
    /// @param user The user to check solvency.
    /// @param _exchangeRate the exchange rate asset/collateral.
    /// @return amountToSolvency the amount of collateral to be solvent.
    /// @return minTVL the asset value of the collateral amount factored by collateralizationRate
    /// @return maxTVL the asset value of the collateral amount.
    function computeTVLInfo(IMarket _market, uint256 _userBorrowPart, Rebase memory _accrueViewTotalBorrow, address user, uint256 _exchangeRate, uint256 _feePrecision)
        public
        view
        returns (uint256 amountToSolvency, uint256 minTVL, uint256 maxTVL)
    {
        uint256 borrowPart = _userBorrowPart;
        if (borrowPart == 0) return (0, 0, 0);

        Rebase memory _totalBorrow = _accrueViewTotalBorrow;

        uint256 collateralAmountInAsset = computeMaxBorrowableAmount(_market, user, _exchangeRate, _feePrecision);

        borrowPart = (borrowPart * _totalBorrow.elastic) / _totalBorrow.base;

        unchecked {
            amountToSolvency = borrowPart >= collateralAmountInAsset ? borrowPart - collateralAmountInAsset : 0;
        }
        (minTVL, maxTVL) = computeMaxAndMinLTVInAsset(_market, IERC4626(address(_market)).balanceOf(user), _exchangeRate, _feePrecision);
    }

    function computeMaxBorrowableAmount(IMarket _market, address _user, uint256 _exchangeRate, uint256 _feePrecision)
        public
        view
        returns (uint256 collateralAmountInAsset)
    {
        require(_exchangeRate > 0, "Market: exchangeRate not valid");
        uint256 userCollateralAmount = IERC4626(address(_market)).balanceOf(_user);
        collateralAmountInAsset =
            (userCollateralAmount * _market._exchangeRatePrecision() * _market._collateralizationRate()) / (_feePrecision * _exchangeRate);
    }
}
