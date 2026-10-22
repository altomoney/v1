# ERP-OFFBOARD-02 Borrow Market Off-Boarding

This is the developer runbook for the repository tooling. The
[Notion ERP](https://app.notion.com/p/ERP-OFFBOARD-02-Borrow-Market-Off-Boarding-3bb90b99d6dc80a8a228cf9eddb07b3b)
is the authority for activation criteria, severity, notice, schedules, parameters, simulation requirements, acceptance
criteria, and approvals. This README explains only how to operate the implementation.

If the Notion ERP, approved activation record, live state, generated artifacts, and this runbook do not agree, stop and
obtain a reviewed update. Do not edit Solidity or generated JSON during an incident.

The Mint and Borrow offboarding tools share scheduling, rate/LTV validation and call builders, integration removal, IO, fork-simulation, and borrower-fetching mechanics under `ERP/libraries` and `ERP/scripts`. This runbook and the ERP-OFFBOARD-02 facade remain the operator-facing interface.

## Emergency flow

1. Confirm Governance/Risk approved the activation and all inputs required by the Notion ERP.
2. Create the activation manifest from
   [config/borrow-market-offboarding.json](config/borrow-market-offboarding.json). Do not reuse another incident's file.
3. Select a finalized source block and generate the phase on a mainnet fork pinned to that exact block.
4. Review the generated caller, target, value, calldata, ordering, Timelock data, and postconditions.
5. Complete every external simulation and approval required by the Notion ERP.
6. Execute artifacts only from their recorded caller and in the order documented below.
7. Verify the phase outcome onchain and preserve all inputs, outputs, transaction hashes, operation IDs, and approvals.

Stop immediately if:

- any approval, notice/waiver, source input, role, owner, implementation, oracle, or integration cannot be verified;
- the market cannot safely remain frozen and operational for the controlled exit period required by the Notion ERP;
- state changed after generation in a way that can affect a transaction;
- a simulation fails or a result exceeds its approved limit;
- a required repayment, withdrawal, collateral-withdrawal, liquidation, oracle, or adapter route may be impaired;
- an artifact differs from the reviewed transaction, a prior operation is incomplete, or a postcondition cannot be proved.

Never bypass a failed gate with a direct call. Refresh the source block, update only approved inputs, regenerate, and obtain
reapproval where the outcome changed.

## Phase and caller reference

| Phase ID | Purpose | Live caller |
| --- | --- | --- |
| `0` | Batch A containment | Freezer Safe, each Vault curator, each Vault allocator |
| `1` | Deploy and attach fixed-rate IRMs | Approved deployer if the factory is missing; then Timelock Safe |
| `2` | Apply one approved rate/LTV correction | Timelock Safe |
| `3` | Batch C Vault cleanup and final removal | Each Vault allocator, then Timelock Safe |

The script normally generates files; it does not execute operational Safe or allocator transactions. The only exception is
the separately described phase 1 factory-deployment prerequisite.

## Manifest

All manifest fields are currently required by the loader, even when a phase does not use all of them. Use the checked-in
example for the schema and obtain values from the approved activation:

- activation: `activationId`, `severity`, `schedulePhase`, `t0`, `step`, prior-step timestamp and operation ID;
- chain inputs: `sourceBlock`, `deploymentId`, `freezerSafe`, `timelockSafe`, `fixedRateIrmVersion`;
- each market: market, leverage integration, approved rates, LTV reduction, and per-market simulation limits;
- each Vault: Vault, authorized allocator, ordered replacement markets for Batch A, and aggregate Vault-loss limit.

The following JSONC is an annotated template only. Comments are not valid in the operational JSON; copy the checked-in
manifest and replace its values instead of passing this block to the script.

~~~jsonc
{
  // Unique, stable incident identifier. It becomes part of the output path.
  "activationId": "erp-offboard-02-incident-name",

  // Governance-approved severity: 0 = Medium, 1 = High, 2 = Critical.
  "severity": 0,

  // Batch B correction mode: 0 = scheduled calendar step, 1 = terminal hourly step.
  "schedulePhase": 0,

  // Governance-approved Unix timestamp from which the Batch B timetable is calculated.
  "t0": 1787591735,

  // Last successfully executed Batch B correction. Use 0 before the first correction.
  "lastExecutedStep": 0,

  // Actual block timestamp of that execution. Use 0 before the first correction.
  "lastStepExecutedAt": 0,

  // Timelock operation ID of that correction. Use bytes32(0) before the first correction.
  "lastOperationId": "0x0000000000000000000000000000000000000000000000000000000000000000",

  // Correction being prepared. It must equal lastExecutedStep + 1.
  "step": 1,

  // Exact finalized Ethereum block used for all reads, borrower discovery, and fork simulation.
  "sourceBlock": 25833639,

  // Deployment folder suffix: ethereum-mainnet-1-<deploymentId>.
  "deploymentId": 1765364975,

  // Safe holding FROZEN_TYPE permission for Batch A.
  "freezerSafe": "0x1111111111111111111111111111111111111111",

  // Safe authorized to schedule and execute the Timelock batches.
  "timelockSafe": "0x2222222222222222222222222222222222222222",

  // Approved nonzero version identifier passed to OwnerFixedRateIrmFactory.
  "fixedRateIrmVersion": 1,

  "vaults": [
    {
      // Affected AltoVault. Repeat this object for every affected Vault.
      "vault": "0x3333333333333333333333333333333333333333",

      // Address currently authorized by this Vault's isAllocator mapping.
      "allocator": "0x4444444444444444444444444444444444444444",

      // Ordered Batch A destinations. Each must be a distinct, registered, enabled, non-frozen,
      // non-paused market for the Vault asset with a nonzero cap. Earlier entries fill first.
      // Unusable entries are skipped. Use [] to leave all affected Vault exposure in place.
      "replacementMarkets": [
        "0x7777777777777777777777777777777777777777",
        "0x8888888888888888888888888888888888888888"
      ],

      // Raw Vault-asset interest buffer reserved by Batch A on source targets and destination caps.
      // Size it as total affected Vault supply x supply APR x expected execution delay. 1 DUSD shown.
      "reallocationBufferAssets": 1000000000000000000,

      // Maximum approved raw-DUSD loss for this Vault across all manifest markets.
      "maxVaultLossAssets": 0
    }
  ],

  "markets": [
    {
      // Affected AltoBorrowMarket. Repeat this object for every affected market.
      "market": "0x5555555555555555555555555555555555555555",

      // Matching AltoLeverage integration used for Batch C cleanup.
      "leverage": "0x6666666666666666666666666666666666666666",

      // Initial fixed rate attached at T0, encoded as WAD per second (SPY).
      "fixedRateSpy": 3170979198,

      // Approved fixed rate for this Batch B correction, also WAD per second.
      "correctionRateSpy": 6341958396,

      // Approved absolute LTV reduction in WAD; 0.03 ether = 3 percentage points.
      "ltvReduction": 30000000000000000,

      // Maximum raw DUSD that the simulated liquidator may need for this market.
      "maxLiquidationFundingAssets": 0,

      // Maximum raw-DUSD bad debt approved for this market.
      "maxBadDebtAssets": 0,

      // Maximum raw-DUSD supplier loss approved for this market.
      "maxSupplierLossAssets": 0,

      // Maximum raw-DUSD fee-recipient/protocol loss approved for this market.
      "maxProtocolLossAssets": 0
    }
  ]
}
~~~

For phases that do not consume the Batch B scheduling fields, keep valid values consistent with the activation; do not use
strings such as `"N/A"`. For every later correction, copy the actual previous execution timestamp and operation ID from
the successful onchain operation, then refresh the source block and all step-specific approved values.

Addresses must be nonzero and unique. Replacement markets are ordered per Vault and must not be affected markets. Use an
empty `vaults` array only when no Vault is affected. Limits are raw
borrow-token amounts and are expected to be DUSD for this ERP; independently verify every market's borrow token because the
script does not enforce a common token. Zero limits are fail-closed.

Nobody should edit library code to change incident inputs.

## Generate a phase

Run from the repository root without `--broadcast`:

~~~bash
MANIFEST_PATH="ERP/ERP-OFFBOARD-02/config/borrow-market-offboarding.json"
PHASE_ID=0
SOURCE_BLOCK="$(jq -r .sourceBlock "$MANIFEST_PATH")"

FOUNDRY_PROFILE=erp forge script \
  ERP/ERP-OFFBOARD-02/scripts/BorrowMarketOffboarding.s.sol:BorrowMarketOffboardingScript \
  --sig "run(uint256,string)" "$PHASE_ID" "$MANIFEST_PATH" \
  --fork-url "$RPC_URL" \
  --fork-block-number "$SOURCE_BLOCK" \
  -vvvv
~~~

The run must satisfy `block.number == sourceBlock`. Before signing anything, confirm live state still matches the reviewed
source state; otherwise regenerate from a fresh finalized block.

## Output

Batch A and Batch C:

~~~text
ERP/ERP-OFFBOARD-02/output/<activation-id>/source-block-<block>/
~~~

Batch B:

~~~text
ERP/ERP-OFFBOARD-02/output/<activation-id>/severity-<severity>/step-<step>/source-block-<block>/
~~~

| Phase | Files |
| --- | --- |
| `0` | Optional `batch-a-freeze-safe.json`; optional `batch-a-vault-<vault>-curator-safe.json` and `batch-a-vault-<vault>-allocator.json` per Vault; `inputs.json` |
| `1` | `batch-b-fixed-rate-irm-schedule.json`, `batch-b-fixed-rate-irm-execute.json`, `inputs.json` |
| `2` | `borrowers.json`; after a passing gate, `batch-b-irm-and-ltv-update-schedule.json`, `batch-b-irm-and-ltv-update-execute.json`, `inputs.json`, `simulation-report.json` |
| `3` | Optional `batch-c-vault-<vault>-allocator.json` files or the optional `batch-c-final-removal-schedule.json` and `batch-c-final-removal-execute.json`; `inputs.json` |

Safe files are Safe Transaction Builder artifacts. Allocator files are generic plans because an allocator may be an EOA,
bot, or Safe. Review the caller and decoded calldata accordingly. Preserve every source-block directory and never combine
schedule and execute files from different directories.

For Timelock pairs, verify the Timelock, Safe, delay, predecessor, zero salt, operation ID, targets, values, payloads, and
call order. Wait until the scheduled operation is ready before executing it.

## Phase 0 — Batch A containment

Before generation:

- confirm the exact market/Vault scope and containment approval;
- confirm every market is unpaused and the Freezer Safe can freeze each market not already frozen;
- record each Vault's curator, authorized allocator, cap, pending actions, queues, shares, and withdrawable assets;
- optionally populate each Vault's `replacementMarkets` in approved fill order; unusable entries are skipped and an empty
  list leaves all affected exposure in place;
- identify every integration that must remain available for repayment, withdrawal, deleveraging, and liquidation.

Execute in this order:

1. Run phase `0`.
2. If present, execute `batch-a-freeze-safe.json` from the Freezer Safe.
3. Verify every affected market is frozen and not paused.
4. Execute each curator file from that Vault's current curator. It contains only outstanding pending-action revocations and
   cap-zeroing calls.
5. Verify affected caps and pending actions are zero.
6. Refresh `sourceBlock` and rerun phase `0` immediately before submitting allocator plans. Interest, market liquidity,
   Vault deposits/withdrawals, and destination cap room can change the derived amounts.
7. Execute each allocator plan once from its recorded allocator, in listed transaction order:
   - optional `setSupplyQueue`, preserving unaffected order and removing only affected markets;
   - optional `reallocate`, withdrawing only what fits within both affected-market liquidity and valid replacement cap room.
     Affected markets and destinations are consumed in manifest order. Intermediate destinations fill to cap and the final
     destination uses `type(uint256).max`. Source targets and destination caps reserve the raw `reallocationBufferAssets`
     manifest amount for interest accrued between generation and execution. A market with zero borrowed assets accrues
     no interest, so its full Vault position is withdrawn (target `0`) without a buffer. Check
     `expectedRemainingAffectedAssets` and keep markets with remaining exposure in the withdraw queue.

Size `reallocationBufferAssets` from live state: at least the total affected Vault supply multiplied by the current
supply APR and the expected delay between generation and allocator execution. At the pinned fork block the five manifest
markets accrue about 0.22 DUSD per hour in total, so 1 DUSD (`1000000000000000000`) covers a few hours at ordinary
rates. A phase `0` rerun during the Batch B terminal phase at 80% APR accrues several DUSD per hour on a 50k DUSD
position and needs a larger buffer. Only the final `type(uint256).max` destination absorbs accrued drift, so its cap room
must exceed the planned supply by the accrual summed across every source and intermediate destination.

Before proceeding, verify the Batch A acceptance criteria in the Notion ERP, including blocked new exposure, working exit
routes, zero Vault caps, exact supply queues, retained withdrawal routes where needed, and no unrelated changes.

Batch A has no Timelock schedule/execute pair.

## Phase 1 — fixed-rate IRM attachment

Run this phase at the approved T0 after Batch A and the required notice/waiver. Confirm every configured market is frozen,
unpaused, and still has debt. Independently simulate this phase; it has no automated borrower/loss gate.

### If the factory address is zero

1. Simulate phase `1` without `--broadcast`.
2. Obtain approval for the factory deployment and run phase `1` with the approved deployer/signing configuration and
   `--broadcast`.
3. Do not use artifacts from that deployment run.
4. Verify factory bytecode, Timelock ownership, and zero pending owner; record the address under
   `.contracts.ownerFixedRateIrmFactory` in the selected deployment's `addresses.json`.
5. Choose a fresh post-deployment source block and rerun phase `1` without `--broadcast`.

A recorded nonzero factory is reused and must be Timelock-owned.

### Execute

1. Review the atomic Timelock batch: all versioned IRM deployments come first, followed by all
   `market.setIrm(predictedIrm, false)` calls.
2. Execute the schedule file from the Timelock Safe.
3. Wait the real Timelock delay and recheck state.
4. Execute the paired file from the same Safe.
5. Verify each market points to the predicted dedicated Timelock-owned IRM with the approved rate and market binding.

The script does not enforce the T0 execution window; the operator must.

## Phase 2 — rate/LTV correction

Use the severity schedule, approved values, simulation requirements, and terminal rules from the Notion ERP. Do not copy
rates or timing from this README.

Before every step:

- use the exact next sequential step;
- for step 1, use zero prior-step values;
- later steps must use the previous successful execution timestamp and completed Timelock operation ID;
- refresh `sourceBlock`, borrower data, rates, reduction, limits, and external simulation evidence;
- verify the dedicated IRM/engine ownership, frozen/unpaused state, DUSD borrow token, and disabled priority liquidation.

Running phase `2` automatically:

1. invokes `ERP/scripts/fetch-borrowers.ts` through FFI;
2. fetches the complete historical borrower candidate set from Goldsky at `sourceBlock`;
3. reconciles active borrower shares exactly with `totalBorrowed().shares`;
4. schedules and executes the exact proposed Timelock batch on the fork;
5. attempts each active borrower's liquidation in isolation;
6. checks per-market funding, bad debt, supplier loss, protocol loss, and per-Vault loss;
7. restores the fork and writes operational artifacts only if the limits pass.

Node.js 22.18 or newer (the fetcher runs as an unflagged `.ts` file) and Goldsky access are required. An approved endpoint may be supplied with
`GOLDSKY_SUBGRAPH_URL`. A failed gate may leave `borrowers.json`, but must not produce schedule, execute, inputs, or report
artifacts.

The automated report covers isolated liquidation at the fork's current oracle state only. Complete every additional
scenario, input, output, and numeric approval required by the Notion ERP before live execution.

For a passing step:

1. Reconcile `borrowers.json`, `simulation-report.json`, limits, and operation ID.
2. Execute the schedule file from the Timelock Safe.
3. Wait until ready; recheck current state and funding.
4. Execute the paired file.
5. Verify rate, all three independently floored LTV reductions, threshold ordering, unchanged engine fields, exit routes,
   and actual losses.
6. Record the execution timestamp and operation ID only after success.

Cleared markets are skipped. Stop immediately when every configured market has zero borrowed assets and shares.

For terminal steps, follow the Notion rules exactly: run a fresh gate after the prior operation executes, use only the next
step, observe the minimum interval, and never catch up a missed or failed reduction.
As LTV decreases, keepers liquidate eligible positions; the team clears any remaining positions with plain `liquidate` or
`governanceLiquidate`.

## Phase 3 — Batch C recovery

Before generation:

- confirm every market has zero borrowed assets and shares;
- once every market has zero debt, rerun phase `0` and execute its allocator plan. With no interest accruing it withdraws
  each affected Vault position completely (target `0`) into the manifest replacement markets, leaving zero market shares
  and quarantine;
- confirm caps and pending actions are zero and affected markets are absent from supply queues;
- confirm the market remains frozen/unpaused, its oracle is nonzero, its adapter approval is active, and every required
  legacy exit route has been identified;
- confirm Timelock ownership and each recorded allocator's current authorization.

Execute:

1. Run phase `3`.
2. If any affected market remains in a withdraw queue, the run writes allocator plans and omits the final Timelock pair.
3. Execute each allocator plan once, from the recorded allocator, against the exact queue used to generate it.
4. Verify the expected withdraw queue, disabled/deleted config, zero shares/cap/quarantine, and no pending action.
5. If allocator plans were executed, choose a fresh source block and rerun phase `3`; otherwise continue with the output
   from the current run.
6. Review the final batch, if present. It removes only outstanding leverage, callback, swapper, and
   liquidation-periphery permissions,
   then registry membership last.
7. Execute the schedule, wait until ready, recheck dependencies, and execute the pair.

`updateWithdrawQueue` is index-based and non-idempotent. Discard and regenerate a plan if its queue or Vault position
changes. Use a separately reviewed atomic withdrawal/queue-update transaction if supply-on-behalf front-running is a
realistic risk.

Do not use ordinary recovery to force-remove nonzero Vault supply. The exceptional path requires the separate approval,
delay, simulation, and loss treatment in the Notion ERP.

Batch C intentionally keeps the oracle and AltoAdapter approval active while legacy users may still need the adapter's
`marketRemoveSupply` or `marketRemoveCollateral` exit routes. Do not call `AltoAdapter.revokeContract(market)` during
recovery: both routes require the market to remain approved. Revoke it only as separately reviewed closure work after
confirming that no user still relies on either route. Oracle shutdown, residual liquidation/repayment, and full market
decommission are also separate closure work and are not generated here. Document every retained dependency and complete
the Notion acceptance criteria before Governance/Risk formally closes the activation.

## Evidence and reruns

Keep:

- the approved activation, notice/waiver, manifest, repository commit, deployment ID, chain, and source block;
- all borrower inputs, simulation reports, external analyses, generated files, and decoded transactions;
- Safe proposals, transaction hashes, Timelock operation IDs, blocks, timestamps, and actual callers;
- before/after market, Vault, queue, permission, registry, route, and loss state;
- generated Batch A reallocation plans, actual allocation results, and separately approved residual-position transactions;
- deviations, failed/missed steps, discarded stale artifacts, reconciliation, and final sign-off.

Batch A and Batch C derive calls from current state and skip completed work. Optional no-op files are removed. For a failed
or missed correction, keep the same next step and regenerate from fresh state. Never manually edit an artifact.

## Verification

~~~bash
FOUNDRY_PROFILE=erp forge test \
  --match-path 'ERP/ERP-OFFBOARD-02/tests/*.t.sol' \
  --threads 1 \
  -vv

FOUNDRY_PROFILE=erp forge build
~~~

`tests/RefreshedSusdeEndToEnd.t.sol` is the Notion Section 6 development pre-simulation. It runs Batch A through
Batch C at Medium severity against the live refreshed sUSDe borrow market `0x5d8fA5E1fAcb746179BD1AEb3aA78Db384C52001`
and the DUSD Vault at block `26225900`, using `tests/fixtures/manifest-susde-26225900.json` and
`tests/fixtures/borrowers-susde-26225900.json`. Refresh both fixtures with `ERP/scripts/fetch-borrowers.ts` when the
source block changes. Pass the manifest path and the desired borrower JSON output path explicitly.
