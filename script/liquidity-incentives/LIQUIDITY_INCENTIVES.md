# Liquidity incentive Safe transaction generator

`GenerateLiquidityIncentivesTransactions.s.sol` implements SOP Actions C, D, consolidation, and F2 as three deliberately separate Safe batches.

All token amounts are raw 18-decimal integers. Review decoded calls and quoted minimum outputs before importing any generated JSON into Safe.

## Phase 1: claims

This fetches and validates Stake DAO's current delegator merkle proof, generates Action C, and generates the exact current Convex ClaimZap payload for Action D.

```bash
LIQUIDITY_PHASE=claims \
forge script script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Output: `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-01-claims.json`

Execute this batch before selecting consolidation amounts. The next phase checks actual post-claim Safe balances instead of estimating accrued rewards.

## Phase 2: consolidation

Select any combination of scrvUSD, CRV, and CVX. A zero amount skips that asset.

- scrvUSD is redeemed directly through its ERC-4626 `redeem` function into crvUSD.
- CRV and CVX use fresh CoW sell quotes into crvUSD.
- Every CoW order receives an exact sell-token approval to the Vault Relayer and a Safe presignature on the Settlement contract.

Preview an individual quote without posting an order:

```bash
node script/liquidity-incentives/createCowPresignOrder.mjs \
  --sell-token <CRV-or-CVX-address> \
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
COW_SLIPPAGE_BPS=<approved-slippage-bps> \
COW_ORDER_VALIDITY_SECONDS=<approved-validity-seconds> \
COW_SUBMIT_ORDERS=true \
forge script script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

`COW_SUBMIT_ORDERS=true` is an explicit side-effect acknowledgement: running this command posts presign orders to the CoW mainnet order book. Do not rerun it blindly, because that would create additional orders.

Outputs:

- `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-02-consolidation.json`
- `contracts/deployments/ethereum-mainnet/output/cow-orders-liquidity-02-consolidation.json`

Review the `analytics` object for every order in the CoW order manifest before importing the Safe batch.

Execute the Safe batch and wait for every selected CoW order to settle. The presign transaction does not synchronously deliver crvUSD.

## Phase 3: Votium F2

After settlement, choose an amount no greater than the Safe's actual crvUSD balance. This phase approves exactly that amount to Votium and calls `depositIncentiveSimple` for one active round and the DUSD/frxUSD gauge.

```bash
LIQUIDITY_PHASE=votium \
VOTIUM_INCENTIVE_AMOUNT=<approved-settled-crvUSD-amount> \
forge script script/liquidity-incentives/GenerateLiquidityIncentivesTransactions.s.sol:GenerateLiquidityIncentivesTransactionsScript \
  --rpc-url ethereum -vvvv
```

Output: `contracts/deployments/ethereum-mainnet/output/safe-tx-liquidity-03-votium.json`
