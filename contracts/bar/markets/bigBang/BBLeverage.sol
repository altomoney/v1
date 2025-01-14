// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {BoringERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/ERC20.sol";

// Tapioca
import {SafeApprove} from "../../libraries/SafeApprove.sol";
import {BBLendingCommon} from "./BBLendingCommon.sol";
import {PauseType} from "tap-utils/interfaces/bar/IMarket.sol";

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

        if (supplyAmount > 0) {
            _allowedCollateral(from, supplyAmount);
            IERC20(borrowableToken()).safeTransferFrom(from, address(leverageExecutor), supplyAmount);
        }

        {
            _borrow(from, address(leverageExecutor), borrowAmount, _computeVariableOpeningFee(borrowAmount));
        }

        {
            updateExchangeRate();
            uint256 assetPartInCollateral = (supplyAmount + borrowAmount) * exchangeRate / EXCHANGE_RATE_PRECISION;
            _allowedBorrow(from, convertToShares(assetPartInCollateral));

            amountOut = leverageExecutor.getCollateral(
                from, address(_borrowableToken()), collateral(), borrowAmount + supplyAmount, data
            );

            if (amountOut == 0) revert AmountNotValid();
        }
        // Mint shares via erc4626 "deposit()" function logic, skipping transferFrom
        uint256 sharesOutput = previewDeposit(amountOut);
        _mint(from, sharesOutput);
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

        _SellCollateralMemoryData memory memoryData;

        memoryData.leverageAmount = super.redeem(share, address(leverageExecutor), from);
        amountOut =
            leverageExecutor.getAsset(from, collateral(), address(_borrowableToken()), memoryData.leverageAmount, data);

        IERC20(_borrowableToken()).safeTransfer(from, amountOut);

        memoryData.shareOut = convertToShares(amountOut);

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
