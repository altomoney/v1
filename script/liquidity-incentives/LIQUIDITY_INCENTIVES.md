# Liquidity incentive Safe transaction generator

`GenerateLiquidityIncentivesTransactions.s.sol` implements SOP Actions C, D, consolidation, and F2 as three Safe transactions when Yearn reward withdrawal is not explicitly selected. An explicitly selected Yearn reward withdrawal adds a Yearn withdrawal transaction and a separate Curve LP removal transaction. The final phase leaves this run's crvUSD proceeds above the approved incentive cap in the Treasury Safe as crvUSD.

All token amounts are raw 18-decimal integers. Review decoded calls, minimum outputs, and balances before importing any generated JSON into Safe.

## Phase 1: claims and optional Yearn yield withdrawal

This phase:

- Fetches and validates Stake DAO's current delegator merkle proof, then generates Action C.
- Calls `claimRewards()` on the Convex credit line market for Action D. The market owns the staked LP and forwards CRV, CVX, and any WFRAX to the Treasury Safe.
- Optionally appends the Stake DAO Accountant claim for CRV earned by the DUSD/frxUSD gauge.
- When `CLAIM_YEARN_REWARDS=true`, reads the Treasury Safe's Yearn vault shares and current price per share.
- When `CLAIM_YEARN_REWARDS=true`, withdraws only the Yearn shares whose current LP value exceeds the retained LP principal.

Yearn reward withdrawal defaults to `false` and must be explicitly approved and enabled. When enabled, the default retained principal is `215246` DUSD/frxUSD Curve LP tokens. Override it only when the approved principal changes. The default Yearn withdrawal maximum loss is 1 basis point, and the script rejects a value above 100 basis points.

```bash
LIQUIDITY_PHASE=claims \
forge script --ffi script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Optional overrides:

```bash
CLAIM_STAKEDAO_CRV=true \
CLAIM_YEARN_REWARDS=true \
YEARN_RETAINED_PRINCIPAL_LP=<raw-LP-principal> \
YEARN_MAX_LOSS_BPS=<0-to-100> \
LIQUIDITY_PHASE=claims \
forge script --ffi script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Output: `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-01-claims.json`

`CLAIM_STAKEDAO_CRV` defaults to `false`. Only setting it explicitly to `true` appends the Stake DAO Accountant `claim(address[],bytes[])` call for the DUSD/frxUSD gauge. The call uses one empty harvest-data entry, matching the Stake DAO UI transaction, and sends claimed CRV to the Treasury Safe. If there is currently no pending Stake DAO CRV, the enabled claim is a no-op.

The Convex credit line market is `0x6b3458c87CD38aeFA6A5D059Eb19f609420DD852`. The claims simulation checks that its reward pool, Treasury recipient, and CRV/CVX/WFRAX reward list match the expected onchain configuration. It verifies that the market's pending CRV is cleared and that its configured token balances are forwarded to the Treasury. Previously claimed CRV and CVX already held by the Safe remain separate from this claim.

`CLAIM_YEARN_REWARDS` also defaults to `false`. Unless it is explicitly set to `true`, the claims batch does not inspect or interact with the Yearn vault. When enabled, if the Yearn position is worth no more than the retained principal, no Yearn transaction is appended. Nothing is withdrawn from Yearn, and the lack of Yearn yield does not make generation fail.

The Yearn calculation realizes only yield already reflected in the vault's current price per share. It does not call a Yearn strategy harvest and does not estimate unreported strategy gains.

Execute this batch before choosing the Curve LP withdrawal amount. The Yearn withdrawal is not exact in underlying LP units, so use the Treasury Safe's actual Curve LP balance increase after execution.

## Phase 2: Curve LP withdrawal

Set `CURVE_LP_AMOUNT` to the exact Curve LP amount received from Yearn in Phase 1. The script generates one balanced `remove_liquidity` call that burns that exact LP amount and returns both pool coins:

- coin 0: frxUSD (`0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29`)
- coin 1: DUSD (`0x63d74d22E689C715a04F2C13962b1f77F443d35b`)

The script calculates proportional expected outputs from current pool balances and enforces minimum amounts using the selected slippage. It rejects slippage above 100 basis points. No token approval is needed because the Curve pool burns its own LP token directly.

```bash
LIQUIDITY_PHASE=curve-withdrawal \
CURVE_LP_AMOUNT=<exact-LP-received-from-Yearn> \
CURVE_WITHDRAWAL_SLIPPAGE_BPS=<approved-0-to-100> \
forge script --ffi script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Output: `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-02-curve-withdrawal.json`

If Phase 1 did not withdraw any Yearn yield, either skip Phase 2 or run it with `CURVE_LP_AMOUNT=0`. That produces a valid Safe batch with no transactions and does not require `CURVE_WITHDRAWAL_SLIPPAGE_BPS`.

Execute the non-empty Curve batch before selecting consolidation amounts. Use the Safe's actual frxUSD and DUSD balance increases after execution.

## Phase 3: consolidation to crvUSD

Select any combination of scrvUSD, CRV, CVX, WFRAX, frxUSD, and DUSD. A zero amount skips that asset. CRV and CVX claimed during the credit line migration are already in the Safe, so include them in the selected amounts only if this run should convert them.

- scrvUSD is redeemed directly through its ERC-4626 `redeem` function into crvUSD.
- CRV, CVX, WFRAX, frxUSD, and DUSD use fresh CoW sell quotes into crvUSD.
- Every CoW order receives an exact sell-token approval to the Vault Relayer and a Safe presignature on the Settlement contract.

Preview an individual quote without posting an order:

```bash
node script/liquidity-incentives/createCowPresignOrder.mjs \
  --sell-token <CRV-CVX-WFRAX-frxUSD-or-DUSD-address> \
  --sell-amount <raw-18-decimal-amount> \
  --slippage-bps <approved-slippage-bps> \
  --valid-for <validity-seconds> | jq
```

Quote-only mode fetches a CoW quote and the current CoW Swap BFF USD reference prices, but it does not call the orders endpoint. Its `analytics` output and the submitted-order manifest include:

- Human-readable sell, expected-buy, minimum-buy, and network-fee amounts.
- Combined amount/value lines such as `1000 CRV ($216.360000)` and `216.147470 crvUSD ($216.027076)`.
- Expected and minimum crvUSD-per-sell-token rates.
- Input, expected-output, and minimum-output USD reference values.
- Expected price impact at the quoted output.
- Worst-case price impact at the order's minimum buy amount.
- Configured slippage and the network fee separately from price impact.
- The price-source URLs and retrieval timestamp.

Price impact uses the same USD-value definition as the CoW Swap frontend: `1 - output USD value / total input USD value`. A positive value is estimated value loss versus the reference prices; a negative value is estimated price improvement. It includes quoted fees and costs. The worst-case value additionally reflects the configured slippage floor. It is an estimate against timestamped reference prices, not a promise of the eventual settlement price.

```bash
LIQUIDITY_PHASE=consolidation \
CONSOLIDATE_SCRVUSD_AMOUNT=<selected-scrvUSD-shares> \
CONSOLIDATE_CRV_AMOUNT=<selected-CRV> \
CONSOLIDATE_CVX_AMOUNT=<selected-CVX> \
CONSOLIDATE_WFRAX_AMOUNT=<selected-WFRAX> \
CONSOLIDATE_FRXUSD_AMOUNT=<selected-frxUSD> \
CONSOLIDATE_DUSD_AMOUNT=<selected-DUSD> \
COW_SLIPPAGE_BPS=<approved-slippage-bps> \
COW_ORDER_VALIDITY_SECONDS=<approved-validity-seconds> \
COW_SUBMIT_ORDERS=true \
forge script --ffi script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

`COW_SUBMIT_ORDERS=true` is an explicit side-effect acknowledgement: running this command posts presign orders to the CoW mainnet order book. Do not rerun it blindly, because that would create additional orders.

Outputs:

- `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-03-consolidation.json`
- `contracts/deployments/ethereum-mainnet/output/cow-orders-liquidity-03-consolidation.json`

Review the `analytics` object for every order in the CoW order manifest before importing the Safe batch.

Execute the Safe batch and wait for every selected CoW order to settle. The presign transaction does not synchronously deliver crvUSD.

## Phase 4: capped Votium F2 and retained crvUSD surplus

After Phase 3 settles, set `LIQUIDITY_CRVUSD_PROCEEDS_AMOUNT` to the exact crvUSD amount attributable to this liquidity run. Do not include unrelated crvUSD already held by the Treasury.
Discard any Phase 4 JSON generated before the surplus-retention change, even if it contains only the Votium calls. Regenerate it from the current round, balances, and prices.

The script then:

- Reads the active Votium round and every existing third-party incentive for the DUSD/frxUSD gauge directly onchain.
- Fails if the Treasury has already posted an incentive in the active round, preventing an accidental duplicate.
- Values each external incentive and crvUSD with current CoW Swap BFF USD reference prices.
- Subtracts the external incentive value from the `$16,000` combined cap.
- Calculates the maximum post-fee crvUSD incentive allowed by the remaining USD cap.
- Grosses that amount up using Votium's current onchain `platformFee` and `DENOMINATOR` values.
- Deposits the lesser of that maximum gross amount and the selected crvUSD proceeds.
- Leaves all crvUSD above the gross Votium deposit in the Treasury Safe. No surplus swap is posted.

The calculation uses Votium's stored external incentive amounts. Those amounts are already net of Votium's fee. The generated allocation report shows external USD value, remaining cap, the maximum stored and gross crvUSD amounts, Votium fee, resulting stored incentive, combined USD value, and the full crvUSD surplus retained in Treasury.

First generate a read-only allocation plan:

```bash
LIQUIDITY_PHASE=votium-plan \
LIQUIDITY_CRVUSD_PROCEEDS_AMOUNT=<this-run-settled-crvUSD> \
forge script --ffi script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Output: `contracts/deployments/ethereum-mainnet/output/votium-allocation-liquidity-04.json`

Review the gross deposit and retained surplus. Then generate the executable batch:

```bash
LIQUIDITY_PHASE=votium \
LIQUIDITY_CRVUSD_PROCEEDS_AMOUNT=<this-run-settled-crvUSD> \
forge script --ffi script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Do not set `COW_SUBMIT_ORDERS=true` for this phase. The script rejects it. If external incentives have already consumed the cap, the script writes an empty Safe batch and reports all selected proceeds as retained crvUSD.

Outputs:

- `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-04-votium.json`
- `contracts/deployments/ethereum-mainnet/output/votium-allocation-liquidity-04.json`
- `contracts/deployments/ethereum-mainnet/output/cow-orders-liquidity-04-surplus.json` - an empty manifest that replaces any stale surplus-order file

The non-empty Phase 4 Safe batch contains only these calls in order:

1. If the calculated Alto incentive is non-zero, approve its exact gross crvUSD amount to Votium.
2. Deposit that exact gross crvUSD amount with `depositIncentiveSimple`. Votium takes its current fee and stores the net incentive for the active round and DUSD/frxUSD gauge.

Execute the Safe batch before the Votium incentivization deadline. Verify that the reported surplus remains as crvUSD in the Treasury Safe.

## Exact end-to-end execution steps

1. Run Phase 1. Review and execute the claims Safe batch. It claims Stake DAO scrvUSD, claims Convex CRV and CVX, optionally claims Stake DAO gauge CRV, and withdraws only Yearn LP value above retained principal.
2. Read the exact Curve LP increase received by the Treasury from the executed Phase 1 batch.
3. Run Phase 2 with that exact LP amount and approved withdrawal slippage. Review and execute the Curve batch. It burns the selected LP and sends frxUSD and DUSD to the Treasury without an approval.
4. Read the Treasury's actual scrvUSD, CRV, CVX, WFRAX, frxUSD, and DUSD balances to be included in this run.
5. Preview every required Phase 3 CoW quote. Review input USD value, expected and minimum crvUSD output, network fee, and expected and worst-case price impact.
6. Run Phase 3 once with `COW_SUBMIT_ORDERS=true`. Review and execute its Safe batch. It redeems selected scrvUSD directly into crvUSD, gives the CoW Vault Relayer exact sell-token allowances, and presigns the submitted orders.
7. Wait until every Phase 3 CoW order is fulfilled. Record the exact crvUSD proceeds attributable to this run.
8. Run `votium-plan` with that exact proceeds amount. Review the onchain external incentives, USD prices, cap arithmetic, gross Votium amount, fee, stored amount, and surplus.
9. Run Phase 4 and review the refreshed allocation report and Safe batch. Check that the surplus-order manifest is empty.
10. Execute the Phase 4 Safe batch before Votium's incentivization deadline. It deposits only the capped crvUSD incentive.
11. Confirm the Votium incentive onchain and verify that all reported surplus remains in the Treasury as crvUSD.

External incentive values and prices can change between generation and Safe execution. Generate Phase 4 as close as operationally possible to execution. If another external incentive changes before execution, discard the stale batch and regenerate it.
