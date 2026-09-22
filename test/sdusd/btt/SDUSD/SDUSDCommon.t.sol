// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {SDUSDInitParams} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ProtocolFeeCollectorCommon} from "../ProtocolFeeCollector/ProtocolFeeCollectorCommon.t.sol";

abstract contract SDUSDCommon is ProtocolFeeCollectorCommon {
    uint256 internal constant EXCHANGE_RATE_SCALE = 1 ether;
    address internal constant SEED_LOCK = address(1);
    uint256 internal constant REWARD_AMOUNT = 70 ether;

    address internal RECEIVER = makeAddr("Receiver");
    address internal SPENDER = makeAddr("Spender");
    address internal NEW_REWARDER = makeAddr("NewRewarder");
    address internal NEW_PAUSER = makeAddr("NewPauser");

    SDUSD internal vault;

    struct ExchangeRateSnapshot {
        uint256 totalAssets;
        uint256 totalSupply;
    }

    function setUp() public virtual override {
        super.setUp();
        vault = sdusdVault;
    }

    function _deployVault(uint256 seedShares_, uint256 rewardDuration_) internal returns (SDUSD deployed) {
        deployed = _deploySdusdVault(_sdusdInitParams(seedShares_, rewardDuration_));
    }

    function _deployVaultWithCap(uint256 seedShares_, uint256 rewardDuration_, uint256 depositCap_)
        internal
        returns (SDUSD deployed)
    {
        SDUSDInitParams memory params = _sdusdInitParams(seedShares_, rewardDuration_);
        params.depositCap = depositCap_;
        deployed = _deploySdusdVault(params);
    }

    function _useEmptyVault() internal returns (SDUSD deployed) {
        deployed = _deployVault(SEED_SHARES, REWARD_DURATION);
        vault = deployed;
    }

    function _depositFor(address depositor, uint256 assets) internal returns (uint256 shares) {
        dusd.mint(depositor, assets);
        vm.startPrank(depositor);
        dusd.approve(address(vault), assets);
        shares = vault.deposit(assets, depositor);
        vm.stopPrank();
    }

    function _mintFor(address minter, uint256 shares) internal returns (uint256 assets) {
        assets = vault.previewMint(shares);
        dusd.mint(minter, assets);
        vm.startPrank(minter);
        dusd.approve(address(vault), assets);
        assets = vault.mint(shares, minter);
        vm.stopPrank();
    }

    function _notifyRewards(uint256 amount) internal {
        dusd.mint(address(collector), amount);
        vm.prank(address(collector));
        dusd.approve(address(vault), amount);
        vm.prank(address(collector));
        vault.notifyRewardAmount(amount);
    }

    function _finishRewardPeriod() internal {
        vm.warp(vault.rewardPeriodFinish());
    }

    function _pauseVault() internal {
        vm.prank(PAUSER);
        vault.pause(PAUSE_TYPE, true);
    }

    function _freezeVault() internal {
        vm.prank(PAUSER);
        vault.pause(FROZEN_TYPE, true);
    }

    function _setDepositCap(uint256 newDepositCap) internal {
        vm.prank(ADMIN);
        vault.setDepositCap(newDepositCap);
    }

    function _donate(uint256 amount) internal {
        dusd.mint(address(vault), amount);
    }

    function _expectedShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        return Math.mulDiv(assets, vault.totalSupply() + 1, vault.totalAssets() + 1, rounding);
    }

    function _expectedAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        return Math.mulDiv(shares, vault.totalAssets() + 1, vault.totalSupply() + 1, rounding);
    }

    /// @dev Assets represented by one whole sDUSD share, using the same virtual asset/share pair as OZ ERC-4626.
    function _exchangeRate() internal view returns (uint256) {
        return Math.mulDiv(vault.totalAssets() + 1, EXCHANGE_RATE_SCALE, vault.totalSupply() + 1);
    }

    function _snapshotExchangeRate() internal view returns (ExchangeRateSnapshot memory snapshot) {
        snapshot = ExchangeRateSnapshot({totalAssets: vault.totalAssets(), totalSupply: vault.totalSupply()});
    }

    /// @dev Compares the exact virtualized ratios by cross multiplication so integer display rounding cannot hide
    ///      a rate change. Test fixture values are deliberately far below the multiplication overflow boundary.
    function _assertExchangeRateUnchanged(ExchangeRateSnapshot memory beforeSnapshot) internal view {
        assertEq(
            (vault.totalAssets() + 1) * (beforeSnapshot.totalSupply + 1),
            (beforeSnapshot.totalAssets + 1) * (vault.totalSupply() + 1),
            "exchange rate changed"
        );
    }

    /// @dev ERC-4626 directional rounding may leave dust for remaining holders but must never dilute them.
    function _assertExchangeRateNotDecreased(ExchangeRateSnapshot memory beforeSnapshot) internal view {
        assertGe(
            (vault.totalAssets() + 1) * (beforeSnapshot.totalSupply + 1),
            (beforeSnapshot.totalAssets + 1) * (vault.totalSupply() + 1),
            "exchange rate decreased"
        );
    }
}
