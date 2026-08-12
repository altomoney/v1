# `DusdPegOracleCurve` Handoff Notes and Open Decisions

This document complements the component [README](./README.md). It records the
assumptions, unresolved decisions, and evidence required before the Curve oracle
can be approved for production.

These entries are not all implementation bugs. Some are deliberate current
behaviors whose safety depends on an explicit protocol decision, economic
analysis, a reviewed deployment record, or operational controls.

## How to close an item

A closed item should record:

1. the selected behavior and its rationale;
2. the team or owner that approved it;
3. links to the specification and implementing change;
4. deterministic, fork, integration, or economic evidence as applicable; and
5. any monitoring or governance requirement that remains off-chain.

Change a top-level checkbox to `[x]` only when that evidence is attached.

## Current implementation posture

The draft oracle is:

- non-upgradeable and owner-managed;
- immutably bound to one exact pool after validating its factory,
  implementation, distinct DUSD and quote-token addresses, and coin order during
  construction;
- configured with an approved EMA time constant and precise amplification
  value that the owner may update only when both match the live pool and no
  amplification ramp is in progress;
- restricted to a factory-registered, non-meta, two-coin Curve StableSwap NG
  pool whose two asset types are standard ERC-20 type `0`; and
- replaced through `PegResponsiveIrm.setPegOracle()` when its approved
  assumptions change.

`getPrice()` distinguishes two outcomes:

- successfully read states that violate timestamp, parameter, or zero-price
  policy return `valid = false`; and
- Curve source-call failures revert from the adapter. The PRM catches that
  revert and treats the observation as unusable.

`rawPoolState()` is deliberately unvalidated and may revert. It is a diagnostic
view, not an alternate oracle path.

## Price definition and reference asset

- [x] **ORACLE-001: Decide whether the controlled peg is DUSD/quoteToken or
      DUSD/USD**

  **Current behavior**

  `price_oracle(0)` is accepted only in the direct `[quoteToken, DUSD]` coin
  order. The result is DUSD priced in `quoteToken`. Calling it DUSD/USD assumes:

  ```math
  P_{\mathrm{quoteToken/USD}} = 1
  ```

  **Decision required**

  Choose whether to:

  - explicitly define the controlled peg as DUSD/quoteToken and accept
    quote-token peg risk;
  - compose the Curve result with an independently validated quoteToken/USD
    feed; or
  - add a separate sanity source without changing the primary price definition.

  A composite design must define precision, orientation, freshness, invalidity,
  revert handling, and the combined observation timestamp. The conservative
  timestamp is normally the older of its inputs.

  **Resolution**

  The first option was selected. The controller intentionally responds to
  DUSD/quoteToken and does not compose the result with quoteToken/USD. This
  accepts quote-token basis risk and keeps the signal tied to the approved pool.
  The currently intended deployment uses frxUSD as `quoteToken`; any different
  quote token requires separate economic approval and a reviewed deployment
  record.

  **Closure evidence**

  - [x] The price definition and quote-token depeg rationale were approved in
        the protocol discussion recorded on the associated Notion task.
  - [x] Quote-token depeg simulations and their controller implications are
        summarized in that Notion task discussion.
  - [x] A composite or sanity source was explicitly not selected, so no
        additional source is required by this price definition.
  - [x] User-facing, oracle-interface, and PRM documentation use the approved
        DUSD/quoteToken unit.

  Production monitoring must track the configured quoteToken/USD peg. The
  remaining economic-review and monitoring requirements are tracked under
  ORACLE-006.

## Smoothing, freshness, and controller liveness

- [ ] **ORACLE-002: Approve the EMA response and end-to-end latency policy**

  **Current behavior**

  The oracle pins Curve's exact `ma_exp_time`. It does not enforce freshness.

  The EMA time constant and observation age are different controls. End-to-end
  rate response includes both EMA movement and time until a market checkpoint.
  Neither contract forces a checkpoint.

  **Decision required**

  - Select the approved EMA half-life and corresponding `ma_exp_time`.
  - Define the maximum market checkpoint interval and keeper SLO.
  - Define behavior during pool inactivity, keeper failure, and market pause.

  **Closure evidence**

  - [ ] Freshness equality boundary tested.
  - [ ] Keeper ownership, funding, monitoring, and escalation documented.
  - [ ] PRM and oracle latency assumptions reviewed together.

## Manipulation and liquidity

- [ ] **ORACLE-003: Establish a manipulation-cost and minimum-liquidity policy**

  **Current behavior**

  The oracle has no reserve floor and no independent price comparison. A deep
  pool and an EMA increase the cost of manipulation, but neither provides a
  complete guarantee. High `A` also means a pool can become materially
  imbalanced before its price moves far from one.

  **Decision required**

  Model sustained manipulation using the actual balances, precise `A`, fees,
  off-peg fee multiplier, EMA period, arbitrage assumptions, external
  liquidity, PRM thresholds, debt exposure, and checkpoint cadence. Then decide
  whether the result justifies:

  - monitoring only;
  - minimum raw or normalized reserves;
  - a minimum LP-value or manipulation-cost threshold;
  - a second price source or deviation check; or
  - market-level restrictions when the signal becomes unsafe.

  **Closure evidence**

  - [ ] Manipulation-cost model and assumptions reviewed.
  - [ ] Minimum safe liquidity and alert thresholds documented.
  - [ ] Withdrawal and sustained-depeg scenarios tested.
  - [ ] Any on-chain guard has unit, fuzz, and fork coverage.
  - [ ] Emergency response to declining liquidity documented.

## Failure semantics

- [ ] **ORACLE-004: Confirm the source-revert and policy-invalid boundary**

  **Current behavior**

  A well-formed source response that fails oracle policy returns a zero price
  with `valid = false` (and preserves `observedAt` when one was safely decoded).
  A failed Curve call reverts. `PegResponsiveIrm` catches either outcome at its
  consumer boundary and applies its fail-static invalid-observation policy.

  **Decision required**

  Confirm that preserving source failures as reverts is preferred to catching
  every pool call inside the adapter. Review all intended consumers; a consumer
  that does not catch reverts will inherit different availability behavior from
  the PRM.

  **Closure evidence**

  - [ ] Semantics documented in the oracle and consumer interfaces.
  - [ ] Every external Curve call can be forced to revert in deterministic tests.
  - [ ] PRM integration tests cover oracle reverts and `valid = false`.
  - [ ] Monitoring distinguishes source failures from policy invalidity.

## Production identity and tests

- [ ] **ORACLE-005: Approve the production pool and complete the test suites**

  **Current state**

  Four deterministic unit suites currently contain 93 passing tests for the
  constructor, validated price path, raw diagnostics, and runtime configuration.
  Oracle-specific fuzz tests and a dedicated mainnet-fork suite do not yet exist.
  Production oracle addresses, approved configuration, and a pinned fork block
  have not been recorded in a reviewed oracle deployment record.

  Before completing them, independently record:

  - chain, pool, factory, and implementation addresses;
  - `coins(0)`, `coins(1)`, decimals, and factory asset types;
  - pool implementation/version and whether any indirection is upgradeable;
  - current and future precise `A` and any ramp schedule;
  - base fee and off-peg fee multiplier;
  - `ma_exp_time` and its human-readable half-life;
  - packed oracle timestamps;
  - balances and LP supply; and
  - every address able to change relevant parameters.

  **Closure evidence**

  - [ ] Deployment record independently reviewed.
  - [x] Constructor, price, raw-state, runtime-config, and source-revert
        deterministic unit suites completed.
  - [ ] Oracle-specific fuzz suite completed.
  - [ ] Mainnet-fork constants pinned to a reviewed historical block.
  - [ ] Fork suite verifies ABI, provenance, configuration, timestamps, and
        returned values without deriving expected constants from the DUT.
  - [ ] PRM-to-oracle integration behavior tested.

## Security review

- [ ] **ORACLE-006: Complete economic and external security review**

  The current work does not establish that Curve's EMA is manipulation-proof,
  that the accepted quote-token basis risk is economically safe, or that copied
  Curve interfaces and the approved implementation behave correctly across
  their full domains.

  **Closure evidence**

  - [ ] Economic review covers manipulation, liquidity loss, quote-token depeg,
        inactivity, and checkpoint latency.
  - [ ] External audit covers the oracle, PRM integration, Curve assumptions,
        deployment path, and operational controls.
  - [ ] Production monitoring covers price, source timestamp, parameter drift,
        source reverts, pool liquidity, quote-token peg, and PRM checkpoint age.

## Threat-model summary

| Threat                             | Current mitigation                                                          | Residual concern                                              |
| ---------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Same-transaction spot manipulation | A newly stored Curve state price receives no elapsed EMA weight immediately | An attacker may sustain influence across time                 |
| Sustained pool manipulation        | Pool depth, `A`, fees, arbitrage, and EMA                                   | Cost has not been simulated or approved                       |
| Stale or inactive pool             | Source timestamp returned to PRM `maxOracleAge` check                       | Invalid observations trigger the PRM's fail-static policy     |
| Wrong coin direction               | Exact pool and factory coin-order checks                                    | A different orientation requires a different reviewed adapter |
| `A` or EMA change                  | Exact current/future `A` and `ma_exp_time` checks                           | Oracle remains unusable until coordinated remediation         |
| Fee change                         | Off-chain review only                                                       | Manipulation cost can change without invalidating the oracle  |
| Quote-token depeg                  | Accepted by the DUSD/quoteToken definition; monitor separately                | The controller does not necessarily measure DUSD/USD          |
| Liquidity loss                     | No current on-chain mitigation                                              | Manipulation cost can fall substantially                      |
| Curve call failure                 | Revert reaches PRM, which treats it as unusable                             | Other consumers must implement compatible handling            |
| Keeper failure                     | Permissionless PRM checkpointing permits automation                         | No on-chain checkpoint-latency guarantee                      |
| Oracle replacement                 | Immutable adapter replaced through the PRM                                  | Current PRM applies the new source at a later checkpoint      |
