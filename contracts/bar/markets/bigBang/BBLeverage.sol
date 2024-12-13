// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {BoringERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/ERC20.sol";

// Tapioca
import {SafeApprove} from "../../libraries/SafeApprove.sol";
import {BBLendingCommon} from "./BBLendingCommon.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract BBLeverage is BBLendingCommon {
    using RebaseLibrary for Rebase;
    using SafeApprove for address;
    using BoringERC20 for IERC20;

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
        notSelf(from)
        returns (uint256 amountOut)
    {
        if (address(leverageExecutor) == address(0)) {
            revert LeverageExecutorNotValid();
        }
        _penrose.reAccrueBigBangMarkets();

        // Stack too deep fix
        _BuyCollateralCalldata memory calldata_;
        _BuyCollateralMemoryData memory memoryData;
        {
            calldata_.from = from;
            calldata_.borrowAmount = borrowAmount;
            calldata_.supplyAmount = supplyAmount;
            calldata_.data = data;
        }

        {
            uint256 supplyShare = convertToShares(calldata_.supplyAmount);
            if (supplyShare > 0) {
                memoryData.supplyShareToAmount = redeem(supplyShare, address(leverageExecutor), calldata_.from);
            }
        }

        {
            (, uint256 borrowShare) = _borrow(
                calldata_.from,
                address(this),
                calldata_.borrowAmount,
                _computeVariableOpeningFee(calldata_.borrowAmount)
            );
            memoryData.borrowShareToAmount = redeem(borrowShare, address(leverageExecutor), address(this));
        }
        {
            updateExchangeRate();
            uint256 assetPartInCollateral = (memoryData.supplyShareToAmount + memoryData.borrowShareToAmount)
                * exchangeRate / EXCHANGE_RATE_PRECISION;
            uint256 _share = convertToShares(assetPartInCollateral);
            _allowedBorrow(calldata_.from, _share);

            amountOut = leverageExecutor.getCollateral(
                from,
                address(_borrowableToken()),
                collateral(),
                memoryData.supplyShareToAmount + memoryData.borrowShareToAmount,
                calldata_.data
            );
        }
        uint256 collateralShare = convertToShares(amountOut);
        if (collateralShare == 0) revert CollateralShareNotValid();

        mint(collateralShare, address(this));

        _addCollateral(calldata_.from, calldata_.from, false, 0, collateralShare, false);
        if (amountOut == 0) revert AmountNotValid();
    }

    struct _SellCollateralMemoryData {
        uint256 obtainedShare;
        uint256 leverageAmount;
        uint256 shareOut;
        uint256 partOwed;
        uint256 amountOwed;
        uint256 shareOwed;
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
        notSelf(from)
        returns (uint256 amountOut)
    {
        if (address(leverageExecutor) == address(0)) {
            revert LeverageExecutorNotValid();
        }
        _penrose.reAccrueBigBangMarkets();

        _allowedBorrow(from, share);
        _removeCollateral(from, address(this), share);

        _SellCollateralMemoryData memory memoryData;

        memoryData.leverageAmount = redeem(share, address(leverageExecutor), address(this));
        amountOut =
            leverageExecutor.getAsset(from, collateral(), address(_borrowableToken()), memoryData.leverageAmount, data);

        memoryData.shareOut = convertToShares(amountOut);

        mint(memoryData.shareOut, from); // TODO Check for rounding attack?

        memoryData.partOwed = userBorrowPart[from];
        memoryData.amountOwed = totalBorrow.toElastic(memoryData.partOwed, true);
        memoryData.shareOwed = convertToShares(memoryData.amountOwed);
        if (memoryData.shareOwed <= memoryData.shareOut) {
            _repay(from, from, memoryData.partOwed, false);
        } else {
            //repay as much as we can
            uint256 partOut = totalBorrow.toBase(amountOut, false);
            _repay(from, from, partOut, false);
        }
        if (amountOut == 0) revert AmountNotValid();
    }
}
