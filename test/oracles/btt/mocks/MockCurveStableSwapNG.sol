// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ICurveStableSwapNGBase, ICurveStableSwapNGOracle} from "@alto/interfaces/curve/ICurveStableSwapNG.sol";

/// @notice Minimal stateful mock of the Curve StableSwap NG pool reads used by
/// `DusdPegCurveOracle`.
/// @dev The mock preserves Curve's externally visible array shapes and packing
/// conventions. Test-only setters replace Curve's AMM and EMA calculations so
/// callers can exercise adapter boundary conditions deterministically.
contract MockCurveStableSwapNG is ICurveStableSwapNGOracle {
    error InvalidInitialization();
    error InvalidBalancesLength();

    uint256 private constant MIN_COINS = 2;
    uint256 private constant MAX_COINS = 8;
    uint256 private constant UINT128_MASK = type(uint128).max;

    /// @inheritdoc ICurveStableSwapNGBase
    uint256 public immutable override N_COINS;

    /// @inheritdoc ICurveStableSwapNGOracle
    uint256 public override future_A;

    /// @inheritdoc ICurveStableSwapNGOracle
    uint256 public override ma_exp_time;

    /// @inheritdoc ICurveStableSwapNGOracle
    uint256 public override ma_last_time;

    uint256 private s_aPrecise;
    address[] private s_coins;
    uint256[] private s_currentStatePrices;
    uint256[] private s_lastPricesPacked;
    uint256[] private s_projectedEmaPrices;
    uint256[] private s_balances;

    /// @param coins_ Coins in pool order.
    /// @param maExpTime_ EMA averaging time.
    /// @param aPrecise_ Current and future precise amplification coefficient.
    constructor(address[] memory coins_, uint256 maExpTime_, uint256 aPrecise_) {
        N_COINS = coins_.length;
        if (N_COINS < MIN_COINS || N_COINS > MAX_COINS || maExpTime_ == 0 || aPrecise_ == 0) {
            revert InvalidInitialization();
        }
        for (uint256 i; i < N_COINS; ++i) {
            if (coins_[i] == address(0)) revert InvalidInitialization();
            for (uint256 j = i + 1; j < N_COINS; ++j) {
                if (coins_[i] == coins_[j]) revert InvalidInitialization();
            }
        }

        s_coins = coins_;
        ma_exp_time = maExpTime_;
        ma_last_time = _pack128(uint128(block.timestamp), uint128(block.timestamp));
        future_A = aPrecise_;
        s_aPrecise = aPrecise_;
        s_balances = new uint256[](coins_.length);

        uint256 oracleCount = coins_.length - 1;
        for (uint256 i; i < oracleCount; ++i) {
            s_currentStatePrices.push(1e18);
            s_lastPricesPacked.push(_pack128(1e18, 1e18));
            s_projectedEmaPrices.push(1e18);
        }
    }

    /// @inheritdoc ICurveStableSwapNGBase
    function coins(uint256 index) external view override returns (address coin) {
        return s_coins[index];
    }

    /// @inheritdoc ICurveStableSwapNGOracle
    function A_precise() external view override returns (uint256 preciseA) {
        return s_aPrecise;
    }

    /// @inheritdoc ICurveStableSwapNGOracle
    function get_p(uint256 index) external view override returns (uint256 statePriceWad) {
        return s_currentStatePrices[index];
    }

    /// @inheritdoc ICurveStableSwapNGOracle
    function last_price(uint256 index) external view override returns (uint256 statePriceWad) {
        return s_lastPricesPacked[index] & UINT128_MASK;
    }

    /// @inheritdoc ICurveStableSwapNGOracle
    function ema_price(uint256 index) external view override returns (uint256 emaPriceWad) {
        return s_lastPricesPacked[index] >> 128;
    }

    /// @inheritdoc ICurveStableSwapNGOracle
    function price_oracle(uint256 index) external view override returns (uint256 emaPriceWad) {
        return s_projectedEmaPrices[index];
    }

    /// @inheritdoc ICurveStableSwapNGOracle
    function get_balances() external view override returns (uint256[] memory balances) {
        return s_balances;
    }

    /// @notice Sets the current EMA averaging time.
    function setMaExpTime(uint256 maExpTime_) external {
        ma_exp_time = maExpTime_;
    }

    /// @notice Sets the current precise amplification coefficient.
    function setAPrecise(uint256 aPrecise_) external {
        s_aPrecise = aPrecise_;
    }

    /// @notice Sets the target precise amplification coefficient.
    function setFutureA(uint256 futureA_) external {
        future_A = futureA_;
    }

    /// @notice Sets Curve's packed price and invariant timestamps.
    function setMaLastTime(uint256 packedTimestamps) external {
        ma_last_time = packedTimestamps;
    }

    /// @notice Replaces the balances, net of admin fees, returned in pool coin order.
    function setBalances(uint256[] calldata balances_) external {
        if (balances_.length != N_COINS) revert InvalidBalancesLength();
        s_balances = balances_;
    }

    /// @notice Sets all price values exposed for one Curve oracle index.
    /// @dev StableSwap NG stores `lastPriceWad` in the low 128 bits and
    /// `storedEmaPriceWad` in the high 128 bits of one packed word.
    function setPriceData(
        uint256 index,
        uint256 currentStatePriceWad,
        uint128 lastPriceWad,
        uint128 storedEmaPriceWad,
        uint256 projectedEmaPriceWad
    ) external {
        s_currentStatePrices[index] = currentStatePriceWad;
        s_lastPricesPacked[index] = _pack128(lastPriceWad, storedEmaPriceWad);
        s_projectedEmaPrices[index] = projectedEmaPriceWad;
    }

    /// @dev Matches Curve's `pack_2`: first value in the low half and second
    /// value in the high half.
    function _pack128(uint128 low, uint128 high) private pure returns (uint256 packed) {
        return uint256(low) | (uint256(high) << 128);
    }
}
