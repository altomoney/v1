# Peg IRM audit scope

[`PegResponsiveExponentialIrm`](./PegResponsiveExponentialIrm.sol) controls a Mint
Market's borrow rate using DUSD/quoteToken. The intended adapter is
[`DusdPegCurveOracle`](../../oracles/DusdPegCurveOracle/README.md), with frxUSD as
the quote token. External audit and production parameter approval are pending.

## Rate and accounting rules

- Prices, distances, and rates use 1e18 precision. Rates are per-second yield
  (SPY), not APY. The raw curve is flat above recovery, linear between recovery
  and stress, and exponential below stress, capped at `maxRate`. Stress mode
  enforces a `stressRate` floor until recovery is confirmed.
- A checkpoint accrues the elapsed interval at the stored rate, then samples
  the oracle and stores the next rate. The returned rate is the old rate used
  for accrual. The Mint Market adds interest to debt and fees without issuing
  borrow shares.
- Owner oracle/configuration changes checkpoint the active market under the old
  inputs, then immediately refresh the rate under the new inputs. They preserve
  stress hysteresis and restart recovery confirmation. Invalid observations hold
  the rate within the new applicable floor and cap. Paused and unbound setters
  refresh without accruing or advancing `lastUpdate`.

## Accepted limitations

- **Checkpoint liveness:** Pool activity does not execute the IRM. Off-chain
  execution must call permissionless `market.accrueInterest()`. There is no
  on-chain maximum gap. Monitor source validity/age separately from checkpoint
  age, since invalid observations still advance `lastUpdate`.
- **Idle interest:** The shared `FixedPointMath.calculateCompoundInterest` uses
  a Taylor approximation capped at a `1e20` interest factor per call. With debt
  outstanding, long gaps can accrue materially less than frequent checkpoints.
  Later calls do not recover the difference. `ExpLib.wExp` also uses an
  approximation. Independent numerical error bounds remain an audit item.
- **Sampled recovery:** A valid price at or below `stressPrice` enters stress.
  Healthy observations at or above `recoveryPrice`, separated by `recoveryDelay`,
  can exit it. Invalid or below-recovery observations clear confirmation.
  This does not prove continuous recovery. Configure
  `0 < maxOracleAge < recoveryDelay` to prevent one observation from starting and
  completing recovery. This relationship is not enforced on-chain.
- **Oracle failure:** Reverts, invalid flags, zero prices, and zero, future, or
  stale timestamps hold the rate and stress mode while clearing recovery.
  Accrual continues. A held low rate can miss a depeg, and a held high rate can
  outlast recovery. There is no fallback feed or automatic borrowing restriction.
- **Oracle trust:** The intended non-upgradeable adapter returns its declared ABI
  or reverts, including on pool-read failures. Malformed successful responses
  are outside this integration assumption. Replacement adapters require review.
  Typed `try/catch` is not a general malformed-data decoder. An incompatible
  source can block accrual, and active replacement first checkpoints the old source.
- **First binding:** `setMarket()` is permissionless and one-shot. An attacker
  can claim an unbound instance, causing deployment cost and delay. An already
  bound instance cannot be reassigned. Deploy/install atomically, verify both
  market/IRM bindings, and discard a misbound instance. Binding does not sample
  the oracle, so checkpoint on installation.

## Pause and operational requirements

The market checkpoints before pausing. Unpause resets the accrual timestamp and
recovery timer, retains the stored rate, and does not sample the oracle. Batch
`market.pause(PAUSE_TYPE, false)` then `market.accrueInterest()` in one owner
transaction. This refreshes before another transaction uses the market and
excludes paused time from interest. Invalid observations retain the held-rate policy.

Before deployment, approve parameters and owners, assign checkpoint cadence and
executor/alert responsibility, and rehearse installation and unpause batches.
Persistent oracle failures require an owner response to restore approved pool
settings or replace the adapter.

## Audit evidence and gaps

[IRM tests](../../../test/lending/btt/PegResponsiveExponentialIrm) and
[adapter integration tests](../../../test/oracles/DusdPegOracle/DusdPegOracleIntegration.t.sol)
cover rate bounds, recovery, pause, replacement, debt accounting, and rollback.
Independent math verification, long-sequence market accounting, and economic
parameter approval remain open.
