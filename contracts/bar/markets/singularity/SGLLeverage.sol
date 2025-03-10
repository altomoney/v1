// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {BoringERC20, IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

// Tapioca
import {SafeApprove} from "../../libraries/SafeApprove.sol";
import {SGLLendingCommon} from "./SGLLendingCommon.sol";
import {PauseType} from "tap-utils/interfaces/bar/IMarket.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract SGLLeverage is SGLLendingCommon {
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;
    using SafeApprove for address;

    // ************** //
    // *** ERRORS *** //
    // ************** //
    error LeverageExecutorNotValid();
    error CollateralShareNotValid();
    error AmountNotValid();

    struct _BuyCollateralCalldata {
        address from;
        uint256 borrowAmount;
        uint256 supplyAmount;
        bytes data;
    }

    struct _BuyCollateralMemoryData {
        uint256 supplyShareToAmount;
        uint256 borrowShareToAmount;
    }

    /// @notice Lever up: Borrow more and buy collateral with it.
    /// @param from The user who buys
    /// @param borrowAmount Amount of extra asset borrowed
    /// @param supplyAmount Amount of asset supplied (down payment)
    /// @param data LeverageExecutor data
    /// @return amountOut Actual collateral amount purchased
    function buyCollateral(address from, uint256 borrowAmount, uint256 supplyAmount, bytes calldata data)
        external
        optionNotPaused(PauseType.LeverageBuy)
        solvent(from)
        returns (uint256 amountOut)
    {
        _notSelf(from);
        if (address(leverageExecutor) == address(0)) {
            revert LeverageExecutorNotValid();
        }
        // Stack too deep fix
        _BuyCollateralCalldata memory calldata_;
        _BuyCollateralMemoryData memory memoryData;
        {
            calldata_.from = from;
            calldata_.borrowAmount = borrowAmount;
            calldata_.supplyAmount = supplyAmount;
            calldata_.data = data;
        }

        // Let this fail first to save gas:
        if (calldata_.supplyAmount > 0) {
            memoryData.supplyShareToAmount = withdraw(calldata_.supplyAmount, address(leverageExecutor), calldata_.from);
        }

        _allowedBorrow(calldata_.from, calldata_.borrowAmount);
        (, uint256 borrowShare) = _borrow(calldata_.from, address(this), calldata_.borrowAmount);

        {
            memoryData.borrowShareToAmount = redeem(borrowShare, address(leverageExecutor), address(this));
            updateExchangeRate();
            uint256 assetPartInCollateral = (memoryData.supplyShareToAmount + memoryData.borrowShareToAmount)
                * exchangeRate / EXCHANGE_RATE_PRECISION;
            _allowedBorrow(calldata_.from, convertToShares(assetPartInCollateral));

            amountOut = leverageExecutor.getCollateral(
                from,
                address(_borrowableToken()),
                collateral(),
                memoryData.supplyShareToAmount + memoryData.borrowShareToAmount,
                calldata_.data
            );
        }

        {
            uint256 collateralShare = deposit(amountOut, address(this));
            if (collateralShare == 0) revert CollateralShareNotValid();

            _addCollateral(calldata_.from, calldata_.from, 0, collateralShare, false);
        }

        if (amountOut == 0) revert AmountNotValid();
    }

    struct _SellCollateralCalldata {
        address from;
        uint256 share;
        bytes data;
    }

    /// @notice Lever down: Sell collateral to repay debt; excess goes to YB
    /// @param from The user who sells
    /// @param share Collateral  to sell
    /// @param data LeverageExecutor data
    /// @return amountOut Actual asset amount received in the sale
    function sellCollateral(address from, uint256 share, bytes calldata data)
        external
        optionNotPaused(PauseType.LeverageSell)
        solvent(from)
        returns (uint256 amountOut)
    {
        _notSelf(from);
        if (address(leverageExecutor) == address(0)) {
            revert LeverageExecutorNotValid();
        }
        // Stack too deep fix
        _SellCollateralCalldata memory calldata_;
        {
            calldata_.from = from;
            calldata_.share = share;
            calldata_.data = data;
        }

        uint256 leverageAmount = super.redeem(calldata_.share, address(leverageExecutor), from);

        amountOut =
            leverageExecutor.getAsset(from, collateral(), address(_borrowableToken()), leverageAmount, calldata_.data);
        uint256 shareOut = deposit(amountOut, calldata_.from);

        uint256 partOwed = userBorrowPart[calldata_.from];
        uint256 amountOwed = totalBorrow.toElastic(partOwed, true);
        uint256 shareOwed = previewWithdraw(amountOwed);
        if (shareOwed <= shareOut) {
            _repay(calldata_.from, calldata_.from, partOwed, false);
        } else {
            //repay as much as we can
            uint256 partOut = totalBorrow.toBase(amountOut, false);
            _repay(calldata_.from, calldata_.from, partOut, false);
        }
        if (amountOut == 0) revert AmountNotValid();
    }
}
