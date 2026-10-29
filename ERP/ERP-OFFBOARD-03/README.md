# ERP-OFFBOARD-03 Vault Offboarding

This is the developer runbook for preparing and operating Vault offboarding. The
[Notion ERP](https://app.notion.com/p/ERP-OFFBOARD-03-Vault-Exposure-3c790b99d6dc80d68508c46ae07c830c)
is authoritative for activation, severity, approvals, execution ordering, economic simulation and acceptance criteria.
Section 4 contains the canonical ordering; this runbook maps it to the repository's scripts and artifacts.

Use this ERP to deprecate an entire Vault while preserving controlled shareholder exits. If those routes cannot safely
remain operational for the seven-day Critical process, use the applicable incident response procedure instead.

The tooling prepares calldata and reports observed state. It does not execute the generated transactions, force user
redemptions, perform economic simulation or certify Governance approval. Run without `--broadcast`.

## Operator flow

1. Confirm Governance/Risk approval, the named Vault, severity, notice or waiver, T0 and numeric economic limits.
2. Resolve the live implementation and complete market, shareholder, role, token and integration inventories.
3. Copy [config/vault-offboarding.json](config/vault-offboarding.json) for this activation. Replace the historical example
   values with reviewed inputs and select a finalized source block.
4. Generate the selected batch on a fork pinned to that exact block. Review the source report and decode every caller,
   target, value, payload, queue index, call order, Timelock delay, predecessor, salt and operation ID.
5. Complete the transaction and economic simulations required by Notion Section 5. Obtain approval for the exact proposed
   effects, including any exceptional removal, recovery or nonzero closure outcome.
6. Recheck current state, then execute the reviewed artifacts from their recorded callers in the order below.
7. Verify the result onchain, preserve the evidence and select a fresh source block before preparing the next stage.

If the spec, approval, live state, manifest, simulation or generated calls disagree, resolve the discrepancy before
execution. Refresh approved inputs and regenerate when state changes; do not hand-edit generated calldata. A successful
script run verifies preparation conditions at its source block, not conditions at execution time.

## Batches and callers

| Phase ID | Batch | Prepared work | Caller |
| --- | --- | --- | --- |
| `0` | A — Contain | Pending administration, supply closure, fee shutdown, allocator revocations | Timelock Safe for owner work; current curator Safe for market/queue work |
| `1` | B — Correct | One selected queue, exceptional-removal or quarantine-recovery action | Approved allocator for queue updates; current curator Safe for submissions and cap recovery |
| `2` | C — Recover | Partial/full cleanup, then final integration removal on a later run | Timelock Safe |

Owner calls execute through the deployed `TimelockController`, which owns the Vault. The `timelockSafe` schedules and
executes those batches; it does not call owner-only Vault functions directly. If Batch B's `allocator` is that Timelock,
queue updates also use the governance schedule/execute pair.

`curatorSafe` must match the current Vault curator when curator calls are required. A Batch B allocator must be the Vault
owner, current curator or an address with `isAllocator == true`. Verify the actual Safe and Timelock permissions before
signing; supplying an address in the manifest does not grant it authority.

## Prepare the manifest

The manifest is flat and covers one Vault. Common fields are loaded for every run, including monitoring. Phase-specific
fields are read only when needed; use the action-specific additions below rather than filling inactive exceptional lists.

| Common input | Meaning |
| --- | --- |
| `activationId` | Stable activation identifier used in paths and salts; 1–96 letters, digits, hyphens or underscores |
| `severity` | `0` Medium, `1` High, `2` Critical |
| `t0` | Approved nonzero Unix timestamp for the start of controlled exits |
| `step` | Positive run label; it is not a checkpoint number or enforced execution sequence |
| `sourceBlock` | Exact finalized block used for source reads and optional borrower discovery |
| `deploymentId` | Deployment folder suffix used to resolve the Timelock, AltoAdapter and VaultRegistry |
| `vault` | Live AltoVault address |
| `markets` | Complete reviewed current and historical market inventory, including both queues and all residual positions |
| `shareholders` | Material shareholder addresses whose balances and exit availability should be reported; `[]` is allowed |
| `quarantinedMarkets` | Reviewed quarantine history, including previously force-removed markets; `[]` is allowed if none exist |

For Ethereum, deployment addresses are loaded from
`contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-<deploymentId>/addresses.json`.
Verify that deployment against the selected live Vault.

Additional inputs:

- **Batch A:** `curatorSafe`, `allocatorsToRevoke`, and `timelockSafe` for owner work.
- **Batch B:** `action`, `noticeAt`, `noticeWaived`, the selected action's fields, and `noticeWaiverReference` when waived.
  Supply `timelockSafe` when routing a queue update through the Timelock.
- **Batch C:** `tokens`, `allocatorsToRevoke`, `timelockSafe`; add exceptional closure fields only when explicitly approved.
- **Monitoring:** common inputs; optional `allocatorsToRevoke` includes those addresses' current permission status.

`allocatorsToRevoke` lists only permissions approved as nonessential; `[]` is valid. Revoking an allocator mapping does
not remove the owner or curator's inherent allocator authority. Batch A retains the current curator and guardian.

Use raw integer token amounts and raw share units, not human-readable decimal amounts. Asset limits use the Vault
underlying token's units; each skim approval uses its token's units. Zero limits are strict. Preserve integer precision
when copying report values into approvals; reports serialize amounts as decimal strings.

Reconstruct inventory from current state, deployment records and historical events. Queue coverage checks cannot discover
all historical positions, unknown allocators, tokens or shareholders. Include positions whose expected assets round to
zero but whose supply shares remain nonzero. Independently verify that the Vault is not any underlying market's fee
recipient; this requirement is reported but is an operator check, not a preparation gate.

## Generate and monitor

Run from the repository root with Foundry, `jq` and an archive RPC available. Set `RPC_URL` to the approved endpoint and
prepare the activation-specific manifest before running:

~~~bash
MANIFEST_PATH="ERP/ERP-OFFBOARD-03/config/vault-offboarding-incident.json"
PHASE_ID=0
SOURCE_BLOCK="$(jq -r .sourceBlock "$MANIFEST_PATH")"

FOUNDRY_PROFILE=erp forge script \
  ERP/ERP-OFFBOARD-03/scripts/VaultOffboarding.s.sol:VaultOffboardingScript \
  --sig "run(uint256,string)" "$PHASE_ID" "$MANIFEST_PATH" \
  --fork-url "$RPC_URL" \
  --fork-block-number "$SOURCE_BLOCK" \
  -vvvv
~~~

Use `PHASE_ID=1` for every Batch B action and select `action` in the manifest. Use `PHASE_ID=2` for Batch C.
The fork block must equal `sourceBlock`. Recompute `SOURCE_BLOCK` after changing the manifest.

Reporting is available before T0, between checkpoints and throughout residual processing:

~~~bash
MANIFEST_PATH="ERP/ERP-OFFBOARD-03/config/vault-offboarding-incident.json"
SOURCE_BLOCK="$(jq -r .sourceBlock "$MANIFEST_PATH")"
INCLUDE_BORROWERS=false

FOUNDRY_PROFILE=erp forge script \
  ERP/ERP-OFFBOARD-03/scripts/VaultOffboarding.s.sol:VaultOffboardingScript \
  --sig "monitor(string,bool)" "$MANIFEST_PATH" "$INCLUDE_BORROWERS" \
  --fork-url "$RPC_URL" \
  --fork-block-number "$SOURCE_BLOCK" \
  -vvvv
~~~

Set `INCLUDE_BORROWERS=true` to invoke the shared [borrower fetcher](../scripts/fetch-borrowers.ts) through FFI.
This requires Node.js 22.18 or newer and Goldsky access; `GOLDSKY_SUBGRAPH_URL` overrides the endpoint. The fetcher checks
indexing status and source-block availability. IO reads the candidates' live positions at the pinned block and includes
zero-debt candidates. These are underlying-market borrowers, not Vault shareholders. Monitoring does not reconcile
aggregate borrower shares or simulate liquidation. Normal phase runs and monitoring with `false` never query the subgraph.

## Outputs and execution

~~~text
# Batches A and C
ERP/ERP-OFFBOARD-03/output/<activationId>/phase-<phase>/step-<step>/source-block-<block>/

# Batch B
ERP/ERP-OFFBOARD-03/output/<activationId>/phase-1/step-<step>/source-block-<block>/action-<action>/

# Monitoring
ERP/ERP-OFFBOARD-03/output/<activationId>/monitor/step-<step>/source-block-<block>/
~~~

| File | Use |
| --- | --- |
| `inputs.json` | Manifest copied after successful preparation/reporting |
| `exposure-report.json` | Source snapshot; successful Batch C preparation adds `closure` |
| `vault-curator-safe.json` | Optional Safe Transaction Builder batch of direct Vault calls |
| `vault-allocator.json` | Optional generic transaction plan with its authorized caller and queue indexes |
| `vault-governance-schedule.json` | Optional Safe Transaction Builder call to schedule owner operations |
| `vault-governance-execute.json` | Matching call to execute the same Timelock operation |
| `borrowers.json` | Optional monitoring-only candidate list and subgraph/source metadata |

Execute Safe calls in their listed order. Recovery acceptance/reset calls must execute as one atomic Safe batch.
The allocator caller may be an EOA, bot or Safe; use the recorded caller and exact payload rather than treating the generic
plan as a Safe import file.

For each governance pair, execute the schedule from `timelockSafe`, wait until the operation is ready, recheck state, then
execute the matching file. Verify the deployed Timelock's `getMinDelay()`. Never mix files from different directories.
The predecessor is zero; operators enforce cross-run ordering. Salts include chain, Vault, activation, phase/action,
step and source block. Regenerating at a new block changes the operation ID and does not update or cancel an already
scheduled operation. Track and resolve superseded proposals separately.

The Vault's own timelock is separate: market removal uses `config[market].removableAt`, cap acceptance uses
`pendingCap[market].validAt`, and guardian removal uses `pendingGuardian().validAt`. Those dates follow the actual
submission transaction, not artifact generation or scheduling. Preparation waits for native readiness; severity does
not shorten either delay.

After identifying the selected run directory, preparation clears its old exposure report, legacy `closure-report.json`
and calldata before phase-specific parsing. A later failure may leave a fresh snapshot without a closure outcome;
`inputs.json` may still be from an older run. Use outputs only from a successful run. No-op runs write fresh reports and
remove stale calldata. Monitoring uses its own directory and does not delete transaction artifacts. Archive reviewed
artifacts before rerunning the same directory.

The exposure report includes accounting, direct underlying balance, queues, roles/pending changes, market positions,
quarantine, caps, registration, pause/freeze status, estimated liquidity and supplied shareholders' `maxWithdraw` and
`maxRedeem`. Batch C also reports listed token balances. Monitoring does not load Batch C token or closure approvals.
Publish liquidity with its source block/time and label it estimated, not reserved or guaranteed.

## Phase 0 — Batch A containment

Before generation, verify approval and complete scope, current roles, pending changes, fee state, queues, direct token
balances and every current/historical position. Identify the integrations required for withdrawal, redemption, accounting
and quarantine recovery.

Rerun phase `0` through the following stages. The builder selects the next work from current state; there is no separate
stage input.

1. **Core containment.** When needed, owner output revokes pending guardian and timelock changes, even if already mature.
   Curator output revokes pending cap/removal changes in market order, empties `supplyQueue`, then calls
   `submitCap(market, 0)` for each nonzero cap. Execute the owner administration before the curator batch. Positive-cap
   reductions require registry membership and the matching underlying asset; historical markets already at zero cap
   remain permitted. Do not remove underlying MarketRegistry membership while reduction or recovery depends on it.
2. **Fee shutdown.** After containment has executed, choose a fresh source block and rerun. If `fee != 0`, the only new
   work is owner `setFee(0)`. Execute it separately and record accrual, accounting changes and fee shares minted under the
   previous fee.
3. **Allocator cleanup.** Refresh and rerun after fee shutdown. Owner output revokes active allocator permissions explicitly
   listed in `allocatorsToRevoke`. The current curator and guardian remain in place. Rerun to confirm no work remains.

No fee or allocator cleanup is prepared while core containment work remains. Both the owner and curator artifacts may be
present in the first stage; completion of only one is insufficient to advance.

After execution, verify Notion's containment acceptance criteria: empty supply queue, zero caps/pending caps, no conflicting
pending administration/removals, zero fee, revoked listed permissions, `maxDeposit == 0`, `maxMint == 0`, and atomic
rejection of nonzero deposits/mints. Confirm ordinary funded markets remain enabled/in the withdrawal queue, quarantine
history is complete and exits remain operational subject to liquidity and functioning market calls.

Containment does not recall supplied assets or reserve liquidity. The Vault has no supported idle-liquidity reserve;
`reallocate` must resupply everything it withdraws, and after caps are zero it cannot move nonzero assets to a destination.
No reallocation, shareholder withdrawal or funded-market removal is generated here. Permissionless transfers/supply on
behalf remain possible. Prepare optional entry-integration changes separately and preserve every required exit route.

## Phase 1 — Batch B correction

Begin after completed containment, the applicable notice and approved simulations. Every action requires source time at
or after T0. All severities use the same action builders and containment checks.

| Severity | Notice required by the implementation | Nominal reporting days from T0 | Active window |
| --- | --- | --- | --- |
| `0` Medium | Nonzero `noticeAt`, at least seven days before T0; no waiver | 0, 1, 7, 14, 21, 28 | 28 days |
| `1` High | At least one day before T0, or a documented waiver | 0, 1, 4, 7, 10, 14 | 14 days |
| `2` Critical | Notice by T0, as early as practicable, or a documented waiver | 0, 1, 2, 3, 4, 5, 6, 7 | 7 days |

For High/Critical, Notion permits waiver when disclosure would materially increase protocol risk. Set `noticeWaived=true`
and supply `noticeWaiverReference`; `noticeAt` is still a required JSON field and may be zero when waived. The script
checks timing/reference presence, not the existence or sufficiency of public notice or Governance's decision.

Checkpoint dates and `activeWindowElapsed` are reporting information. They neither gate between-checkpoint actions nor
permit closure. `step` does not enforce sequencing or replace the Vault's native delays.

### Common rules and action selection

Keep the supply queue empty, performance fee zero, ordinary caps zero and ordinary pending cap changes absent.
Only action `4` permits selected recovery targets to have a pending or matching accepted cap. All open recovery caps
must therefore be included in that action. Pending removal of a retained market does not by itself block a queue reorder.

At each checkpoint, refresh shares, assets, losses, per-market positions/quarantine, borrower/liquidity information and
material shareholders' exit availability. Simulate proposed ordering and underlying-market scenarios, publish aggregate
exits/residuals and preserve all claims. The common rules apply to every action; they are not a separate transaction.

| `action` | Operation | Required action inputs | Output |
| --- | --- | --- | --- |
| `0` | Ordinary queue update | `allocator`, `withdrawQueue` | One allocator plan, or governance pair if allocator is the Timelock |
| `1` | Submit exceptional removals | `curatorSafe`, `removalTargets` with `market` per entry | Curator Safe batch |
| `2` | Execute exceptional removals | `allocator`, `withdrawQueue`, full `removalTargets`, combined removal/loss/quarantine limits | One queue update via allocator or Timelock |
| `3` | Submit recovery caps | `curatorSafe`, `recoveryTargets`, combined cap limit, `allocatorsToRevoke` | Curator Safe batch |
| `4` | Accept/reset recovery caps | Same as action 3 | One atomic curator Safe batch |

Selected exceptional lists must be nonempty, unique, nonzero and within `markets`. One invalid or unready selected target
rejects the entire preparation. Unrelated target lists are not parsed. All examples below are JSON fragments to merge
into the activation manifest; replace placeholders and illustrative raw amounts with exact reviewed values.

### Action 0 — ordinary withdrawal queue

Set `withdrawQueue` to the approved ordered **market addresses** to retain. The builder derives current queue indexes;
for example, current `[A, B, C]` and approved `[C, A, B]` produce `[2, 0, 1]`. Additions, duplicates and omission of ordinary
funded markets are rejected. Zero-share entries may be omitted; an unchanged queue generates no transaction.

Simulate the effect on exiting and remaining shareholders. Immediately before execution, re-read the queue, positions and
pending removals. Index-based updates are not idempotent, and the preparation-time funded-position check is not embedded
in the calldata. Regenerate/reapprove if those inputs change. Verify the resulting order and any deleted configurations.

### Actions 1 → 2 — exceptional funded-market removal

1. Obtain approval for the exceptional process, affected users, recovery plan and limits. Set action `1` and supply the
   target markets, for example `"removalTargets": [{"market": "<A>"}, {"market": "<B>"}]`.
2. Generate and execute the curator batch. Each target must be enabled, funded, in the withdrawal queue, with zero cap and
   no pending cap change. Calls are `submitMarketRemoval(market)` in manifest order. Existing pending removals are skipped
   without resetting their timestamps; all already pending means no transaction.
3. Wait until every selected `config[market].removableAt`. This is the native Vault delay measured from submission.
4. Refresh the source block, simulate the exact current outcome, approve fresh positions and set action `2`. Supply the
   full remaining `withdrawQueue` and the following fields:

~~~json
{
  "removalTargets": [
    { "market": "<A>", "approvedSupplyShares": 100, "approvedExpectedAssets": 10, "maxExceptionalRemovedAssets": 10 },
    { "market": "<B>", "approvedSupplyShares": 200, "approvedExpectedAssets": 20, "maxExceptionalRemovedAssets": 20 }
  ],
  "maxExceptionalRemovedAssets": 30,
  "maxLostAssets": 30,
  "maxQuarantinedAssets": 30
}
~~~

Each live position must exactly match its approval and fit its individual limit. The sum must fit the top-level removal
limit. Projected quarantine replaces selected targets' records with their removal amounts and retains other records;
projected loss uses the complete remaining queue and preserves previously stored loss. Both must fit Vault-wide limits.
All targets must be omitted; every other omitted market must have zero supply shares. The output is one queue update.
If a target has drained to zero shares, use ordinary queue removal instead of the exceptional funded-removal action.

Execute only after fresh-state review. Confirm each removed position remains owned by the Vault, its expected assets were
recorded in `quarantinedAssets`, its configuration was deleted and it left the withdrawal queue. Update the reviewed
quarantine inventory and record accounting effects. Removal does not transfer assets or release liquidity; it excludes
the position from ordinary withdrawal/accounting and may increase calculated loss.

### Actions 3 → 4 — quarantine recovery

Use this path to return a previously force-removed position to the withdrawal queue, allowing existing assets to support
shareholder exits again. Keep its history in `quarantinedMarkets` while processing the selected recovery list.

~~~json
{
  "recoveryTargets": [
    { "market": "<A>", "recoveryCap": 1, "maxTemporaryCapAssets": 1 },
    { "market": "<B>", "recoveryCap": 2, "maxTemporaryCapAssets": 2 }
  ],
  "maxTemporaryCapAssets": 3
}
~~~

1. Confirm registration, matching asset, quarantine history, no pending removal, sufficient queue capacity and that every
   supplied nonessential allocator has already been revoked. Approve the temporary cap exposure and economic effects.
2. Set action `3`; every target must be disabled with zero cap and no pending cap change. Generate and execute the ordered
   `submitCap(market, recoveryCap)` calls. Caps must be positive, fit `uint184`, and satisfy individual/combined limits.
3. Wait until all pending caps' `validAt`, refresh the source block and switch to action `4`. Keep every pending/open
   recovery target included. Do not rerun action `3` against already pending submissions.
4. Execute the generated calls as one atomic Safe batch in manifest order:

| Target state for action 4 | Calls |
| --- | --- |
| Disabled with matching matured pending cap | `acceptCap(market)`, immediately followed by `submitCap(market, 0)` |
| Enabled with matching positive cap, no pending change and no quarantine | `submitCap(market, 0)` only |
| Enabled with zero cap, no pending change and no quarantine | None; already completed |
| Conflicting state or immature pending cap | Preparation rejected |

The combined limit counts all declared recovery caps, including completed entries. Queue capacity counts only targets
that still need enabling. A completely recovered list produces no transaction. Supply queue emptiness prevents deposits,
but any temporary positive cap still requires the approved allocator controls and atomic reset.

After execution, verify every newly enabled market was appended to the queue, its quarantine record was deleted and its
cap/pending cap returned to zero. Verify the implemented accounting: recovered loss is
`min(current calculated loss, recorded quarantine, live expected assets)`; `lastTotalAssets` increases by
`live expected assets - recovered loss`. Partial recovery leaves unrecovered loss recognized. Re-enabling does not itself
withdraw assets, guarantee liquidity or clear unrelated bad debt.

### Residual claims

At the end of the active window, any remaining Vault shares, market supply shares, quarantine or unresolved accounting
continues through Batch B with no automatic deadline. Maintain containment, ordinary funded queue entries, quarantine
records and all required roles/integrations. Continue monitoring, reporting and approved queue/recovery actions.

Underlying-market rate, LTV, liquidation, pause/freeze or loss-treatment changes require their applicable ERP or separate
approval. Migration, reimbursement, incentives and settlement are separately prepared work. Time elapsed does not cancel
claims or authorize final Batch C integration removal.

## Phase 2 — Batch C recovery and cleanup

Obtain approval to progress under Notion's closure conditions. Ordinary cleanup requires zero Vault shares, every known
market's supply shares and quarantine, and zero `totalAssets`, `lastTotalAssets` and `lostAssets`. Both ordinary and
exceptional modes require empty supply queue, zero fee/caps and no pending cap changes.

### Token treatment and exceptional approvals

Supply `tokens` with the underlying token and every other reviewed token, for example:

~~~json
{
  "tokens": [
    { "token": "<underlying-token>", "approvedBalance": 100, "recipient": "<approved-recipient>" }
  ]
}
~~~

For each nonzero source balance, the approval must match the full balance exactly and the recipient must be nonzero.
Zero balances are skipped. The Vault cannot be a listed token or recipient. `skim` transfers the **entire execution-time
balance**, so recheck balances/recipients immediately before execution. Partial skimming and token retention are not
supported. Resolve earned fee shares/claims before clearing the fee recipient; fee zero alone is not evidence of settlement.

`exceptionalClosure` defaults to `false`. To prepare approved nonzero residual outcomes, add:

~~~json
{
  "exceptionalClosure": true,
  "closureApprovalReference": "<governance approval covering residuals, users, outcomes, treatment and loss limits>",
  "closureTreatmentReference": "<token/fee reconciliation and justification for the proposed cleanup>",
  "approvedTotalSupply": 0,
  "approvedTotalAssets": 10,
  "approvedLastTotalAssets": 10,
  "approvedLostAssets": 10,
  "maxLostAssets": 10,
  "maxQuarantinedAssets": 10,
  "closureMarkets": [
    { "market": "<A>", "approvedSupplyShares": 0, "approvedExpectedAssets": 0, "approvedQuarantinedAssets": 10 }
  ]
}
~~~

This example illustrates a single reviewed market with accounting residue. Include exactly one entry for **every** market
in `markets`, including zero positions. All four Vault totals and each market's shares, expected assets and recorded
quarantine must match the source state exactly. `maxLostAssets` bounds both stored and calculated loss;
`maxQuarantinedAssets` bounds aggregate quarantine. The references must support Notion's exact affected-user outcomes,
rounding/stranded balances and recovery/migration/reimbursement treatment; the script checks their presence, not their
substance or completeness.

Exceptional mode supports approved partial cleanup while shares/positions remain. This is not completion of Batch B or
formal decommissioning. Before final integration removal, treatment evidence must establish that approved residual
accounting/quarantine needs no remaining exit or recovery route.

### Execute cleanup, then rerun for integration removal

1. Generate phase `2`. Read `exposure-report.json.closure.outcome` and review the complete owner batch.
2. Execute the governance schedule/execute pair when present. Cleanup calls, where needed, are ordered as follows:

   - revoke pending removals, including unconditional revocation for every empty queue entry being omitted;
   - update the queue to retain funded entries in their existing relative order;
   - set approved skim recipients and skim listed nonzero token balances; clear the skim recipient afterward;
   - clear the fee recipient, revoke listed active allocator permissions and, only without live claims, clear the curator;
   - revoke pending timelock changes and resolve pending guardian changes. With live claims, preserve the current guardian;
     without live claims, submit guardian removal when needed.

3. Verify execution and choose a fresh source block. Refresh exceptional approvals, including accounting changes from
   `setFeeRecipient`. Continue Batch B while any Vault shares or market supply shares remain.
4. Once shares/positions are zero and all queue/configuration, token and role cleanup is reflected in source state, rerun
   phase `2` after the pending guardian removal's native `validAt` has elapsed.
5. Review and execute the final governance pair: accept guardian removal if needed, revoke AltoAdapter approval if present,
   then remove VaultRegistry membership if present. Its governance delay still applies after preparation.
6. Verify final state, separately complete deployment-specific cleanup and obtain formal Governance closure.

Revoking removal permissions before omitting empty entries restores the contract's funded-removal rejection if an entry
becomes funded before execution. Still re-read current queue indexes immediately before executing. Partial cleanup always
retains funded markets, current curator/guardian and both integrations. Full cleanup and final integration removal are
separate runs; the script never erases stored loss or quarantine records to make closure pass. Governance ownership remains.

| `closure.outcome` | Meaning and next action |
| --- | --- |
| `partial-cleanup-prepared` | Execute approved limited cleanup; preserve recovery routes and continue Batch B |
| `residual-claims` | Shares/positions remain but no partial cleanup calls are needed; continue Batch B |
| `full-cleanup-prepared` | Execute cleanup, refresh approvals/state and wait for guardian readiness before rerunning |
| `integration-removal-prepared` | Cleanup is reflected in source state; review and execute the final governance pair |
| `no-cleanup-required` | No generated work remains; perform external final-state verification and closure |

The `closure` object also contains `exceptionalClosure`, `closureApprovalReference` and `closureTreatmentReference`.
These are preparation outcomes, not execution receipts. There is no standalone closure report.

## Evidence, external work and verification

Complete Notion Section 5's scenarios before operational execution. Include no/front-loaded/final-shareholder exits,
queue-order effects, adverse liquidity, paused/frozen markets, no voluntary repayment, liquidation/bad debt, premature
registry removal, exceptional-removal accounting, full/partial/zero quarantine recovery, full queue capacity, token skims,
rounding and residual claims beyond the active window. Quantify user outcomes, fees, stored/calculated losses, quarantine,
recovery amounts, temporary cap exposure and protocol loss against approved limits.

Unlike the Mint/Borrow correction simulators, this script has no automated economic simulation gate or production
post-execution assertions. Reports are point-in-time observations. Development supplies decoded calls, transaction
simulation and before/after state verification; Risk reviews the evidence. Complete the Notion Section 6 record with the
exact commit, representative target, fork block, response tested, results, state diff and acceptance/retest decisions.

Preserve activation/notice approvals, manifests, source blocks/timestamps, reports, simulations, decoded calls, Safe
proposals, transaction hashes, operation IDs, actual callers and before/after state. Record failed or superseded proposals
and the treatment of every residual claim. Required live getters must work; a failed report is not evidence of zero exposure.

Entry discovery changes, rewards, keepers, interfaces, external incentives and other deployment-specific integrations are
separate work. The generated final integration calls cover only AltoAdapter and VaultRegistry. Keep every dependency needed
for user exits/recovery until the approved treatment removes that need.

Repository checks:

~~~bash
FOUNDRY_PROFILE=erp forge build
FOUNDRY_PROFILE=erp forge fmt --check ERP/ERP-OFFBOARD-03
jq empty ERP/ERP-OFFBOARD-03/config/vault-offboarding.json
git diff --check
~~~

Implementation reference: [phase builders](VaultOffboarding.sol), [types and manifest fields](IVaultOffboarding.sol),
[manifest/report IO](libraries/VaultOffboardingIO.sol), and [script entrypoints](scripts/VaultOffboarding.s.sol).
Transaction serialization is shared through [ERPOutputWriter](../libraries/ERPOutputWriter.sol).
