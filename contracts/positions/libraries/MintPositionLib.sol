// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MintPositionLib
/// @notice Internal helpers for adding collateral to mint market, minting debt assets, repaying debt and withdrawing collateral from mint market
library MintPositionLib {
    using SafeERC20 for IERC20;

    /// @notice adds the collateral to the mint market for the calling position
    /// @param market The address of the mint market to add collateral to
    /// @param collateralToken The address of the collateral token to add
    /// @param owner The address of the owner of the collateral
    /// @param amount The amount of collateral to add
    function addCollateral(address market, address collateralToken, address owner, uint256 amount) internal {
        if (amount == 0) return;

        IERC20(collateralToken).safeTransferFrom(owner, address(this), amount);
        IERC20(collateralToken).forceApprove(market, amount);
        IMarket(market).addCollateral(amount, address(this));
        IERC20(collateralToken).forceApprove(market, 0);
    }

    /// @notice Mints borrow assets to the calling position through the mint market.
    /// @param market The address of the mint market to mint borrow assets from
    /// @param borrowAssets The amount of borrow assets to mint
    function borrow(address market, uint256 borrowAssets) internal {
        if (borrowAssets == 0) return;

        IMarket(market).borrow(borrowAssets, 0, address(this), address(this), bytes(""));
    }

    /// @notice Repays debt on behalf of the calling position.
    /// @param market The address of the mint market to repay debt from
    /// @param borrowToken The address of the borrow token to repay debt with
    /// @param borrowAssets The amount of borrow assets to repay debt with
    /// @param borrowShares The amount of borrow shares to repay debt with
    function repay(address market, address borrowToken, uint256 borrowAssets, uint256 borrowShares) internal {
        if (borrowAssets == 0 && borrowShares == 0) return;

        IMarket(market).repay(borrowAssets, borrowShares, address(this));
    }

    /// @notice Withdraws collateral from the mint market to the receiver.
    /// @param market The address of the mint market to withdraw collateral from
    /// @param collateralAmount The amount of collateral to withdraw
    /// @param receiver The address of the receiver to withdraw collateral to
    function removeCollateral(address market, uint256 collateralAmount, address receiver) internal {
        if (collateralAmount == 0) return;

        IMarket(market).removeCollateral(collateralAmount, address(this), receiver, bytes(""));
    }
}
