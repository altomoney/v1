// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IRewardsDistributor, ClaimData} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {IAltoStaking} from "@alto/staking/interfaces/IAltoStaking.sol";
import {IUniversalRewardsDistributor} from "@alto/utils/interfaces/IUniversalRewardsDistributor.sol";
import {IAltoVesting, VestingInfo} from "@alto/vesting/interfaces/IAltoVesting.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

import {CoreAdapter, Address} from "@morpho-org/bundler3/adapters/CoreAdapter.sol";
import {IWNative} from "@morpho-org/bundler3/interfaces/IWNative.sol";
import {ErrorsLib} from "@morpho-org/bundler3/libraries/ErrorsLib.sol";
import {MathRayLib} from "@morpho-org/bundler3/libraries/MathRayLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AltoAdapter
/// @author GPM
/// @author Inspired by Morpho's GeneralAdapter1 (https://github.com/morpho-org/bundler3).
/// @custom:contact security@altofoundation.org
/// @notice A contract that allows for transaction bundling Alto's contracts via Morpho's Bundler3.
/// @dev This contract assumes that all of the functions are being bundled correctly and no funds are
/// left on the adapter post transaction! If there are any funds left on the adapter,
/// the "attacker" would be able to drain those funds via any of the functions in this contract. Because this
/// contract max approves arbitrary contracts in its name, this attack vector could be extended. That being
/// said, it is the responsibility of the caller to ensure that the adapter is not left with any funds after
/// the transaction.
contract AltoAdapter is CoreAdapter, AdapterContractApproval {
    using MathRayLib for uint256;

    /// @dev The address of the wrapped native token.
    IWNative public immutable WRAPPED_NATIVE;

    /// @param bundler3 The address of the Bundler3 contract.
    /// @param wNative The address of the canonical native token wrapper.
    constructor(address bundler3, address wNative, address owner) CoreAdapter(bundler3) AdapterContractApproval(owner) {
        require(wNative != address(0), ErrorsLib.ZeroAddress());

        WRAPPED_NATIVE = IWNative(wNative);
    }

    /* MARKET ACTIONS */

    /// @notice Adds supply to the market.
    /// @param market The address of the market.
    /// @param assets The amount of assets to add.
    /// @param shares The amount of shares to add.
    /// @param maxSharePriceE27 The maximum share price scaled by 1e27 (used for slippage protection).
    /// @param onBehalf The address of the user whose position is supply being added to.
    function marketAddSupply(IMarket market, uint256 assets, uint256 shares, uint256 maxSharePriceE27, address onBehalf)
        external
        onlyBundler3
        onlyApprovedContract(address(market))
    {
        // Do not check `onBehalf` against the zero address as it's done in AltoBaseMarket.
        require(onBehalf != address(this), ErrorsLib.AdapterAddress());

        if (assets == type(uint256).max) {
            assets = IERC20(market.borrowToken()).balanceOf(address(this));
            require(assets != 0, ErrorsLib.ZeroAmount());
        }

        // AltoBaseMarket's allowance is not reset as it is trusted.
        SafeERC20.forceApprove(IERC20(market.borrowToken()), address(market), type(uint256).max);

        (uint256 suppliedAssets, uint256 suppliedShares) = market.addSupply(assets, shares, onBehalf);

        require(suppliedAssets.rDivUp(suppliedShares) <= maxSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Removes supply from the market.
    /// @param market The address of the market.
    /// @param assets The amount of assets to remove.
    /// @param shares The amount of shares to remove.
    /// @param minSharePriceE27 The minimum share price scaled by 1e27 (used for slippage protection).
    /// @param receiver The address of the receiver of the withdrawn assets.
    function marketRemoveSupply(
        IMarket market,
        uint256 assets,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver
    ) external onlyBundler3 onlyApprovedContract(address(market)) {
        if (shares == type(uint256).max) {
            shares = market.position(initiator()).supplyShares;
            require(shares != 0, ErrorsLib.ZeroAmount());
        }

        (uint256 withdrawnAssets, uint256 withdrawnShares) = market.removeSupply(assets, shares, initiator(), receiver);

        require(withdrawnAssets.rDivDown(withdrawnShares) >= minSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Adds collateral to the market.
    /// @param market The address of the market.
    /// @param assets The amount of assets to add.
    /// @param onBehalf The address of the user whose position is collateral being added to.
    function marketAddCollateral(IMarket market, uint256 assets, address onBehalf)
        external
        onlyBundler3
        onlyApprovedContract(address(market))
    {
        // Do not check `onBehalf` against the zero address as it's done at AltoBaseMarket's level.
        require(onBehalf != address(this), ErrorsLib.AdapterAddress());

        if (assets == type(uint256).max) assets = IERC20(market.collateralToken()).balanceOf(address(this));

        require(assets != 0, ErrorsLib.ZeroAmount());

        // AltoBaseMarket's allowance is not reset as it is trusted.
        SafeERC20.forceApprove(IERC20(market.collateralToken()), address(market), type(uint256).max);

        market.addCollateral(assets, onBehalf);
    }

    /// @notice Removes collateral from the market.
    /// @param market The address of the market.
    /// @param assets The amount of assets to remove.
    /// @param receiver The address of the receiver of the withdrawn assets.
    /// @param data The data to pass to the AltoBaseMarket's `removeCollateral` function.
    function marketRemoveCollateral(IMarket market, uint256 assets, address receiver, bytes calldata data)
        external
        onlyBundler3
        onlyApprovedContract(address(market))
    {
        if (assets == type(uint256).max) assets = market.position(initiator()).collateralAssets;
        require(assets != 0, ErrorsLib.ZeroAmount());

        market.removeCollateral(assets, initiator(), receiver, data);
    }

    /// @notice Borrows assets from the market.
    /// @param market The address of the market.
    /// @param assets The amount of assets to borrow.
    /// @param shares The amount of shares to borrow.
    /// @param minSharePriceE27 The minimum share price scaled by 1e27 (used for slippage protection).
    /// @param receiver The address of the receiver of the borrowed assets.
    /// @param data The data to pass to the AltoBaseMarket's `borrow` function.
    function marketBorrow(
        IMarket market,
        uint256 assets,
        uint256 shares,
        uint256 minSharePriceE27,
        address receiver,
        bytes calldata data
    ) external onlyBundler3 onlyApprovedContract(address(market)) {
        (uint256 borrowedAssets, uint256 borrowedShares,) = market.borrow(assets, shares, initiator(), receiver, data);

        require(borrowedAssets.rDivDown(borrowedShares) >= minSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /// @notice Repays assets to the market.
    /// @param market The address of the market.
    /// @param assets The amount of assets to repay.
    /// @param shares The amount of shares to repay.
    /// @param maxSharePriceE27 The maximum share price scaled by 1e27 (used for slippage protection).
    /// @param onBehalf The address of the user whose position is being repaid.
    function marketRepay(IMarket market, uint256 assets, uint256 shares, uint256 maxSharePriceE27, address onBehalf)
        external
        onlyBundler3
        onlyApprovedContract(address(market))
    {
        // Do not check `onBehalf` against the zero address as it's done at AltoBaseMarket's level.
        require(onBehalf != address(this), ErrorsLib.AdapterAddress());

        if (assets == type(uint256).max) {
            assets = IERC20(market.borrowToken()).balanceOf(address(this));
            require(assets != 0, ErrorsLib.ZeroAmount());
        }

        if (shares == type(uint256).max) {
            shares = market.position(onBehalf).borrowShares;
            require(shares != 0, ErrorsLib.ZeroAmount());
        }

        // AltoBaseMarket's allowance is not reset as it is trusted.
        SafeERC20.forceApprove(IERC20(market.borrowToken()), address(market), type(uint256).max);

        (uint256 repaidAssets, uint256 repaidShares) = market.repay(assets, shares, onBehalf);

        require(repaidAssets.rDivUp(repaidShares) <= maxSharePriceE27, ErrorsLib.SlippageExceeded());
    }

    /* TRANSFER ACTIONS */

    /// @notice Transfers ERC20 tokens from the initiator.
    /// @dev Initiator must have given sufficient allowance to the Adapter to spend their tokens.
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

    /* REWARDS ACTIONS */

    function rewardsDistributorClaimRewardTokensWithERC20Transfer(
        IRewardsDistributor rewardsDistributor,
        ClaimData memory claimData,
        bytes32[] calldata proof,
        uint256 rewardsPurchaseAmount,
        address paymentToken,
        uint256 paymentAmount,
        bool lockPurchasedRewards,
        uint256 maxEpochsToLockFor
    ) external onlyBundler3 onlyApprovedContract(address(rewardsDistributor)) {
        // AltoRewardsDistributor's allowance is not reset as it is trusted.
        SafeERC20.forceApprove(IERC20(paymentToken), address(rewardsDistributor), type(uint256).max);

        SafeERC20.safeTransferFrom(IERC20(paymentToken), initiator(), address(this), paymentAmount);

        uint256 amountPaidToDistributor = rewardsDistributor.claimRewardTokens(
            claimData, proof, rewardsPurchaseAmount, paymentToken, lockPurchasedRewards, maxEpochsToLockFor, initiator()
        );

        if (paymentAmount - amountPaidToDistributor != 0) {
            SafeERC20.safeTransfer(IERC20(paymentToken), initiator(), paymentAmount - amountPaidToDistributor);
        }
    }

    /* STAKING ACTIONS */

    /// @notice Locks tokens in the staking contract.
    /// @param staking The address of the staking contract.
    /// @param amount The amount of tokens to lock.
    /// @param containerId The id of the container to lock the tokens in.
    /// @param isReuse Whether to reuse the container.
    /// @param maxEpochsToLockFor The maximum number of epochs to lock for.
    function stakingLock(
        IAltoStaking staking,
        uint256 amount,
        uint256 containerId,
        bool isReuse,
        uint256 maxEpochsToLockFor
    ) external onlyBundler3 onlyApprovedContract(address(staking)) {
        if (!isReuse) {
            // AltoStaking's allowance is not reset as it is trusted.
            SafeERC20.forceApprove(IERC20(staking.LOCK_TOKEN()), address(staking), type(uint256).max);
        }
        staking.lock(initiator(), amount, containerId, isReuse, maxEpochsToLockFor);
    }

    /// @notice Unlocks tokens from the staking contract.
    /// @param staking The address of the staking contract.
    /// @param receiver The address to send the unlocked tokens to.
    /// @param containerId The id of the container to unlock the tokens from.
    function stakingUnlock(IAltoStaking staking, address receiver, uint256 containerId)
        external
        onlyBundler3
        onlyApprovedContract(address(staking))
    {
        staking.unlock(initiator(), receiver, containerId);
    }

    /// @notice Claims reward tokens from the rewards distributor.
    /// @param rewardsDistributor The address of the rewards distributor.
    /// @param rewardToken The address of the reward token.
    /// @param amount The amount of reward tokens to claim.
    /// @param proof The merkle proof that validates this claim.
    function claimRewardTokens(
        IUniversalRewardsDistributor rewardsDistributor,
        address rewardToken,
        uint256 amount,
        bytes32[] calldata proof
    ) external onlyBundler3 onlyApprovedContract(address(rewardsDistributor)) {
        rewardsDistributor.claim(initiator(), rewardToken, amount, proof);
    }

    /* VESTING ACTIONS */

    /// @notice Claims the vested tokens from the vesting contract.
    /// @param vesting The address of the vesting contract.
    /// @param vestingInfo The vesting info struct
    /// @param proof The merkle proof that validates this claim.
    function claimVestedTokens(IAltoVesting vesting, VestingInfo memory vestingInfo, bytes32[] calldata proof)
        external
        onlyBundler3
        onlyApprovedContract(address(vesting))
    {
        vesting.claim(initiator(), vestingInfo, proof);
    }

    /* USM ACTIONS */

    /// @notice Buys assets from the USM.
    /// @param usm The address of the USM.
    /// @param minAmount The minimum amount of assets to buy.
    /// @param maxStableTokenAmount The maximum amount of Stable Token to pay.
    /// @param receiver The address of the receiver of the assets.
    function usmBuyAssetWithERC20Transfer(IUsm usm, uint256 minAmount, uint256 maxStableTokenAmount, address receiver)
        external
        onlyBundler3
        onlyApprovedContract(address(usm))
    {
        address stableToken = usm.STABLE_TOKEN();

        // USM's allowance is not reset as it is trusted.
        SafeERC20.forceApprove(IERC20(stableToken), address(usm), type(uint256).max);

        SafeERC20.safeTransferFrom(IERC20(stableToken), initiator(), address(this), maxStableTokenAmount);

        (, uint256 stableTokenSold) = usm.buyAsset(minAmount, receiver);

        if (maxStableTokenAmount - stableTokenSold != 0) {
            SafeERC20.safeTransfer(IERC20(stableToken), initiator(), maxStableTokenAmount - stableTokenSold);
        }
    }

    /// @notice Sells assets from the USM.
    /// @param usm The address of the USM.
    /// @param maxAmount The maximum amount of underlying assets to sell.
    /// @param minStableTokenAmount The minimum amount of Stable Token to receive.
    /// @param receiver The address of the receiver of the Stable Token.
    function usmSellAssetWithERC20Transfer(IUsm usm, uint256 maxAmount, uint256 minStableTokenAmount, address receiver)
        external
        onlyBundler3
        onlyApprovedContract(address(usm))
    {
        address underlyingAsset = usm.UNDERLYING_ASSET();

        // USM's allowance is not reset as it is trusted.
        SafeERC20.forceApprove(IERC20(underlyingAsset), address(usm), type(uint256).max);

        SafeERC20.safeTransferFrom(IERC20(underlyingAsset), initiator(), address(this), maxAmount);

        (uint256 assetAmountSold, uint256 stableTokenBought) = usm.sellAsset(maxAmount, receiver);

        require(stableTokenBought >= minStableTokenAmount, ErrorsLib.SlippageExceeded());

        if (maxAmount - assetAmountSold != 0) {
            SafeERC20.safeTransfer(IERC20(underlyingAsset), initiator(), maxAmount - assetAmountSold);
        }
    }
}
