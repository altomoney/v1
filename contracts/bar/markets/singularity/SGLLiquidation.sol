// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {BoringERC20, IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Tapioca
import {IMarketLiquidatorReceiver} from "tap-utils/interfaces/bar/IMarketLiquidatorReceiver.sol";

import {ICluster} from "tap-utils/interfaces/periph/ICluster.sol";
import {SafeApprove} from "../../libraries/SafeApprove.sol";
import {SGLCommon} from "./SGLCommon.sol";

// solhint-disable max-line-length

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract SGLLiquidation is SGLCommon {
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;
    using SafeCast for uint256;
    using SafeApprove for address;

    // ************** //
    // *** ERRORS *** //
    // ************** //
    error AmountNotValid();
    error NothingToLiquidate();
    error LengthMismatch();
    error OnCollateralReceiverFailed(uint256 returned, uint256 minAccepted);
    error BadDebt();
    error NotEnoughCollateral();
    error Solvent();
    error InsufficientLiquidationBonus();
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
        ICluster cluster = _cluster();
        require(cluster.hasRole(msg.sender, keccak256("LIQUIDATOR")) || msg.sender == owner(), "Market: unauthorized");
        _tryUpdateExchangeRate();

        //check from whitelist status
        {
            bool isWhitelisted = cluster.isWhitelisted(0, from);
            if (!isWhitelisted) revert NotAuthorized();
        }
        // accrue before liquidation
        _accrue();

        // compute borrow amount with bonus
        uint256 elasticPart = totalBorrow.toElastic(userBorrowPart[user], false);
        uint256 borrowAmountWithBonus = elasticPart + (elasticPart * liquidationMultiplier) / FEE_PRECISION;
        uint256 requiredCollateral = convertToShares((borrowAmountWithBonus * exchangeRate) / EXCHANGE_RATE_PRECISION);

        uint256 collateralShare = balanceOf(user);

        if (requiredCollateral < collateralShare) revert NotAuthorized();

        // update totalBorrow
        uint256 borrowAmount = totalBorrow.toElastic(userBorrowPart[user], true);
        totalBorrow.elastic -= borrowAmount.toUint128();
        totalBorrow.base -= userBorrowPart[user].toUint128();

        // burn collateral shares from user.
        _burn(user, collateralShare);

        // User collateral shares is now 0.
        // Set user borrow part to 0
        userBorrowPart[user] = 0;

        // transfer asset from `from`
        _borrowableToken().safeTransferFrom(from, address(this), borrowAmount);
        uint256 borrowShare = convertToShares(borrowAmount);
        totalAsset.elastic += borrowShare.toUint128();

        // swap collateral with asset and send it to `receiver`
        if (swapCollateral) {
            (, uint256 returnedAmount) =
                _swapCollateralWithAsset(collateralShare, liquidatorReceiver, liquidatorReceiverData, 0, false);
            _borrowableToken().safeTransfer(receiver, returnedAmount);
        } else {
            uint256 collateralAmount = convertToAssets(collateralShare);
            withdraw(collateralAmount, receiver, address(this));
        }
    }

    // ************************ //
    // *** PUBLIC FUNCTIONS *** //
    // ************************ //
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
    ) external optionNotPaused(PauseType.Liquidation) {
        if (users.length == 0) revert NothingToLiquidate();
        if (users.length != maxBorrowParts.length) revert LengthMismatch();
        if (users.length != liquidatorReceivers.length) revert LengthMismatch();
        if (liquidatorReceiverDatas.length != liquidatorReceivers.length) {
            revert LengthMismatch();
        }

        _tryUpdateExchangeRate();

        _accrue();

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
    ) private returns (uint256 returnedShare, uint256 returnedAmount) {
        uint256 collateralAmount = convertToAssets(_collateralShare);
        withdraw(collateralAmount, address(_liquidatorReceiver), address(this));

        {
            uint256 assetBalanceBefore = _borrowableToken().balanceOf(address(this));
            //msg.sender should be validated against `initiator` on IMarketLiquidatorReceiver
            _liquidatorReceiver.onCollateralReceiver(
                msg.sender,
                address(collateral()),
                address(_borrowableToken()),
                collateralAmount,
                _liquidatorReceiverData
            );
            uint256 assetBalanceAfter = _borrowableToken().balanceOf(address(this));
            returnedAmount = assetBalanceAfter - assetBalanceBefore;

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
        returnedShare = convertToShares(returnedAmount);
    }

    function _computeAssetAmountToSolvency(address user, uint256 _exchangeRate) private view returns (uint256) {
        // accrue must have already been called!
        uint256 borrowPart = userBorrowPart[user];
        if (borrowPart == 0) return 0;

        if (_exchangeRate == 0) revert ExchangeRateNotValid();

        Rebase memory _totalBorrow = totalBorrow;

        uint256 assetAmount = convertToAssets(
            (balanceOf(user) * (EXCHANGE_RATE_PRECISION / FEE_PRECISION) * liquidationCollateralizationRate)
        );

        uint256 collateralAmountInAsset = assetAmount / _exchangeRate;
        // Obviously it's not `borrowPart` anymore but `borrowAmount`
        borrowPart = (borrowPart * _totalBorrow.elastic) / _totalBorrow.base;

        return borrowPart >= collateralAmountInAsset ? borrowPart - collateralAmountInAsset : 0;
    }

    function _updateBorrowAndCollateralShare(
        address user,
        uint256 maxBorrowPart,
        uint256 minLiquidationBonus, // min liquidation bonus to accept (default 0)
        uint256 _exchangeRate
    ) private returns (uint256 borrowAmount, uint256 borrowPart, uint256 collateralShare) {
        if (_exchangeRate == 0) revert ExchangeRateNotValid();

        uint256 _userBorrowPart = userBorrowPart[user];
        uint256 _userCollateralShare = balanceOf(user);

        // get collateral amount in asset's value
        uint256 collateralPartInAsset =
            (convertToAssets(_userCollateralShare) * EXCHANGE_RATE_PRECISION) / _exchangeRate;

        // compute closing factor (liquidatable amount)
        uint256 borrowPartWithBonus = _computeClosingFactor(
            _userBorrowPart,
            collateralPartInAsset,
            FEE_PRECISION_DECIMALS,
            liquidationCollateralizationRate,
            liquidationMultiplier,
            totalBorrow
        );

        // limit liquidable amount before bonus to the current debt
        uint256 userTotalBorrowAmount = totalBorrow.toElastic(_userBorrowPart, true);
        borrowPartWithBonus = borrowPartWithBonus > userTotalBorrowAmount ? userTotalBorrowAmount : borrowPartWithBonus;

        // make sure liquidator cannot bypass bad debt handling
        if (collateralPartInAsset < borrowPartWithBonus) revert BadDebt();

        // check the amount to be repaid versus liquidator supplied limit
        borrowPartWithBonus = borrowPartWithBonus > maxBorrowPart ? maxBorrowPart : borrowPartWithBonus;
        borrowAmount = borrowPartWithBonus;

        // compute part units, preventing rounding dust when liquidation is full
        borrowPart =
            borrowAmount == userTotalBorrowAmount ? _userBorrowPart : totalBorrow.toBase(borrowPartWithBonus, false);
        if (borrowPart == 0) revert Solvent();

        if (liquidationBonusAmount > 0) {
            borrowPartWithBonus = borrowPartWithBonus + (borrowPartWithBonus * liquidationBonusAmount) / FEE_PRECISION;
        }

        if (collateralPartInAsset < borrowPartWithBonus) {
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
                collateralShare = _userCollateralShare;
            } else {
                revert InsufficientLiquidationBonus();
            }
        } else {
            uint256 totalUserBorrowWithBonus =
                userTotalBorrowAmount + (userTotalBorrowAmount * liquidationBonusAmount) / FEE_PRECISION;
            if (collateralPartInAsset < totalUserBorrowWithBonus) revert BadDebt();
            collateralShare = convertToShares((borrowPartWithBonus * _exchangeRate) / EXCHANGE_RATE_PRECISION);
            if (collateralShare > _userCollateralShare) {
                revert NotEnoughCollateral();
            }
        }

        userBorrowPart[user] -= borrowPart;
        _burn(user, collateralShare);
    }

    function _extractLiquidationFees(uint256 extraShare, uint256 callerReward)
        private
        returns (uint256 feeShare, uint256 callerShare)
    {
        callerShare = (extraShare * callerReward) / FEE_PRECISION; //  y%  of profit goes to caller.
        feeShare = extraShare - callerShare; // rest goes to the fee

        if (feeShare > 0) {
            uint256 feeAmount = convertToAssets(feeShare);

            uint256 fullAssetAmount = convertToAssets(totalAsset.elastic) + totalBorrow.elastic;
            uint256 feeFraction = (feeAmount * totalAsset.base) / fullAssetAmount;
            // balanceOf[address(penrose)] += feeFraction; TODO Check it
            _mint(address(_penrose), feeFraction);
            totalAsset.base += feeFraction.toUint128();
            totalAsset.elastic += feeShare.toUint128();

            deposit(convertToAssets(feeShare), address(this)); // TODO Check it
        }
        if (callerShare > 0) {
            uint256 callerAmount = convertToAssets(callerShare);
            deposit(callerAmount, msg.sender);
        }
    }

    struct __LiquidateUserData {
        uint256 callerReward;
        uint256 borrowAmount;
        uint256 borrowPart;
        uint256 collateralShare;
        uint256 borrowShare;
        uint256 returnedShare;
        uint256 extraShare;
        uint256 feeShare;
        uint256 callerShare;
    }

    function _liquidateUser(
        address user,
        uint256 maxBorrowPart,
        IMarketLiquidatorReceiver _liquidatorReceiver,
        bytes calldata _liquidatorReceiverData,
        uint256 _exchangeRate,
        uint256 minLiquidationBonus
    ) private {
        __LiquidateUserData memory data;

        data.callerReward = _getCallerReward(user, _exchangeRate);
        (data.borrowAmount, data.borrowPart, data.collateralShare) =
            _updateBorrowAndCollateralShare(user, maxBorrowPart, minLiquidationBonus, _exchangeRate);
        data.borrowShare = convertToShares(data.borrowAmount);

        {
            uint256 totalCollateralShare = balanceOf(address(this)); // TODO Check it
            totalBorrow.elastic -= data.borrowAmount.toUint128();
            totalBorrow.base -= data.borrowPart.toUint128();
        }

        {
            (data.returnedShare,) = _swapCollateralWithAsset(
                data.collateralShare, _liquidatorReceiver, _liquidatorReceiverData, _exchangeRate, true
            );
            if (data.returnedShare < data.borrowShare) revert AmountNotValid();

            data.extraShare = data.returnedShare > data.borrowShare ? data.returnedShare - data.borrowShare : 0;

            deposit(convertToAssets(data.returnedShare - data.extraShare), address(this));

            totalAsset.elastic += (data.returnedShare - data.extraShare).toUint128();
            emit LogAddAsset(address(this), address(this), (data.returnedShare - data.extraShare), 0);

            (data.feeShare, data.callerShare) = _extractLiquidationFees(data.extraShare, data.callerReward);

            address[] memory _users = new address[](1);
            _users[0] = user;
            emit Liquidated(
                msg.sender, _users, data.callerShare, data.feeShare, data.borrowAmount, data.collateralShare
            );
        }
    }

    struct __ClosedLiquidationCalldata {
        address user;
        uint256 maxBorrowPart;
        uint256 minLiquidationBonus;
        IMarketLiquidatorReceiver liquidatorReceiver;
    }

    function _closedLiquidation(
        address[] calldata users,
        uint256[] calldata maxBorrowParts,
        uint256[] calldata minLiquidationBonuses,
        IMarketLiquidatorReceiver[] calldata liquidatorReceivers,
        bytes[] calldata liquidatorReceiverDatas,
        uint256 _exchangeRate
    ) private {
        uint256 liquidatedCount = 0;
        uint256 arrLength = users.length;

        __ClosedLiquidationCalldata memory calldata_; // Stack too deep fix

        for (uint256 i; i < arrLength;) {
            calldata_.user = users[i];
            calldata_.maxBorrowPart = maxBorrowParts[i];
            calldata_.minLiquidationBonus = minLiquidationBonuses[i];
            calldata_.liquidatorReceiver = liquidatorReceivers[i];

            if (!_isSolvent(calldata_.user, _exchangeRate, true)) {
                liquidatedCount++;
                _liquidateUser(
                    calldata_.user,
                    calldata_.maxBorrowPart,
                    calldata_.liquidatorReceiver,
                    liquidatorReceiverDatas[i],
                    _exchangeRate,
                    calldata_.minLiquidationBonus
                );
            }
            unchecked {
                ++i;
            }
        }

        require(liquidatedCount != 0, "BB: no users found");
    }
}
