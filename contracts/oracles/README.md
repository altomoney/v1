# Alto Protocol Oracle Usage Guidelines

This document summarizes the oracle modules currently used by Alto, how they compose into concrete oracle contracts, and what rounding direction they apply.

## Audited Scope

The following modules and composed oracles are in scope for the current audited oracle stack:

### Core modules

- `ModuleChainlink` - Chainlink conversion module, rounds down
- `ModuleERC4626Ratio` - caps ERC4626 / LST growth, rounds down
- `ModuleLinearDiscount` - applies a time-based PT discount, rounds down overall
- `ModuleMultiplier` - scales an input by a fixed multiplier
- `ModuleUniswap` - Uniswap TWAP module with configurable `roundUp`
- `ModuleUniswap/OracleMath` - precision math helpers used by `ModuleUniswap`
- `ModuleUniswap/FullMath` - mul/div helper used by oracle math

### Composed oracles

- `AltoMultiChainlinkLendingOracle` - lending oracle built from `ModuleChainlink`
- `AltoERC4626RatioChainlinkOracle` - `ModuleERC4626Ratio` + `ModuleChainlink`
- `AltoChainlinkERC4626RatioMultiplierOracle` - `ModuleChainlink` + `ModuleERC4626Ratio` + `ModuleMultiplier`
- `AltoERC4626RatioLinearDiscountOracle` - `ModuleERC4626Ratio` + `ModuleLinearDiscount`
- `AltoRewardsOracle` - `ModuleUniswap` + `ModuleChainlink`

---

## Lending / Collateral Scenarios (Round DOWN)

**When to use floor division:**
- Valuing user collateral deposits
- Calculating maximum borrowing capacity

**Goal:** Be conservative to keep protocol solvent - undervaluing collateral protects the protocol.

**Oracles:**
- `AltoMultiChainlinkLendingOracle` - uses `ModuleChainlink` (floors)
- `AltoERC4626RatioChainlinkOracle` - uses `ModuleERC4626Ratio` (floors) + `ModuleChainlink` (floors)
- `AltoChainlinkERC4626RatioMultiplierOracle` - uses `ModuleChainlink` (floors) + `ModuleERC4626Ratio` (floors) + `ModuleMultiplier`
- `AltoERC4626RatioLinearDiscountOracle` - uses `ModuleERC4626Ratio` (floors) + `ModuleLinearDiscount` (floors overall)

**Notes:**
- Alto lending consumers expect `getPrice()` to follow the lending oracle precision convention based on `LENDING_ORACLE_PRICE_PRECISION`, including token decimal offsets.
- `ModuleERC4626Ratio` assumes the underlying ratio is monotonically non-decreasing.
- `ModuleLinearDiscount` is intended for PT-style assets where a deterministic haircut to maturity is acceptable.

---

## Payment Scenarios (Round UP)

**When to use ceiling division:**
- Calculating payment amounts users must transfer
- Pricing tokens users are purchasing

**Goal:** Prevent value leakage from accumulated rounding - protocol should never receive less than owed.

**Current support:**
- `ModuleUniswap` - supports `roundUp` via `UniswapNode.roundUp`
- `ModuleChainlink` - **does not support** ceiling division
- `ModuleMultiplier` - applies a raw scalar multiplier; no directional rounding mode
- `ModuleLinearDiscount` - no configurable rounding mode; final result rounds down

**Options:**
1. Set `roundUp: true` in `UniswapNode` config when the flow supports Uniswap pricing
2. Round up at the consumer contract level after the oracle call
3. Add explicit round-up support to the relevant module if the use case requires it

---

## `AltoRewardsOracle`

Used for pricing ALTO tokens in `AltoRewardsDistributor` (exercise price for call options).

**Current behavior:**
1. `ModuleUniswap` with `roundUp: true` - rounds up the TWAP price
2. `ModuleChainlink` - rounds down when converting to USD

**Net effect:** Chainlink floors a value that was already ceiled by Uniswap, so the final result is closer to the true value than if both rounded in the same direction. The Uniswap round-up compensates for Chainlink's round-down.

---

## Reverse Flows (Not Currently Supported)

If the protocol adds inverse operations, rounding direction must flip:

| Flow | Current Rounding | Reverse Flow | Required Rounding |
|------|------------------|--------------|-------------------|
| Deposit collateral → borrow DUSD | DOWN (conservative) | Deposit DUSD → borrow collateral | UP |
| Pay stablecoins → receive ALTO | UP (protocol favored) | Sell ALTO → receive stablecoins | DOWN |

