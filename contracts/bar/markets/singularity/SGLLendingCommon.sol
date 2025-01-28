// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// External
import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {BoringERC20, IERC20} from "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Tapioca
import {SGLCommon} from "./SGLCommon.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract SGLLendingCommon is SGLCommon {
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;
    using SafeCast for uint256;

    // ************** //
    // *** ERRORS *** //
    // ************** //
    error BorrowCapReached();
    error NothingToRepay();
    error NotEnough();

    // ************************** //
    // *** PRIVATE FUNCTIONS *** //
    // ************************* //

    /// @dev Concrete implementation of `addCollateral`.
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
    function _borrow(address from, address to, uint256 amount) internal returns (uint256 part, uint256 share) {
        Rebase memory _totalAsset = totalAsset;
        if (_totalAsset.base < 1000) revert MinLimit();

        uint256 allShare = _totalAsset.elastic + totalBorrow.elastic;
        share = allShare == 0 ? amount : (amount * _totalAsset.base) / allShare;

        uint256 totalAssetElasticInAssets = (_totalAsset.elastic * allShare) / _totalAsset.base;
        uint256 fullAssetAmountBefore = totalAssetElasticInAssets + totalBorrow.elastic;

        _totalAsset.elastic -= share.toUint128();

        uint256 feeAmount = (amount * borrowOpeningFee) / FEE_PRECISION; // A flat % fee is charged for any borrow

        (totalBorrow, part) = totalBorrow.add(amount + feeAmount, true);
        if (totalBorrowCap != 0) {
            if (totalBorrow.elastic > totalBorrowCap) revert BorrowCapReached();
        }
        userBorrowPart[from] += part;
        emit LogBorrow(from, to, amount, feeAmount, part);

        if (feeAmount > 0) {
            uint256 feeFraction = (feeAmount * _totalAsset.base) / fullAssetAmountBefore;
            _totalAsset.base += feeFraction.toUint128();
            _mint(address(_penrose), feeFraction);
        }

        totalAsset = _totalAsset; // TODO Check it

        _borrowableToken().safeTransfer(to, amount);
    }

    /// @dev Concrete implementation of `repay`.
    function _repay(address from, address to, uint256 part, bool checkAllowance) internal returns (uint256 amount) {
        if (part > userBorrowPart[to]) {
            part = userBorrowPart[to];
        }
        if (part == 0) revert NothingToRepay();

        if (checkAllowance && msg.sender != from) {
            uint256 partInAmount;
            Rebase memory _totalBorrow = totalBorrow;
            (_totalBorrow, partInAmount) = _totalBorrow.sub(part, true);

            _allowedLend(from, partInAmount);
        }
        (totalBorrow, amount) = totalBorrow.sub(part, true);

        userBorrowPart[to] -= part;

        uint256 share = previewDeposit(amount);
        uint128 totalShare = totalAsset.elastic;

        totalAsset.elastic = totalShare + share.toUint128();

        _borrowableToken().safeTransferFrom(from, address(this), amount);

        emit LogRepay(from, to, amount, part);
    }

    function _safeDecimals(IERC20 token) internal view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x313ce567)); //decimals() selector
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }
}
