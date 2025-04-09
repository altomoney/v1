// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {BoringERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {IERC20} from "@boringcrypto/boring-solidity/contracts/ERC20.sol";

// Tapioca
import {IUsdo} from "tap-utils/interfaces/oft/IUsdo.sol";
import {BBCommon} from "./BBCommon.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract BBLendingCommon is BBCommon {
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;

    // ************** //
    // *** ERRORS *** //
    // ************** //
    error BorrowCapReached();
    error NothingToRepay();
    error RepayAmountNotValid();

    // ************************** //
    // *** PRIVATE FUNCTIONS *** //
    // ************************* //

    function _addCollateral(address from, address to, uint256 amount, uint256 share, bool pullTokens) internal {
        _allowedCollateral(from, amount);

        if (share == 0) {
            share = previewDeposit(amount);
        }

        if (pullTokens) {
            IERC20(collateral()).safeTransferFrom(from, address(this), amount);
        }
        _mint(to, share);

        emit LogAddCollateral(from, to, share);
    }

    function _depositCollateral(address from, address to, uint256 assets) internal returns (uint256 shares) {
        _allowedCollateral(from, assets);

        shares = super.deposit(assets, to);

        emit LogAddCollateral(from, to, shares);
    }

    /// @dev Concrete implementation of `removeCollateral`.
    function _removeCollateral(address from, address to, uint256 share) internal {
        uint256 assets = super.redeem(share, to, from);

        emit LogRemoveCollateral(from, to, assets);
    }

    /// @dev Concrete implementation of `borrow`.
    function _borrow(address from, address to, uint256 amount, uint256 feeAmount) internal returns (uint256 part) {
        (totalBorrow, part) = totalBorrow.add(amount + feeAmount, true);

        if (totalBorrowCap > 0) {
            if (totalBorrow.elastic > totalBorrowCap) revert BorrowCapReached();
        }

        userBorrowPart[from] += part;
        emit LogBorrow(from, to, amount, feeAmount, part);

        //mint USDO
        IUsdo(address(_borrowableToken())).mint(address(this), amount);

        //deposit borrowed amount to user
        _borrowableToken().safeTransfer(to, amount);
    }

    /// @dev Concrete implementation of `repay`.
    function _repay(address from, address to, uint256 part, bool checkAllowance) internal returns (uint256 amount) {
        if (part > userBorrowPart[to]) {
            part = userBorrowPart[to];
        }
        if (part == 0) revert NothingToRepay();

        if (checkAllowance && msg.sender != from) {
            uint256 partInAmount = convertToAssets(part);
            _allowedBorrow(from, partInAmount);
        }
        // @dev sub `part` of totalBorrow
        (totalBorrow, amount) = totalBorrow.sub(part, true);
        userBorrowPart[to] -= part;

        IERC20(address(_borrowableToken())).safeTransferFrom(from, address(this), amount);

        // @dev burn USDO
        IUsdo(address(_borrowableToken())).burn(address(this), amount);

        emit LogRepay(from, to, amount, part);
    }
}
