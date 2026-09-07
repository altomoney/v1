# Curve peg oracle audit scope

[`DusdPegCurveOracle`](./DusdPegCurveOracle.sol) returns the Curve EMA price of
DUSD in the quote token, intended to be frxUSD. QuoteToken/USD is not composed
into the price. Quote-token basis risk is accepted and monitored separately.
External audit and production approval are pending.

## Source and validation

- The adapter is non-upgradeable and immutably bound to one Curve StableSwap NG
  pool. Construction verifies factory registration, the approved implementation,
  a non-meta two-coin pool, `[quoteToken, DUSD]` order, distinct tokens, and
  standard ERC-20 asset type `0` for both.
- Every price read checks approved `ma_exp_time`, current `A_precise`, and
  `future_A`. Drift invalidates the observation. Owner-only `setRuntimeConfig()`
  requires values matching the live pool with no amplification ramp in progress.
  Fees and the off-peg fee multiplier are not pinned.
- `getPrice()` returns the declared `(uint256, uint48, bool)` ABI or reverts.
  Policy failures return `valid = false`. Source-call failures revert and the
  intended IRM applies its held-rate policy. Severe depegs remain valid prices.
- `observedAt` comes from the low 128 bits of `ma_last_time`, not the invariant
  timestamp in the high bits. Zero, future, and oversized timestamps are invalid.
  The adapter imposes no age limit. The IRM applies `maxOracleAge`.
- `price_oracle(0)` projects the EMA from the last stored pool state price.
  Its value can change without a new observation timestamp. Smoothing does not
  guarantee freshness or checkpoint liveness. `rawPoolState()` is unvalidated
  diagnostics and must not serve as a protocol price feed.

## Economic assumptions and operations

This Curve pool is assumed to be the dominant DUSD price venue. The design uses
no second feed or reserve floor. Liquidity withdrawals can leave the price valid
while making sustained manipulation cheaper. High amplification can hide large
imbalances near peg, and EMA smoothing does not prevent sustained manipulation.

Monitor balances, LP supply, imbalance, fees, amplification, EMA settings,
quote-token peg, source age, and market debt exposure. Approve economic alert
thresholds and assign a response. Review the single-venue assumption as other
DUSD markets grow. Restoring approved pool settings or replacing the adapter
requires the relevant owner. Active IRM replacement checkpoints the old source first.

## Audit evidence and gaps

[Unit tests](../../../test/oracles/btt/DusdPegCurveOracle),
[fuzz/integration tests](../../../test/oracles/DusdPegOracle), and the
[mainnet fork suite](../../../test/oracles/DusdPegOracle/DusdPegOracleFork.t.sol)
cover source validation and IRM consumption. The fork is pinned to block
`25_746_611`. Production identity/parameter approval and manipulation-cost
analysis remain open. Retain factory, implementation, token, and administrative
addresses in the deployment record, since constructor validation inputs are
not all stored as getters.
