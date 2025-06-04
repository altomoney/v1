// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IMarket} from "@alto-monorepo/lending/interfaces/IMarket.sol";

import {CoreAdapter, Address} from "@morpho-org/bundler3/adapters/CoreAdapter.sol";
import {IWNative} from "@morpho-org/bundler3/interfaces/IWNative.sol";
import {ErrorsLib} from "@morpho-org/bundler3/libraries/ErrorsLib.sol";
import {MathRayLib} from "@morpho-org/bundler3/libraries/MathRayLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AltoAdapter is CoreAdapter {
    using MathRayLib for uint256;

    /// @dev The address of the wrapped native token.
    IWNative public immutable WRAPPED_NATIVE;

    /// @param bundler3 The address of the Bundler3 contract.
    /// @param wNative The address of the canonical native token wrapper.
    constructor(address bundler3, address wNative) CoreAdapter(bundler3) {
        require(wNative != address(0), ErrorsLib.ZeroAddress());

        WRAPPED_NATIVE = IWNative(wNative);
    }

    function marketAddSupply(IMarket market, uint256 assets, uint256 shares, uint256 maxSharePriceE27, address onBehalf)
        external
        onlyBundler3
    {
        // Do not check `onBehalf` against the zero address as it's done in AltoBorrowMarket.
        require(onBehalf != address(this), ErrorsLib.AdapterAddress());

        if (assets == type(uint256).max) {
            assets = IERC20(market.borrowToken()).balanceOf(address(this));
            require(assets != 0, ErrorsLib.ZeroAmount());
        }

        // AltoBorrowMarket's allowance is not reset as it is trusted.
        SafeERC20.forceApprove(IERC20(market.borrowToken()), address(market), type(uint256).max);

        (uint256 suppliedAssets, uint256 suppliedShares) = market.addSupply(assets, shares, onBehalf);

        require(suppliedAssets.rDivUp(suppliedShares) <= maxSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    function marketRemoveSupply(
        IMarket market,
        uint256 assets,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver
    ) external onlyBundler3 {
        if (shares == type(uint256).max) {
            shares = market.position(initiator()).supplyShares;
            require(shares != 0, ErrorsLib.ZeroAmount());
        }

        (uint256 withdrawnAssets, uint256 withdrawnShares) = market.removeSupply(assets, shares, initiator(), receiver);

        require(withdrawnAssets.rDivDown(withdrawnShares) >= minSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    function marketAddCollateral(IMarket market, uint256 assets, address onBehalf) external onlyBundler3 {
        // Do not check `onBehalf` against the zero address as it's done at AltoBorrowMarket's level.
        require(onBehalf != address(this), ErrorsLib.AdapterAddress());

        if (assets == type(uint256).max) assets = IERC20(market.collateralToken()).balanceOf(address(this));

        require(assets != 0, ErrorsLib.ZeroAmount());

        // AltoBorrowMarket's allowance is not reset as it is trusted.
        SafeERC20.forceApprove(IERC20(market.collateralToken()), address(market), type(uint256).max);

        market.addCollateral(assets, onBehalf);
    }

    function marketRemoveCollateral(IMarket market, uint256 assets, address receiver, bytes calldata data)
        external
        onlyBundler3
    {
        if (assets == type(uint256).max) assets = market.position(initiator()).collateralAssets;
        require(assets != 0, ErrorsLib.ZeroAmount());

        market.removeCollateral(assets, initiator(), receiver, data);
    }

    function marketBorrow(
        IMarket market,
        uint256 assets,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver,
        bytes calldata data
    ) external onlyBundler3 {
        (uint256 borrowedAssets, uint256 borrowedShares,) = market.borrow(assets, shares, initiator(), receiver, data);

        require(borrowedAssets.rDivDown(borrowedShares) >= minSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    function marketRepay(IMarket market, uint256 assets, uint256 shares, uint256 maxSharePriceE27, address onBehalf)
        external
        onlyBundler3
    {
        // Do not check `onBehalf` against the zero address as it's done at AltoBorrowMarket's level.
        require(onBehalf != address(this), ErrorsLib.AdapterAddress());

        if (assets == type(uint256).max) {
            assets = IERC20(market.borrowToken()).balanceOf(address(this));
            require(assets != 0, ErrorsLib.ZeroAmount());
        }

        if (shares == type(uint256).max) {
            shares = market.position(onBehalf).borrowShares;
            require(shares != 0, ErrorsLib.ZeroAmount());
        }

        // AltoBorrowMarket's allowance is not reset as it is trusted.
        SafeERC20.forceApprove(IERC20(market.borrowToken()), address(market), type(uint256).max);

        (uint256 repaidAssets, uint256 repaidShares) = market.repay(assets, shares, onBehalf);

        require(repaidAssets.rDivUp(repaidShares) <= maxSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /* TRANSFER ACTIONS */

    /// @notice Transfers ERC20 tokens from the initiator.
    /// @notice Initiator must have given sufficient allowance to the Adapter to spend their tokens.
    /// @param token The address of the ERC20 token to transfer.
    /// @param receiver The address that will receive the tokens.
    /// @param amount The amount of token to transfer. Pass `type(uint).max` to transfer the initiator's balance.
    function erc20TransferFrom(address token, address receiver, uint256 amount) external onlyBundler3 {
        require(receiver != address(0), ErrorsLib.ZeroAddress());

        address initiator = initiator();
        if (amount == type(uint256).max) amount = IERC20(token).balanceOf(initiator);

        require(amount != 0, ErrorsLib.ZeroAmount());

        SafeERC20.safeTransferFrom(IERC20(token), initiator, receiver, amount);
    }

    /* WRAPPED NATIVE TOKEN ACTIONS */

    /// @notice Wraps native tokens to wNative.
    /// @dev Native tokens must have been previously sent to the adapter.
    /// @param amount The amount of native token to wrap. Pass `type(uint).max` to wrap the adapter's balance.
    /// @param receiver The account receiving the wrapped native tokens.
    function wrapNative(uint256 amount, address receiver) external onlyBundler3 {
        if (amount == type(uint256).max) amount = address(this).balance;

        require(amount != 0, ErrorsLib.ZeroAmount());

        WRAPPED_NATIVE.deposit{value: amount}();
        if (receiver != address(this)) SafeERC20.safeTransfer(IERC20(address(WRAPPED_NATIVE)), receiver, amount);
    }

    /// @notice Unwraps wNative tokens to the native token.
    /// @dev Wrapped native tokens must have been previously sent to the adapter.
    /// @param amount The amount of wrapped native token to unwrap. Pass `type(uint).max` to unwrap the adapter's
    /// balance.
    /// @param receiver The account receiving the native tokens.
    function unwrapNative(uint256 amount, address receiver) external onlyBundler3 {
        if (amount == type(uint256).max) amount = WRAPPED_NATIVE.balanceOf(address(this));

        require(amount != 0, ErrorsLib.ZeroAmount());

        WRAPPED_NATIVE.withdraw(amount);
        if (receiver != address(this)) Address.sendValue(payable(receiver), amount);
    }
}
