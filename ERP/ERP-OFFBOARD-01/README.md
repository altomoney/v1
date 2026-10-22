# ERP-OFFBOARD-01 Mint Market Off-Boarding

This is the operator guide for the repository tooling. The
[Notion ERP](https://app.notion.com/p/ERP-OFFBOARD-01-Mint-Market-Off-Boarding-3c190b99d6dc8064868cfd54eca6237b)
is authoritative for activation, severity, notice, schedules, simulations, limits, and approvals. Stop if it disagrees
with the activation, live state, manifest, simulation, or generated transactions. Refresh the source block, regenerate,
and obtain reapproval when outcomes change. Never edit generated JSON.

The Mint and Borrow offboarding tools share scheduling, rate/LTV validation and call builders, integration removal, IO, fork-simulation, and borrower-fetching mechanics under `ERP/libraries` and `ERP/scripts`. This runbook and the ERP-OFFBOARD-01 facade remain the operator-facing interface.

## Operator flow

1. Confirm Governance/Risk approval, notice or waiver, market scope, severity, and numeric limits.
2. Copy [config/mint-market-offboarding.json](config/mint-market-offboarding.json) for the activation.
3. Select a finalized Ethereum block and run the phase on a fork pinned to that block.
4. Decode and review every caller, target, value, payload, order, Timelock delay, predecessor, salt, and operation ID.
5. Complete the economic and transaction simulations required by the Notion ERP.
6. Execute only the reviewed artifacts, from their recorded callers and in the documented order.
7. Verify the onchain result and retain the manifest, artifacts, simulations, approvals, transaction hashes, and operation IDs.

## Phase reference

| ID | Phase | Caller |
| --- | --- | --- |
| `0` | Batch A containment | Freezer Safe, then Timelock Safe |
| `1` | Deploy and attach dedicated fixed-rate IRMs | Approved deployer if the factory is missing; then Timelock Safe |
| `2` | Apply one rate/LTV correction | Timelock Safe |
| `3` | Batch C recovery and integration removal | Timelock Safe |

The script generates artifacts; it does not execute live Safe or Timelock calls. Phase `2` executes the proposed
operation only on a snapshotted fork. Deployment of a missing `OwnerFixedRateIrmFactory` is the only broadcast
prerequisite.

## Manifest

All fields in the checked-in example are required by the loader, even when a phase does not consume them.

- Activation: `activationId`, `severity` (`0` Medium, `1` High, `2` Critical), `schedulePhase`
  (`0` scheduled, `1` terminal), `t0`, and `step`.
- Prior correction: `lastExecutedStep`, `lastStepExecutedAt`, and `lastOperationId`. Use zero values before the
  first phase-`2` correction.
- Chain: `sourceBlock`, `deploymentId`, `freezerSafe`, `timelockSafe`, and `fixedRateIrmVersion`.
- Market: `market`, matching `leverage`, approved debt and DUSD ceilings, exact SPY rates, absolute
  `ltvReduction`, simulation limits, and the exact `approvedRecoveryBadDebtAssets` for Batch C.

`ltvReduction` uses WAD precision and cannot exceed `0.05 ether`. Rates are supplied directly as SPY. DUSD limits use
raw DUSD units; `maxSeizedCollateralAssets` uses the collateral token's raw units. Zero limits fail closed.

Phase `2` uses `maxLiquidationFundingAssets`, `maxBadDebtAssets`, `maxDusdMintedAssets`, and
`maxSeizedCollateralAssets`. The DUSD mint limit must cover current `claimableFeesAssets`; the approved external
simulation must quantify the exact execution-time mint. Phase `3` also uses `maxUnbackedDusdAssets` for an explicitly
approved DUSD residual and requires live bad debt to equal `approvedRecoveryBadDebtAssets` exactly.

## Generate

Run from the repository root without `--broadcast`:

~~~bash
MANIFEST_PATH="ERP/ERP-OFFBOARD-01/config/mint-market-offboarding.json"
PHASE_ID=0
SOURCE_BLOCK="$(jq -r .sourceBlock "$MANIFEST_PATH")"

FOUNDRY_PROFILE=erp forge script \
  ERP/ERP-OFFBOARD-01/scripts/MintMarketOffboarding.s.sol:MintMarketOffboardingScript \
  --sig "run(uint256,string)" "$PHASE_ID" "$MANIFEST_PATH" \
  --fork-url "$RPC_URL" \
  --fork-block-number "$SOURCE_BLOCK" \
  -vvvv
~~~

The fork block must equal `sourceBlock`. Phase `2` requires Node.js `22.18` or newer and Goldsky access; override the
endpoint with `GOLDSKY_SUBGRAPH_URL` when required.

Output paths:

~~~text
# Phases 0 and 3
ERP/ERP-OFFBOARD-01/output/<activation-id>/source-block-<block>/

# Phases 1 and 2
ERP/ERP-OFFBOARD-01/output/<activation-id>/severity-<severity>/step-<step>/source-block-<block>/
~~~

| Phase | Files |
| --- | --- |
| `0` | Optional `batch-a-freeze-safe.json`; `batch-a-containment-schedule.json`; `batch-a-containment-execute.json`; `inputs.json` |
| `1` | `batch-b-fixed-rate-irm-schedule.json`; `batch-b-fixed-rate-irm-execute.json`; `inputs.json` |
| `2` | `borrowers.json`; `batch-b-irm-and-ltv-update-schedule.json`; `batch-b-irm-and-ltv-update-execute.json`; `simulation-report.json`; `inputs.json` |
| `3` | `batch-c-final-removal-schedule.json`; `batch-c-final-removal-execute.json`; `inputs.json` |

Do not combine schedule and execute files from different source-block directories.

## Phase 0 — containment

Before generation, approve the exact ceilings and confirm each market is unpaused. Identify every repayment,
collateral-withdrawal, deleveraging, liquidation, oracle, adapter, and DUSD permission that must remain available.

Execute the optional freeze artifact first. After every market is frozen and unpaused, schedule and execute one atomic
Timelock batch containing, for each market in manifest order:

1. `accrueInterest()`;
2. `claimInterest(0)`;
3. `setDebtCeiling(debtCeiling)`;
4. `DUSD.setMinterCeiling(market, dusdMinterCeiling)`.

Batch A does not revoke DUSD permissions or remove registry/integration/adapter routes. Regenerate from a fresh block
before execution if accrual no longer fits the approved debt or DUSD ceiling.

## Phase 1 — fixed-rate IRM attachment

Run at approved T0 after Batch A and the required notice or waiver. The Timelock batch deploys every dedicated IRM in
manifest order, then calls `market.setIrm(predictedIrm, false)` for every market in the same order. `false` accrues
under the existing IRM before switching.

If `ownerFixedRateIrmFactory` is absent:

1. obtain approval and run phase `1` with the approved deployer and `--broadcast`;
2. discard that run's artifacts;
3. verify the factory and Timelock ownership, then record it in the selected deployment `addresses.json`;
4. choose a fresh source block and rerun without `--broadcast`.

After execution, verify each market uses its predicted dedicated IRM, the IRM is bound to that market, and its rate equals
`fixedRateSpy`.

## Phase 2 — rate and LTV correction

| Severity | Scheduled floors | Terminal starts |
| --- | --- | --- |
| Medium | T+1 10%, T+7 20%, T+14 40%, T+21 80% | T+28 |
| High | T+1 10%, T+4 20%, T+7 40%, T+10 80% | T+14 |
| Critical | T+1 through T+6: 10%, 20%, 40%, 80%, 160%, 320% | T+7 |

The manifest supplies exact SPY values. Steps are sequential. Later steps use the last successful operation as predecessor.
Terminal steps require the prior operation to be executed, a fresh simulation, and at least one hour since the previous
step; do not catch up missed steps.

For every market with debt, the atomic Timelock batch calls:

1. `FixedRateIrm.setBorrowRate(correctionRateSpy)`, accruing under the prior rate;
2. `claimInterest(0)`;
3. `setMaxLtv(reducedMaxLtv)`;
4. `setLiquidationConfiguration(updatedConfiguration)`, reducing both liquidation thresholds and preserving other fields;
5. `setDebtCeiling(debtCeiling)`.

Running phase `2` fetches borrower candidates, reconciles active shares with `totalBorrowed().shares`, classifies
liquidatability before and after the exact operation, simulates each borrower in isolation with synthetic DUSD funding,
checks approved funding/bad-debt/collateral limits, restores the fork, and writes artifacts.

This automated gate covers the pinned block and current oracle state only. The Notion ERP additionally requires approved
adverse-price, oracle, DUSD-liquidity, collateral-exit-liquidity, protocol-loss, and final-state simulation. Rerun from a
fresh finalized block immediately before execution; stop if calldata, operation ID, borrowers, or outcomes change.

## Phase 3 — recovery

Ordinary recovery requires zero borrowed assets and shares, zero claimable fees, zero bad debt, and zero market-attributed
minted DUSD. Any nonzero bad debt or DUSD residual requires explicit Governance approval and remediation; the manifest
limits must cover it.

The generated atomic Timelock batch:

1. sets each market debt ceiling to live `badDebtAssets`;
2. sets its DUSD minter ceiling to zero and revokes minter and burner status;
3. removes outstanding leverage, callback, swapper, and liquidation-periphery permissions;
4. removes Mint Market registry membership last.

Every valid nonempty manifest generates the schedule/execute pair because the four shutdown calls are unconditional.
The implementation still uses the optional Timelock writer defensively to remove stale files if no calls exist.

The market must remain frozen and unpaused. The oracle and `AltoAdapter` approval are deliberately retained so legacy
collateral can still be withdrawn. Never append `AltoAdapter.revokeContract(market)` to this batch. Remove that approval
only in separately reviewed closure work after confirming no user collateral depends on `marketRemoveCollateral`.
Oracle shutdown and full decommissioning are also separate closure work.

Before execution, recheck that no permission or integration being removed is required by an affected user. After
execution, verify ceilings, DUSD authority, integrations, registry state, retained exit routes, and the freeze.

## Evidence and verification

Preserve the manifest, source block, borrower list, simulation report, decoded calls, operation ID, approvals, and
execution receipts.

### Refreshed WETH development pre-simulation

`tests/RefreshWethEndToEnd.t.sol` runs the complete Medium-severity flow against refreshed WETH Mint Market
`0x81b2CcE73052f67312eD9994385f62D413eE566e` at block `26,225,900`. It uses the eight-account
`tests/fixtures/borrowers-refresh-weth-26225900.json` fixture and the dedicated
`tests/fixtures/manifest-refresh-weth-26225900.json` manifest. It executes Batch A, fixed-rate IRM attachment, every
scheduled and hourly terminal correction, ordinary liquidations, and ordinary zero-residual Batch C recovery through
the production entrypoints. The calibrated run requires 17 corrections and 26 liquidations and finishes with zero
debt, bad debt, claimable fees, and market-attributed DUSD.

To refresh the pre-simulation, select a finalized block, update the manifest's source block, T0, targets, and approved
limits, update the test fork-block constant, and regenerate its borrower fixture:

~~~bash
node ERP/scripts/fetch-borrowers.ts \
  ERP/ERP-OFFBOARD-01/tests/fixtures/manifest-refresh-weth-<block>.json \
  ERP/ERP-OFFBOARD-01/tests/fixtures/borrowers-refresh-weth-<block>.json
~~~

Then rerun the pre-simulation and replace the measured exact targets and limits in the manifest.

~~~bash
FOUNDRY_PROFILE=erp forge test \
  --match-path ERP/ERP-OFFBOARD-01/tests/RefreshWethEndToEnd.t.sol -vv
~~~

Repository checks:

~~~bash
forge fmt --check \
  ERP/ERP-OFFBOARD-01/MintMarketOffboarding.sol \
  ERP/ERP-OFFBOARD-01/IMintMarketOffboarding.sol \
  ERP/ERP-OFFBOARD-01/libraries/MintMarketOffboardingIO.sol \
  ERP/ERP-OFFBOARD-01/scripts/MintMarketOffboarding.s.sol

FOUNDRY_PROFILE=erp forge build
FOUNDRY_PROFILE=erp forge test --match-path 'ERP/ERP-OFFBOARD-01/tests/*.t.sol' -vv
jq empty ERP/ERP-OFFBOARD-01/config/mint-market-offboarding.json
git diff --check
~~~
