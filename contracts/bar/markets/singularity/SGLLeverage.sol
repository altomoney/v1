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

        // Let this fail first to save gas:
        if (supplyAmount > 0) {
            _allowedBorrow(from, supplyAmount);
            IERC20(borrowableToken()).safeTransferFrom(from, address(leverageExecutor), supplyAmount);
        }

        {
            _allowedBorrow(from, borrowAmount);
            _borrow(from, address(this), borrowAmount);
        }

        {
            updateExchangeRate();
            
            uint256 assetPartInCollateral = (supplyAmount + borrowAmount) * exchangeRate / EXCHANGE_RATE_PRECISION;
            
            _allowedBorrow(from, previewDeposit(assetPartInCollateral));
            borrowableToken().safeApprove(address(leverageExecutor), supplyAmount + borrowAmount);

            amountOut = leverageExecutor.getCollateral(
                address(this),
                address(_borrowableToken()),
                collateral(),
                supplyAmount + borrowAmount,
                data
            );
        }

        {
            // Mint shares via erc4626 "deposit()" function logic, skipping transferFrom
            uint256 sharesOutput = previewDeposit(amountOut);
            _mint(from, sharesOutput);
            
            if (sharesOutput == 0) revert CollateralShareNotValid();

            address thisAddress = address(this);
            /// @solidity memory-safe-assembly
            assembly {
                // Emit the {Deposit} event.
                mstore(0x00, amountOut)
                mstore(0x20, sharesOutput)
                let m := shr(96, not(0))
                log3(
                    0x00,
                    0x40,
                    0xdcbc1c05240f31ff3ad067ef1ee35ce4997762752e3a095284754544f4c709d7, // _DEPOSIT_EVENT_SIGNATURE
                    and(m, address()),
                    and(m, from)
                )
            }
            _afterDeposit(amountOut, sharesOutput);

            emit LogAddCollateral(address(this), from, sharesOutput);
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
        notSelf(from)
        returns (uint256 amountOut)
    {
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
        uint256 leverageAmount = super.redeem(calldata_.share, address(this), from);

        collateral().safeApprove(address(leverageExecutor), leverageAmount);

        amountOut =
            leverageExecutor.getAsset(from, collateral(), address(_borrowableToken()), leverageAmount, calldata_.data);
        
        IERC20(_borrowableToken()).safeTransfer(from, amountOut);

        uint256 shareOut = previewWithdraw(amountOut);
        uint256 partOwed = userBorrowPart[from];
        uint256 amountOwed = totalBorrow.toElastic(partOwed, true);
        uint256 shareOwed = previewWithdraw(amountOwed);
        if (shareOwed <= shareOut) {
            _repay(calldata_.from, calldata_.from, partOwed, false);
            // TODO Should we check returned value?
        } else {
            //repay as much as we can
            uint256 partOut = totalBorrow.toBase(amountOut, false);
            _repay(calldata_.from, calldata_.from, partOut, false);
            // TODO Should we check returned value?
        }
        if (amountOut == 0) revert AmountNotValid();
    }
}
