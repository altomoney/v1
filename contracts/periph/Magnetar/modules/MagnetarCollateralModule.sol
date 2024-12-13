// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Tapioca
import {
    DepositAddCollateralAndBorrowFromMarketData,
    DepositRepayAndRemoveCollateralFromMarketData,
    MagnetarWithdrawData
} from "tap-utils/interfaces/periph/IMagnetar.sol";

import {IMarket, Module} from "tap-utils/interfaces/bar/IMarket.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {SafeApprove} from "tap-utils/libraries/SafeApprove.sol";
import {MagnetarBaseModule} from "./MagnetarBaseModule.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

/**
 * @title MagnetarCollateralModule
 * @author TapiocaDAO
 * @notice Magnetar collateral related operations
 */
contract MagnetarCollateralModule is MagnetarBaseModule {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeApprove for address;

    error MagnetarCollateralModule_UnwrapNotAllowed();
    error Magnetar_WithdrawParamsMismatch();

    constructor(address _toeHelper) MagnetarBaseModule(_toeHelper) {}

    /**
     * @notice helper for deposit , add collateral to a market, borrow from the same market and withdraw
     * @dev all operations are optional:
     *         - if `deposit` is false it will skip the deposit  step
     *         - if `withdraw` is false it will skip the withdraw step
     *         - if `collateralAmount == 0` it will skip the add collateral step
     *         - if `borrowAmount == 0` it will skip the borrow step
     *     - the amount deposited  is `collateralAmount`
     *
     * @param data.market the SGL/BigBang market
     * @param data.user the user to perform the action for
     * @param data.collateralAmount the collateral amount to add
     * @param data.borrowAmount the borrow amount
     * @param data.deposit true/false flag for the deposit  step
     * @param data.withdrawParams necessary data for the same chain withdrawal
     */
    function depositAddCollateralAndBorrowFromMarket(DepositAddCollateralAndBorrowFromMarketData memory data)
        public
        payable
    {
        /**
         * @dev validate data
         */
        _validateDepositAddCollateralAndBorrowFromMarket(data);

        IMarket _market = IMarket(data.market);

        uint256 _share = _market.convertToShares(data.collateralAmount);

        /**
         * @dev deposit
         */
        if (data.deposit && data.collateralAmount > 0) {
            address collateralAddress = _market._collateral();
            data.collateralAmount = _extractTokens(data.user, collateralAddress, data.collateralAmount);
            _depositToMarket(_market, data.user, data.collateralAmount);
        }

        /**
         * @dev performs .addCollateral on data.market
         */
        if (data.collateralAmount > 0) {
            _marketAddCollateral(_market, data.marketHelper, _share, data.user, data.user);
        }

        /**
         * @dev performs .borrow on data.market
         *      if `withdraw` it uses `_withdrawHere` to withdraw assets on the same chain
         */
        if (data.borrowAmount > 0) {
            uint256 borrowShare = _market.convertToShares(data.borrowAmount);
            _marketBorrow(
                _market,
                data.marketHelper,
                data.borrowAmount,
                data.user,
                data.withdrawParams.withdraw ? address(this) : data.user
            );

            // data validated in `_validateDepositAddCollateralAndBorrowFromMarket`
            if (data.withdrawParams.withdraw) _withdrawHere(data.withdrawParams, _market);
        }
    }

    /**
     * @notice helper for deposit asset , repay on a market, remove collateral and withdraw
     * @dev all steps are optional:
     *         - if `depositAmount` is 0, the deposit  step is skipped
     *         - if `repayAmount` is 0, the repay step is skipped
     *         - if `collateralAmount` is 0, the add collateral step is skipped
     * @param data.market the SGL/BigBang market
     * @param data.user the user to perform the action for
     * @param data.depositAmount the amount to deposit
     * @param data.repayAmount the amount to repay to the market
     * @param data.collateralAmount the amount to remove from the market
     * @param data.withdrawCollateralParams necessary data for the same chain withdrawal
     */
    function depositRepayAndRemoveCollateralFromMarket(DepositRepayAndRemoveCollateralFromMarketData memory data)
        public
        payable
    {
        /**
         * @dev validate data
         */
        _validateDepositRepayAndRemoveCollateralFromMarketData(data);

        IMarket _market = IMarket(data.market);

        /**
         * @dev deposit `market._assetId()`
         */
        if (data.depositAmount > 0) {
            address assetAddress = _market._collateral();
            data.depositAmount = _extractTokens(data.user, assetAddress, data.depositAmount);
            _depositToMarket(_market, data.user, data.depositAmount);
        }

        /**
         * @dev performs a repay operation for the specified market
         */
        if (data.repayAmount > 0) {
            _marketRepay(_market, data.marketHelper, data.repayAmount, data.user, data.user);
        }

        /**
         * @dev performs a remove collateral market operation;
         *       also withdraws if requested.
         */
        if (data.collateralAmount > 0) {
            uint256 collateralShare = _market.convertToShares(data.collateralAmount);
            _marketRemoveCollateral(
                _market,
                data.marketHelper,
                collateralShare,
                data.user,
                data.withdrawCollateralParams.withdraw ? address(this) : data.user
            );

            if (data.withdrawCollateralParams.withdraw) {
                /**
                 * @dev re-calculate amount after `removeCollateral` operation
                 */
                if (collateralShare > 0) {
                    uint256 computedCollateral = _market.convertToAssets(collateralShare);
                    if (computedCollateral == 0) revert Magnetar_WithdrawParamsMismatch();

                    _withdrawHere(data.withdrawCollateralParams, _market);
                }
            }
        }
    }

    /// =====================
    /// Private
    /// =====================

    function _validateDepositAddCollateralAndBorrowFromMarket(DepositAddCollateralAndBorrowFromMarketData memory data)
        private
        view
    {
        // Check sender
        _checkSender(data.user);

        // Check provided addresses
        _checkExternalData(data.market, data.marketHelper);

        // Check withdraw data
        _checkWithdrawData(data.withdrawParams, data.market);
    }

    function _checkWithdrawData(MagnetarWithdrawData memory data, address market) private view {
        if (data.withdraw) {
            // USDO doesn't have unwrap
            if (data.unwrap) revert MagnetarCollateralModule_UnwrapNotAllowed();
            if (data.asset != IMarket(market)._asset()) revert Magnetar_WithdrawParamsMismatch();
            if (data.amount == 0) revert Magnetar_WithdrawParamsMismatch();
        }
    }

    function _validateDepositRepayAndRemoveCollateralFromMarketData(
        DepositRepayAndRemoveCollateralFromMarketData memory data
    ) private view {
        // Check sender
        _checkSender(data.user);

        // Check provided addresses
        _checkExternalData(data.market, data.marketHelper);

        // Check withdraw data
        _checkDepositRepayAndRemoveCollateralFromMarketDataWithdrawData(data.withdrawCollateralParams, data.market);
    }

    function _checkExternalData(address market, address marketHelper) private view {
        _checkWhitelisted(market);
        _checkWhitelisted(marketHelper);
    }

    function _checkDepositRepayAndRemoveCollateralFromMarketDataWithdrawData(
        MagnetarWithdrawData memory data,
        address market
    ) private view {
        if (data.withdraw) {
            if (data.asset != IMarket(market)._collateral()) revert Magnetar_WithdrawParamsMismatch();
            if (data.amount == 0) revert Magnetar_WithdrawParamsMismatch();
        }
    }
}
