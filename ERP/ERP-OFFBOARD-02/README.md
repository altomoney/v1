# ERP-OFFBOARD-02 operational scripts

These scripts generate the Safe Transaction Builder JSONs for the ordinary borrow-market off-boarding path. Contract
addresses are read from the checked-in Ethereum mainnet deployment output. The target market and rate arrays are
deliberate placeholders and must match the approved activation manifest before use.

## Structure

- `scripts/BatchA.s.sol` writes separate Freezer-Safe and Vault-curator-Safe containment batches.
- `scripts/DeployOwnerFixedRateIrmFactory.s.sol` deploys the factory directly with the production Timelock as owner.
- `scripts/BatchB.s.sol` writes the atomic Timelock pair that deploys and attaches one dedicated fixed-rate IRM per
  market at T0.
- `scripts/BatchBLtvReduction.s.sol` writes one approved rate/LTV correction step. Run it again from fresh state for
  each later scheduled or terminal step.
- `scripts/BatchC.s.sol` verifies the ordinary recovery gates and writes the final registry and integration-removal
  Timelock pair.
- `scripts/ErpOffboard02Json.sol` contains the common Safe/Timelock JSON encoder and validates the production
  Timelock Safe route.
- `output/` is generated and ignored except for `.gitkeep`.

## Manual governance and allocator boundaries

- The Vault allocator is an EOA. Batch A does not generate `setSupplyQueue` or `reallocate` calldata, and Batch C does
  not generate `updateWithdrawQueue` calldata. The allocator must perform those operations in the canonical order.
- Execute `batch-a-freeze-safe.json` before `batch-a-vault-curator-safe.json`, then complete the allocator’s supply
  queue removal and approved reallocation. The distinct Safe routes cannot enforce this cross-Safe ordering onchain.
- Batch C verifies that every configured Vault market has already been removed cleanly before it writes final-removal
  JSON.
- Notice dates, severity calendars, economic limits, liquidatable-position outcomes, and Internal Governance
  approvals are inputs to the approved manifest/simulation; Solidity cannot infer them.
- The scripts implement the ordinary zero-debt/zero-Vault-supply path only. They do not implement exceptional
  `submitMarketRemoval`, loss taking, residual repayment, or governance-liquidation transactions.
- Fully backed direct supply or collateral may remain as legacy user claims in Batch C. The market stays frozen and
  unpaused, and its oracle and direct withdrawal routes are not removed.

## Generate operational JSON

Run from the repository root on an Ethereum mainnet fork. No environment manifest is read.

```bash
FOUNDRY_PROFILE=erp_offboard_02_live forge script \
  ERP/ERP-OFFBOARD-02/scripts/BatchA.s.sol:BatchAScript \
  --sig run --fork-url "$RPC_URL"
```

Deploy the factory once with the production deployment wallet. The constructor sets the production Timelock as the
initial owner; there is no follow-up ownership transfer.

```bash
FOUNDRY_PROFILE=erp_offboard_02_live forge script \
  ERP/ERP-OFFBOARD-02/scripts/DeployOwnerFixedRateIrmFactory.s.sol:DeployOwnerFixedRateIrmFactoryScript \
  --sig run --fork-url "$RPC_URL" --broadcast
```

Pass the deployed factory address to the T0 generator. `setOwnerFixedRateIrmFactory` and the storage placeholder remain
available for test fixtures.

```bash
FOUNDRY_PROFILE=erp_offboard_02_live forge script \
  ERP/ERP-OFFBOARD-02/scripts/BatchB.s.sol:BatchBFixedRateIrmScript \
  --sig "run(address)" "$DEPLOYED_FACTORY_ADDRESS" --fork-url "$RPC_URL"

FOUNDRY_PROFILE=erp_offboard_02_live forge script \
  ERP/ERP-OFFBOARD-02/scripts/BatchBLtvReduction.s.sol:BatchBLtvReductionScript \
  --sig run --fork-url "$RPC_URL"

FOUNDRY_PROFILE=erp_offboard_02_live forge script \
  ERP/ERP-OFFBOARD-02/scripts/BatchC.s.sol:BatchCScript \
  --sig run --fork-url "$RPC_URL"
```

Import each generated `*-schedule.json` from the Safe recorded in its metadata. Import the matching `*-execute.json`
only after the Timelock operation is ready and the required fresh simulation and governance checks pass. Timelock
operations use a zero predecessor and zero salt.

Generated files are state-specific. Regenerate and decode them after any contract upgrade, ownership change, target
change, parameter change, or other retest trigger.
