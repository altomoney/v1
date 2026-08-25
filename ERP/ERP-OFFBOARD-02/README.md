# ERP-OFFBOARD-02 operational preparation

This folder follows the mainnet deployment pattern: typed inputs and phases, one library that validates current state,
builds ordered calls and writes Safe Transaction Builder JSON, and one thin script that loads deployment output.

## Structure

- `IBorrowMarketOffboarding.sol` defines `BorrowMarketOffboardingPhase`, params, minimal current-chain input and reports.
- `BorrowMarketOffboarding.sol` deploys or prepares and validates all five phases:
  - `DEPLOY_OWNER_FIXED_RATE_IRM_FACTORY`
  - `BATCH_A_CONTAIN`
  - `BATCH_B_SET_FIXED_RATE_IRM`
  - `BATCH_B_REDUCE_LTV`
  - `BATCH_C_RECOVER`
- `scripts/BorrowMarketOffboarding.s.sol` selects a phase, loads the complete named ERP current-chain input and invokes
  the library. It does not construct operational arrays or write Safe/Timelock artifacts.

## Configure a phase

Edit the constants near the top of `scripts/BorrowMarketOffboarding.s.sol`:

1. Set `PHASE_TO_RUN`.
2. Confirm `DEPLOYMENT_ID_TO_LOAD`, `FREEZER_SAFE` and `TIMELOCK_SAFE`.
3. In `BorrowMarketOffboarding.sol`, update the selected phase's explicit market argument constructor if the approved
   manifest names different targets.
4. For either Batch B phase, replace every placeholder SPY rate in its market argument constructor with the exact
   approved per-market encoding.

As in `DeployAltoEthereumMainnet.sol`, `runPhase` constructs a phase-specific parameter struct and passes it to that
phase's internal implementation. Shared runner parameters contain only the selected phase and Safe addresses.

IRM and liquidation-engine addresses are not loaded from JSON for correction steps. They are resolved from each
market at generation time and validated as dedicated and Timelock-owned.
Leverage swapper addresses are resolved on-chain from each configured `AltoLeverage` contract.

## Run

```bash
FOUNDRY_PROFILE=erp_offboard_02 forge script \
  ERP/ERP-OFFBOARD-02/scripts/BorrowMarketOffboarding.s.sol:BorrowMarketOffboardingScript \
  --sig run --fork-url "$RPC_URL"
```

Run the factory phase first with `--broadcast`. It deploys `OwnerFixedRateIrmFactory` with the production Timelock as
initial owner:

```bash
FOUNDRY_PROFILE=erp_offboard_02 forge script \
  ERP/ERP-OFFBOARD-02/scripts/BorrowMarketOffboarding.s.sol:BorrowMarketOffboardingScript \
  --sig run --fork-url "$RPC_URL" --broadcast
```

After deployment, manually add its logged address to the selected deployment JSON using the key
`.contracts.ownerFixedRateIrmFactory`. Later phases load that address from the JSON. The fixed-rate IRM attachment
phase validates that the code exists and that the production Timelock is the factory owner before generating calldata.

## Test

Run all current ERP phase tests with the dedicated profile:

```bash
FOUNDRY_PROFILE=erp_offboard_02 forge test --threads 1 -vv
```

Run one phase test directly when iterating, for example:

```bash
FOUNDRY_PROFILE=erp_offboard_02 forge test ERP/ERP-OFFBOARD-02/tests/BatchAContain.t.sol -vv
```

The current suite covers factory deployment, Batch A containment, both Batch B phases and ordinary Batch C recovery.
The Batch A test performs allocator-only supply-queue and reallocation actions directly on the fork; those actions are
intentionally absent from generated Safe JSON.

## Manual boundaries

- Execute the Batch A freezer file before the Vault-curator file.
- The allocator is an EOA. No `setSupplyQueue`, `reallocate` or `updateWithdrawQueue` calldata is generated. Batch C
  verifies that the allocator has already completed the required Vault queue changes.
- Batch C does not deprecate the Vault and does not require the Vault ERC-4626 `totalSupply()` to be zero. For every
  offboarded borrow market, ordinary recovery requires both `position[vault].supplyShares == 0` and
  `quarantinedAssets[market] == 0`.
- Before recovery, the allocator bot targets every old market at zero through `reallocate`. Any positive assets are
  supplied to a replacement borrow market only after it is registered, enabled in the Vault and given an approved cap.
- Because no replacement exists at the snapshot block, the fork test deploys a real WETH `AltoBorrowMarket` through
  the production `BorrowMarketBatch` path using deployment-script parameters, then calls the production Vault and all
  five production source markets through the real `reallocate` route.
- If positive residual value remains and no approved replacement market is ready, Batch C validation must stop
  recovery. Non-withdrawable residue requires a separate governance-approved exceptional path.
- Timelock operations use a zero predecessor and zero salt. Execute files are used only after the encoded delay and a
  fresh approved simulation.
- Notice timing, severity calendars, economic limits, residual repayments, liquidations and governance approvals are
  inputs to the activation process, not inferred by these scripts.
- Batch C implements zero-debt, zero-target-market-supply and zero-quarantine ordinary recovery. It does not generate
  exceptional `submitMarketRemoval` or loss-taking transactions.
