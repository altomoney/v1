// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./SGLLendingCommon.sol";
import {PauseType} from "tap-utils/interfaces/bar/IMarket.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

contract SGLCollateral is SGLLendingCommon {
    using RebaseLibrary for Rebase;
    using BoringERC20 for IERC20;

    // ************************ //
    // *** PUBLIC FUNCTIONS *** //
    // ************************ //

    function deposit(uint256 assets, address to)
        public
        override
        notSelf(to)
        optionNotPaused(PauseType.AddCollateral)
        returns (uint256 shares)
    {
        if (assets < minCollateralAmount) revert MinCollateralAmountNotMet();

        shares = _depositCollateral(msg.sender, to, assets);
    }

    function mint(uint256 shares, address to)
        public
        override
        notSelf(to)
        optionNotPaused(PauseType.AddCollateral)
        returns (uint256 assets)
    {
        assets = convertToAssets(shares);

        if (assets < minCollateralAmount) revert MinCollateralAmountNotMet();

        shares = _depositCollateral(msg.sender, to, assets);
    }


    /// @notice Adds `collateral` from msg.sender to the account `to`.
    /// @param from Account to transfer shares from.
    /// @param to The receiver of the tokens.
    /// False if tokens from msg.sender  should be transferred. TODO Remove skim?
    /// @param amount The amount to add for `to`.
    /// @param share The amount of shares to add for `to`.
    function addCollateral(address from, address to, uint256 amount, uint256 share)
        external
        optionNotPaused(PauseType.AddCollateral)
        notSelf(to)
    {
        if (share == 0) {
            share = convertToShares(amount);
        }

        if (amount == 0) {
            amount = convertToAssets(share);
        }
        if (amount <= minCollateralAmount) revert MinCollateralAmountNotMet();

        _addCollateral(from, to, amount, share, true);
    }

    function withdraw(uint256 _assets, address _to, address _owner)
        public
        override
        optionNotPaused(PauseType.RemoveCollateral)
        solvent(_owner)
        notSelf(_to)
        returns (uint256 shares)
    {
        shares = super.withdraw(_assets, _to, _owner);

        emit LogRemoveCollateral(_owner, _to, shares);
    }

    function redeem(uint256 _shares, address _to, address _owner)
        public
        override
        optionNotPaused(PauseType.RemoveCollateral)
        solvent(_owner)
        notSelf(_to)
        returns (uint256 assets)
    {
        assets = super.redeem(_shares, _to, _owner);

        emit LogRemoveCollateral(_owner, _to, _shares);
    }

    /// @notice Removes `share` amount of collateral and transfers it to `to`.
    /// @param from Account to debit collateral from.
    /// @param to The receiver of the shares.
    /// @param share Amount of shares to remove.
    function removeCollateral(address from, address to, uint256 share)
        external
        optionNotPaused(PauseType.RemoveCollateral)
        solvent(from)
        allowedBorrow(from, share)
        notSelf(to)
    {
        _removeCollateral(from, to, share);
    }
}
