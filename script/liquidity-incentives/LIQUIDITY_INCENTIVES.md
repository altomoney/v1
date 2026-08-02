# Liquidity incentive Safe transaction generator

`GenerateLiquidityIncentivesTransactions.s.sol` implements SOP Actions C, D, consolidation, and F2 as four separate Safe batches.

All token amounts are raw 18-decimal integers. Review decoded calls, minimum outputs, and balances before importing any generated JSON into Safe.

## Phase 1: claims and optional Yearn yield withdrawal

This phase:

- Fetches and validates Stake DAO's current delegator merkle proof, then generates Action C.
- Generates the exact current Convex ClaimZap payload for Action D.
- Optionally appends the Stake DAO Accountant claim for CRV earned by the DUSD/frxUSD gauge.
- Reads the Treasury Safe's Yearn vault shares and current price per share.
- Withdraws only the Yearn shares whose current LP value exceeds the retained LP principal.

The default retained principal is `215246` DUSD/frxUSD Curve LP tokens. Override it only when the approved principal changes. The default Yearn withdrawal maximum loss is 1 basis point, and the script rejects a value above 100 basis points.

```bash
LIQUIDITY_PHASE=claims \
forge script script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Optional overrides:

```bash
CLAIM_STAKEDAO_CRV=true \
YEARN_RETAINED_PRINCIPAL_LP=<raw-LP-principal> \
YEARN_MAX_LOSS_BPS=<0-to-100> \
LIQUIDITY_PHASE=claims \
forge script script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Output: `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-01-claims.json`

`CLAIM_STAKEDAO_CRV` defaults to `false`. Only setting it explicitly to `true` appends the Stake DAO Accountant `claim(address[],bytes[])` call for the DUSD/frxUSD gauge. The call uses one empty harvest-data entry, matching the Stake DAO UI transaction, and sends claimed CRV to the Treasury Safe. If there is currently no pending Stake DAO CRV, the enabled claim is a no-op.

If the Yearn position is worth no more than the retained principal, no Yearn transaction is appended. Nothing is withdrawn from Yearn, and the lack of Yearn yield does not make generation fail.

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
forge script script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Output: `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-02-curve-withdrawal.json`

If Phase 1 did not withdraw any Yearn yield, either skip Phase 2 or run it with `CURVE_LP_AMOUNT=0`. That produces a valid Safe batch with no transactions and does not require `CURVE_WITHDRAWAL_SLIPPAGE_BPS`.

Execute the non-empty Curve batch before selecting consolidation amounts. Use the Safe's actual frxUSD and DUSD balance increases after execution.

## Phase 3: consolidation to crvUSD

Select any combination of scrvUSD, CRV, CVX, frxUSD, and DUSD. A zero amount skips that asset.

- scrvUSD is redeemed directly through its ERC-4626 `redeem` function into crvUSD.
- CRV, CVX, frxUSD, and DUSD use fresh CoW sell quotes into crvUSD.
- Every CoW order receives an exact sell-token approval to the Vault Relayer and a Safe presignature on the Settlement contract.

Preview an individual quote without posting an order:

```bash
node script/liquidity-incentives/createCowPresignOrder.mjs \
  --sell-token <CRV-CVX-frxUSD-or-DUSD-address> \
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
CONSOLIDATE_FRXUSD_AMOUNT=<selected-frxUSD> \
CONSOLIDATE_DUSD_AMOUNT=<selected-DUSD> \
COW_SLIPPAGE_BPS=<approved-slippage-bps> \
COW_ORDER_VALIDITY_SECONDS=<approved-validity-seconds> \
COW_SUBMIT_ORDERS=true \
forge script script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

`COW_SUBMIT_ORDERS=true` is an explicit side-effect acknowledgement: running this command posts presign orders to the CoW mainnet order book. Do not rerun it blindly, because that would create additional orders.

Outputs:

- `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-03-consolidation.json`
- `contracts/deployments/ethereum-mainnet/output/cow-orders-liquidity-03-consolidation.json`

Review the `analytics` object for every order in the CoW order manifest before importing the Safe batch.

Execute the Safe batch and wait for every selected CoW order to settle. The presign transaction does not synchronously deliver crvUSD.

## Phase 4: Votium F2

After settlement, choose an amount no greater than the Safe's actual crvUSD balance. This phase approves exactly that amount to Votium and calls `depositIncentiveSimple` for one active round and the DUSD/frxUSD gauge.

```bash
LIQUIDITY_PHASE=votium \
VOTIUM_INCENTIVE_AMOUNT=<approved-settled-crvUSD-amount> \
forge script script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Output: `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-04-votium.json`
