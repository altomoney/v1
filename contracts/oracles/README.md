# Alto Protocol Oracle Usage Guidelines

This document describes the correct usage of oracle functions based on rounding requirements.

## Lending/Collateral Scenarios (Round DOWN)

**When to use floor division:**
- Valuing user collateral deposits
- Calculating maximum borrowing capacity

**Goal:** Be conservative to keep protocol solvent — undervaluing collateral protects the protocol.

**Oracles:**
- `AltoMultiChainlinkLendingOracle` — uses `ModuleChainlink` (floors)
- `AltoERC4626RatioChainlinkOracle` — uses `ModuleERC4626Ratio` (floors) + `ModuleChainlink` (floors)

---

## Payment Scenarios (Round UP)

**When to use ceiling division:**
- Calculating payment amounts users must transfer
- Pricing tokens users are purchasing

**Goal:** Prevent value leakage from accumulated rounding — protocol should never receive less than owed.

**Current Support:**
- `ModuleUniswap` — supports `roundUp` via `UniswapNode.roundUp` field
- `ModuleChainlink` — **does NOT support** ceiling division

**Options:**
1. Set `roundUp: true` in `UniswapNode` config (if only using Uniswap)
2. Round up at the consumer contract level after oracle call
3. Add `roundUp` parameter to `ModuleChainlink` if needed

---

## AltoRewardsOracle

Used for pricing ALTO tokens in `AltoRewardsDistributor` (exercise price for call options).

**Current behavior:** 
1. `ModuleUniswap` with `roundUp: true` — rounds UP the TWAP price
2. `ModuleChainlink` — rounds DOWN when converting to USD

**Net effect:** Chainlink floors a value that was already ceiled by Uniswap, so the final result is closer to the true value than if both rounded in the same direction. The Uniswap round-up compensates for Chainlink's round-down.

---

## Reverse Flows (Not Currently Supported)

If the protocol adds inverse operations, rounding direction must flip:

| Flow | Current Rounding | Reverse Flow | Required Rounding |
|------|------------------|--------------|-------------------|
| Deposit collateral → borrow DUSD | DOWN (conservative) | Deposit DUSD → borrow collateral | UP |
| Pay stablecoins → receive ALTO | UP (protocol favored) | Sell ALTO → receive stablecoins | DOWN |

