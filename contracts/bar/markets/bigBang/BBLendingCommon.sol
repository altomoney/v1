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
    function _addCollateral(address from, address to, uint256 amount, uint256 share) internal {
        if (share == 0) {
            share = convertToShares(amount);
        }

        IERC20(collateral()).safeTransferFrom(from, address(this), amount);
        _mint(to, share);

        emit LogAddCollateral(from, to, share);
    }

    /// @dev Concrete implementation of `removeCollateral`.
    function _removeCollateral(address from, address to, uint256 share) internal {
        _burn(from, share);
        IERC20(collateral()).safeTransfer(to, convertToAssets(share));

        emit LogRemoveCollateral(from, to, share);
    }

    /// @dev Concrete implementation of `borrow`.
    function _borrow(address from, address to, uint256 amount, uint256 feeAmount)
        internal
        returns (uint256 part, uint256 share)
    {
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
        share = convertToShares(amount); // TODO Check it
    }

    /// @dev Concrete implementation of `repay`.
    function _repay(address from, address to, uint256 part, bool checkAllowance) internal returns (uint256 amount) {
        if (part > userBorrowPart[to]) {
            part = userBorrowPart[to];
        }
        if (part == 0) revert NothingToRepay();

        // @dev sub `part` of totalBorrow
        (totalBorrow, amount) = totalBorrow.sub(part, true);
        userBorrowPart[to] -= part;

        IERC20(address(_borrowableToken())).safeTransferFrom(from, address(this), amount);

        // @dev burn USDO
        IUsdo(address(_borrowableToken())).burn(address(this), amount);

        emit LogRepay(from, to, amount, part);
    }

    function _safeDecimals(IERC20 token) internal view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x313ce567)); //decimals() selector
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }
}
