// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {BoringERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/ERC20.sol";

// Tapioca
import {IMarketLiquidatorReceiver} from "tap-utils/interfaces/bar/IMarketLiquidatorReceiver.sol";
import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {IUsdo} from "tap-utils/interfaces/oft/IUsdo.sol";
import {BBCommon} from "./BBCommon.sol";
import {PauseType} from "tap-utils/interfaces/bar/IMarket.sol";

// solhint-disable max-line-length

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract BBLiquidation is BBCommon {
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;
    using SafeCast for uint256;

    // ************** //
    // *** ERRORS *** //
    // ************** //
    error NothingToLiquidate();
    error LengthMismatch();
    error OnCollateralReceiverFailed(uint256 returned, uint256 minAccepted);
    error AmountNotValid();
    error NotAuthorized();

    // *********************** //
    // *** OWNER FUNCTIONS *** //
    // *********************** //

    function liquidateBadDebt(
        address user,
        address from,
        address receiver,
        IMarketLiquidatorReceiver liquidatorReceiver,
        bytes calldata liquidatorReceiverData,
        bool swapCollateral
    ) external {
        require(
            _cluster().hasRole(msg.sender, keccak256("LIQUIDATOR")) || msg.sender == owner(), "Market: unauthorized"
        );
        _tryUpdateExchangeRate();

        //check from whitelist status
        {
            if (!_cluster().isWhitelisted(0, from)) revert NotAuthorized();
        }

        // accrue before liquidation
        _accrue();
        _penrose.reAccrueBigBangMarkets();

        // compute borrow amount with bonus
        uint256 collateralShare = balanceOf(user);
        if (_computeRequiredCollateralWithBonus(user) < previewRedeem(collateralShare)) revert NotAuthorized();

        // update totalBorrow
        uint256 borrowAmount = totalBorrow.toElastic(userBorrowPart[user], true);
        totalBorrow.elastic -= borrowAmount.toUint128();
        totalBorrow.base -= userBorrowPart[user].toUint128();

        // set user share & part to 0
        userBorrowPart[user] = 0;

        // swap collateral with asset and send it to `owner`
        if (swapCollateral) {
            uint256 returnedAmount =
                _swapCollateralWithAsset(collateralShare, liquidatorReceiver, liquidatorReceiverData, 0, false);
            IERC20(address(_borrowableToken())).safeTransfer(receiver, returnedAmount);
        } else {
            IERC20(collateral()).safeTransfer(receiver, previewRedeem(collateralShare));
        }

        _burn(user, collateralShare);

        // burn debt amount from `from`
        IUsdo(address(_borrowableToken())).burn(from, borrowAmount);
    }

    function _computeRequiredCollateralWithBonus(address _user) private view returns (uint256) {
        // compute borrow amount with bonus
        uint256 elasticPart = totalBorrow.toElastic(userBorrowPart[_user], false);
        uint256 borrowAmountWithBonus = elasticPart + (elasticPart * liquidationMultiplier) / FEE_PRECISION;
        return (borrowAmountWithBonus * exchangeRate) / EXCHANGE_RATE_PRECISION;
    }

    // ************************ //
    // *** PUBLIC FUNCTIONS *** //
    // ************************ //

    /// @notice Entry point for liquidations.
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
    ) external optionNotPaused(PauseType.Liquidation) {
        if (users.length == 0) revert NothingToLiquidate();
        if (
            users.length != maxBorrowParts.length || users.length != liquidatorReceivers.length
                || liquidatorReceiverDatas.length != liquidatorReceivers.length
        ) revert LengthMismatch();

        _tryUpdateExchangeRate();

        _accrue();
        _penrose.reAccrueBigBangMarkets();

        _closedLiquidation(
            users, maxBorrowParts, minLiquidationBonuses, liquidatorReceivers, liquidatorReceiverDatas, exchangeRate
        );
    }

    // ************************* //
    // *** PRIVATE FUNCTIONS *** //
    // ************************* //
    function _swapCollateralWithAsset(
        uint256 _collateralShare,
        IMarketLiquidatorReceiver _liquidatorReceiver,
        bytes memory _liquidatorReceiverData,
        uint256 _exchangeRate,
        bool checkReturned
    ) private returns (uint256 returnedAmount) {
        uint256 collateralAmount = previewRedeem(_collateralShare);
        IERC20(collateral()).safeTransfer(address(_liquidatorReceiver), collateralAmount);

        {
            uint256 assetBalanceBefore = _borrowableToken().balanceOf(address(this));
            //msg.sender should be validated against `initiator` on IMarketLiquidatorReceiver
            _liquidatorReceiver.onCollateralReceiver(
                msg.sender, collateral(), address(_borrowableToken()), collateralAmount, _liquidatorReceiverData
            );
            returnedAmount = _borrowableToken().balanceOf(address(this)) - assetBalanceBefore;

            if (checkReturned) {
                uint256 receivableAsset = collateralAmount * EXCHANGE_RATE_PRECISION / _exchangeRate;
                uint256 minReceivableAsset =
                    receivableAsset - (receivableAsset * maxLiquidationSlippage / FEE_PRECISION); //1% slippage
                if (returnedAmount < minReceivableAsset) {
                    revert OnCollateralReceiverFailed(returnedAmount, minReceivableAsset);
                }
            }
        }
        if (returnedAmount == 0) revert OnCollateralReceiverFailed(0, 0);
    }

    function _updateBorrowAndCollateralShare(
        address user,
        uint256 maxBorrowAmount,
        uint256 minLiquidationBonus, // min liquidation bonus to accept (default 0)
        uint256 _exchangeRate
    ) private returns (uint256 borrowAmount, uint256 borrowPart, uint256 collateralShare) {
        if (_exchangeRate == 0) revert ExchangeRateNotValid();

        // get collateral amount in asset's value
        uint256 collateralPartInAsset = (convertToAssets(balanceOf(user)) * EXCHANGE_RATE_PRECISION) / _exchangeRate;

        // compute closing factor (liquidatable amount)
        uint256 borrowAmountToClose = computeClosingFactor(
            userBorrowPart[user],
            collateralPartInAsset
        );

        // limit liquidable amount before bonus to the current debt
        uint256 userTotalBorrowAmount = totalBorrow.toElastic(userBorrowPart[user], true);
        borrowAmountToClose = borrowAmountToClose > userTotalBorrowAmount ? userTotalBorrowAmount : borrowAmountToClose;

        // make sure liquidator cannot bypass bad debt handling
        if (collateralPartInAsset < borrowAmountToClose) revert BadDebt();

        // check the amount to be repaid versus liquidator supplied limit
        borrowAmountToClose = borrowAmountToClose > maxBorrowAmount ? maxBorrowAmount : borrowAmountToClose;
        borrowAmount = borrowAmountToClose;

        // compute part units, preventing rounding dust when liquidation is full
        borrowPart = borrowAmount == userTotalBorrowAmount
            ? userBorrowPart[user]
            : totalBorrow.toBase(borrowAmountToClose, false);
        if (borrowPart == 0) revert Solvent();

        if (liquidationBonusAmount > 0) {
            borrowAmountToClose = borrowAmountToClose + (borrowAmountToClose * liquidationBonusAmount) / FEE_PRECISION;
        }

        if (collateralPartInAsset < borrowAmountToClose) {
            if (collateralPartInAsset <= userTotalBorrowAmount) {
                revert BadDebt();
            }
            // If current debt is covered by collateral fully
            // then there is some liquidation bonus,
            // so liquidation can proceed if liquidator's minimum is met
            if (minLiquidationBonus > 0) {
                // `collateralPartInAsset > borrowAmount` as `borrowAmount <= userTotalBorrowAmount`
                uint256 effectiveBonus = ((collateralPartInAsset - borrowAmount) * FEE_PRECISION) / borrowAmount;
                if (effectiveBonus < minLiquidationBonus) {
                    revert InsufficientLiquidationBonus();
                }
                collateralShare = balanceOf(user);
            } else {
                revert InsufficientLiquidationBonus();
            }
        } else {
            uint256 totalUserBorrowWithBonus =
                userTotalBorrowAmount + (userTotalBorrowAmount * liquidationBonusAmount) / FEE_PRECISION;
            if (collateralPartInAsset < totalUserBorrowWithBonus) revert BadDebt();
            collateralShare = previewWithdraw((borrowAmountToClose * _exchangeRate) / EXCHANGE_RATE_PRECISION);
            if (collateralShare > balanceOf(user)) {
                revert NotEnoughCollateral();
            }
        }

        userBorrowPart[user] -= borrowPart;
        _burn(user, collateralShare);
    }

    function _extractLiquidationFees(uint256 returnedShare, uint256 borrowShare, uint256 callerReward)
        private
        returns (uint256 feeShare, uint256 callerShare)
    {
        uint256 extraShare = returnedShare > borrowShare ? returnedShare - borrowShare : 0;
        callerShare = (extraShare * callerReward) / FEE_PRECISION; //  y%  of profit goes to caller.
        feeShare = extraShare - callerShare; // rest of the profit goes to fee.

        //protocol fees should be kept in the contract as we do a yield box.depositAsset when we are extracting the fees using `refreshPenroseFees`
        if (callerShare > 0) {
            IERC20(_borrowableToken()).safeTransfer(msg.sender, callerShare); // TODO: check this
        }
    }

    function _liquidateUser(
        address user,
        uint256 maxBorrowAmount,
        IMarketLiquidatorReceiver _liquidatorReceiver,
        bytes calldata _liquidatorReceiverData,
        uint256 _exchangeRate,
        uint256 minLiquidationBonus
    ) private {
        uint256 callerReward = _getCallerReward(user, _exchangeRate);

        (uint256 borrowAmount, uint256 borrowPart, uint256 collateralShare) =
            _updateBorrowAndCollateralShare(user, maxBorrowAmount, minLiquidationBonus, _exchangeRate);
        totalBorrow.elastic -= borrowAmount.toUint128();
        totalBorrow.base -= borrowPart.toUint128();

        uint256 returnedAmount =
            _swapCollateralWithAsset(collateralShare, _liquidatorReceiver, _liquidatorReceiverData, _exchangeRate, true);
        if (returnedAmount < borrowAmount) revert AmountNotValid();

        (uint256 feeShare, uint256 callerShare) = _extractLiquidationFees(returnedAmount, borrowAmount, callerReward);

        IUsdo(address(_borrowableToken())).burn(address(this), borrowAmount);

        address[] memory _users = new address[](1);
        _users[0] = user;
        emit Liquidated(msg.sender, _users, callerShare, feeShare, borrowAmount, collateralShare);
    }

    /// @notice Handles the liquidation of users' balances, once the users' amount of collateral is too low.
    /// @dev Closed liquidations Only, 90% of extra shares goes to caller and 10% to protocol

    function _closedLiquidation(
        address[] calldata users,
        uint256[] calldata maxBorrowParts,
        uint256[] calldata minLiquidationBonuses,
        IMarketLiquidatorReceiver[] calldata liquidatorReceivers,
        bytes[] calldata liquidatorReceiverDatas,
        uint256 _exchangeRate
    ) private {
        uint256 liquidatedCount = 0;
        unchecked {
            for (uint256 i; i < users.length; ++i) {
                if (!_isSolvent(users[i], _exchangeRate, true)) {
                    liquidatedCount++;
                    _liquidateUser(
                        users[i],
                        maxBorrowParts[i],
                        liquidatorReceivers[i],
                        liquidatorReceiverDatas[i],
                        _exchangeRate,
                        minLiquidationBonuses[i]
                    );
                }
            }
            require(liquidatedCount != 0, "BB: no users found");
        }
    }
}
