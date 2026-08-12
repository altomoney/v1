# `PegResponsiveIrm` Handoff Notes and Open Decisions

This document complements the component [README](./README.md) by tracking
design and integration decisions that must be resolved before the
peg-responsive IRM can be confirmed for production.

These entries are not all implementation bugs. Some are deliberate current
behaviors whose safety depends on an explicit protocol decision, an operational
guarantee, or evidence from the main Alto repository.

## How to close an item

Do not close an item only because the current code compiles or its isolated
tests pass. A closed item should record:

1. the chosen behavior;
2. why it was selected over the alternatives;
3. the owner or team that approved it;
4. links to the implementing pull request or specification;
5. unit, fuzz, invariant, integration, or operational evidence as applicable;
   and
6. any monitoring or governance requirement that remains off-chain.

When a decision is complete, change its top-level checkbox to `[x]` and replace
`Decision: Pending` with the final decision and supporting links.

## Controller semantics

- [ ] **PRM-001: Define checkpoint liveness and the maximum response latency**

  **Current behavior**

  `PegResponsiveIrm` is a lazy, checkpoint-driven controller. Oracle updates do
  not execute the IRM. Until the market checkpoints, the previously stored rate
  continues to accrue.

  `maxOracleAge` validates an observation only when a checkpoint happens. It
  does not create a checkpoint or bound the time between checkpoints. The
  market exposes permissionless `accrueInterest()` while unpaused, but no
  keeper or service-level objective is encoded in the PRM.

  **Decision required**

  - Define the maximum intended checkpoint interval.
  - Decide whether the bound differs between healthy and stressed conditions.
  - Identify the keeper, automation, or other liveness mechanism.
  - Define monitoring and escalation when the interval is exceeded.
  - Define expected behavior while the market is paused or the keeper is
    unavailable.

  **Closure evidence**

  - [ ] Maximum checkpoint interval documented.
  - [ ] Keeper ownership, funding, redundancy, and failure response documented.
  - [ ] Permissionless checkpointing confirmed in the real Mint Market.
  - [ ] Integration test demonstrates the expected cadence.

  **Decision:** Pending.

- [ ] **PRM-002: Define what constitutes confirmed recovery**

  **Current behavior**

  Recovery is based on qualifying checkpoints:

  1. A valid checkpoint at or above `recoveryPrice` starts a block-time timer.
  2. At least `recoveryDelay` wall-clock time passes.
  3. A later checkpoint reads a valid price at or above `recoveryPrice`.

  The controller cannot prove continuous recovery between checkpoints. It also
  does not track the oracle observation that started recovery. If
  `maxOracleAge >= recoveryDelay`, the same still-fresh observation can
  potentially start and complete recovery.

  The current test fixture uses a six-hour recovery delay and a thirty-minute
  maximum oracle age, which prevents reuse of one observation in that fixture.
  The contract does not enforce that relationship for other configurations.

  **Decision required**

  Choose and specify one recovery guarantee:

  - accept two qualifying checkpoints and document that the same observation
    may be reused;
  - require `maxOracleAge < recoveryDelay`;
  - track `recoveryStartObservedAt` and require a newer recovery observation;
  - require oracle observation time to span the full recovery delay; or
  - use an oracle capable of proving the required historical interval.

  Also decide whether recovery timing should be anchored to block time, oracle
  time, or both.

  **Closure evidence**

  - [ ] Recovery guarantee written as a precise state-machine specification.
  - [ ] Configuration validation updated if parameters require a relationship.
  - [ ] Same-observation start/completion case explicitly tested.
  - [ ] Exact `delay - 1`, `delay`, and `delay + 1` behavior retained.
  - [ ] README and interface terminology use “sampled” or “qualifying
        observations” unless continuity is actually proven.

  **Decision:** Pending.

- [ ] **PRM-003: Select the invalid-oracle risk policy**

  **Current behavior**

  Invalid, stale, zero, future, or reverting observations:

  - leave the stored rate unchanged;
  - preserve the current stress-mode flag;
  - clear recovery confirmation; and
  - advance `lastUpdate` after a successful market checkpoint.

  This is fail-static rather than uniformly conservative. It retains a high
  rate when failure occurs during stress, but it can also retain `baseRate`
  indefinitely when failure coincides with an unobserved depeg.

  **Decision required**

  Decide whether to:

  - keep the current rate indefinitely;
  - introduce a separately configured oracle-failure rate;
  - block or limit new minting/borrowing while leaving existing-debt accrual
    unchanged;
  - pause selected market actions; or
  - use a fallback oracle.

  **Closure evidence**

  - [ ] Policy documented.
  - [ ] Fallback behavior documented if used.
  - [ ] Market and IRM integration tests cover invalidity before and during
        stress.
  - [ ] Monitoring and emergency governance response documented.

  **Decision:** Pending.

- [ ] **PRM-004: Decide when new oracle and curve inputs take effect**

  **Current behavior**

  `setPegOracle()` and `setIrmConfig()` checkpoint the market under the old
  inputs before installing the new inputs. That checkpoint also installs an
  old-input-derived next rate. The new oracle or curve does not determine the
  live rate until a later checkpoint.

  This can temporarily leave:

  - a stored rate below a new `baseRate`;
  - a stored rate below a new `stressRate`;
  - stress state inconsistent with new price thresholds; or
  - an old-oracle-derived rate active after oracle replacement.

  **Decision required**

  Choose between:

  - deferred application at the next ordinary checkpoint; or
  - an immediate zero-elapsed controller refresh after installing new inputs.

  If refreshing immediately, specify:

  - how stress mode is re-evaluated;
  - how recovery confirmation is reset or restarted;
  - what happens if the new oracle observation is unusable;
  - which events are emitted; and
  - whether the same rule applies when initially binding the market.

  **Closure evidence**

  - [ ] Effective-time semantics documented.
  - [ ] Oracle and configuration replacement tests assert the selected
        behavior.
  - [ ] Stored rate is checked against every new configured rate bound required
        by the specification.
  - [ ] Integration test covers replacement while healthy, stressed, recovering,
        paused, and unbound.

  **Decision:** Pending.

- [ ] **PRM-005: Decide how the rate is refreshed after unpause**

  **Current behavior**

  The market is expected to accrue immediately before pausing. On unpause, the
  IRM moves `lastUpdate` to the current time and clears recovery confirmation.
  It does not read the oracle or update `borrowRate`.

  The pre-pause rate therefore remains active until the next checkpoint. The
  PRM makes no guarantee that a post-unpause checkpoint occurs.

  **Decision required**

  Choose between:

  - refreshing the controller during the unpause hook;
  - requiring an atomic or immediate market checkpoint after unpause;
  - assigning the responsibility to keeper infrastructure with a defined
    maximum delay; or
  - explicitly accepting continued use of the pre-pause rate.

  Consider the trade-off between rate freshness and making unpause dependent on
  an external oracle read.

  **Closure evidence**

  - [ ] Main-market pause hook ordering confirmed.
  - [ ] Pre-pause checkpoint requirement confirmed.
  - [ ] Post-unpause rate policy documented.
  - [ ] Integration tests cover deep depeg and full recovery during a pause.
  - [ ] Oracle-invalid unpause behavior tested.

  **Decision:** Pending.

## Numerical dependencies

- [ ] **PRM-007: Validate trusted math libraries and the supported domain**

  **Current behavior**

  The PRM reuses the main repository's:

  - `ExpLib.wExp` for the raw stress curve; and
  - `FixedPointMath.calculateCompoundInterest` and
    `multiplyWithPrecision` for elapsed interest.

  The current work tests PRM integration and mathematical properties around
  these libraries but does not independently prove either implementation.
  Some test expectations reuse the same production helpers.

  **Decision required**

  - Decide whether upstream trust is acceptable or independent verification is
    required before merge.

  **Closure evidence**

  - [ ] Independent high-precision curve comparison completed.
  - [ ] Independent high-precision compound-interest comparison completed.
  - [ ] Rounding and maximum-error bounds documented.
  - [ ] Library versions and provenance pinned.
  - [ ] Security review covers both libraries.

  **Decision:** Pending.

## Market and deployment integration

- [ ] **PRM-008: Confirm one-shot market binding is safe in deployment**

  **Current behavior**

  `setMarket()` is permissionless, accepts one nonzero address, and can only
  succeed once. The design assumes deterministic deployment binds the intended
  market atomically.

  **Decision required**

  - Confirm the actual deployment transaction makes front-running impossible.
  - Decide whether permissionless one-shot binding remains acceptable outside
    that deployment path.
  - Define recovery if deployment fails after IRM creation but before binding.

  **Closure evidence**

  - [ ] Main deployment contracts reviewed.
  - [ ] Atomic deployment/binding integration test added.
  - [ ] Mis-binding/front-running scenario tested.
  - [ ] Deployment runbook verifies the final market address.

  **Decision:** Pending.

- [ ] **PRM-009: Validate real Mint Market accrual and accounting**

  **Current evidence**

  The Mint Market passes debt before accrual, receives `(interest, borrowRate)`,
  adds interest to total borrowed assets and claimable fees, and emits an accrual
  event. The isolated mock is not a complete reproduction of that accounting.

  **Decision required**

  Confirm the behavior against the current main-repository market, including:

  - debt and share accounting;
  - fee accounting;
  - rounding and `uint128` conversions;
  - all operations that trigger accrual;
  - repeated checkpoints without replacing totals;
  - zero debt and maximum debt; and
  - revert atomicity if accounting cannot apply the returned interest.

  **Closure evidence**

  - [ ] Integration suite deploys the actual Mint Market.
  - [ ] Sequential debt/share/fee conservation properties tested.
  - [ ] Every rate-sensitive market action shown to checkpoint as expected.
  - [ ] Accrual event semantics confirmed.
  - [ ] Long-sequence market-accounting invariant campaign completed or
        explicitly waived with rationale.

  **Decision:** Pending.
