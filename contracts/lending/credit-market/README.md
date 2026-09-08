# Convex Credit Line

> [!WARNING]
> This implementation has not been tested or audited and is not ready for
> production deployment.

## Facility model

`AltoConvexCreditLine` is a dedicated, single-account Mint Market. A configured
Curve LP deposit gates access to a revolving credit limit and is staked in one
validated Ethereum Convex pool.

The contract is a direct `AltoBaseMarket` variant, like `AltoBorrowMarket` and
`AltoMintMarket`. The narrowly scoped changes made to the audited base contract
to support this inheritance are recorded in
[`README_ALTO_BASE_MARKET_CHANGES.md`](README_ALTO_BASE_MARKET_CHANGES.md).

An Alto-compatible lending oracle values the LP for borrowing. New debt must
remain below `maxLtv`, while a separate, higher `foreclosureLtv` gives the
account room to cure a position after price movement or interest accrual. The
market has no permissionless liquidation: only governance may seize the entire
LP position and close all debt after the foreclosure threshold is breached.
Outside foreclosure, the LP cannot leave the market until all borrow shares are
repaid.

## Standard market compatibility

The market implements `IMarketStaticTypes` and reports `MarketType.CREDIT_MINT`.
Existing integrations can query the familiar tuples:

- `totalSupply.assets` is the synthetic credit limit;
- `totalSupply.shares` is always zero;
- `totalBorrowed` uses the standard Mint Market asset/share accounting;
- the credit account's `position.borrowShares` is its debt;
- the credit account's `position.collateralAssets` is accounted Curve LP; and
- `position.supplyShares` is always zero.

`oracle()` and `maxLtv()` retain their standard market meanings. The
credit-specific `foreclosureLtv()` reports the threshold for permissioned full
foreclosure. `liquidationEngine()` continues to return zero. Supply,
liquidation-engine, callback-authorization, and public `liquidate` operations
revert explicitly. `governanceLiquidate` is supported only for the configured
credit account after its foreclosure threshold is breached. Indexers and
frontends must still branch on `MARKET_TYPE()` because this market has no public
or partial liquidation path.

## Borrowing and repayment

A draw requires:

1. the position owner to equal the configured `creditAccount`;
2. the caller to be the account or an authorized account delegate;
3. the market to be neither paused nor frozen;
4. post-accrual debt, including the opening fee, to remain within the credit
   limit; and
5. post-borrow debt to remain at or below `collateralValue * maxLtv`.

There is no separate absolute LP minimum. A zero-collateral position has zero
oracle-supported borrowing capacity, while any positive deposit supports only
the debt permitted by its current value and `maxLtv`.

Interest may take existing debt above the credit limit. That prevents new draws
but does not itself execute foreclosure. Anyone may repay the credit account.
LP withdrawal requires the caller to be the account or an authorized delegate
and requires exactly zero remaining borrow shares.

The oracle follows `ILendingOracle`: one unit of LP is quoted in one unit of the
borrow token with `1e36` precision. Collateral value is rounded down and debt is
rounded up. A zero oracle price is rejected; production oracle freshness and
validity policy must be enforced by the oracle itself.

## Governance foreclosure

`governanceLiquidate(creditAccount)` first accrues interest and then requires:

```text
debt value > collateral value * foreclosureLtv
```

If breached, the operation clears all account and global debt assets and shares,
clears the recorded collateral, unwraps every recorded LP from Convex (or uses
idle LP following an emergency exit), and transfers the LP to governance. The
facility may be used again after new LP is deposited. The operation is available
while paused or frozen so emergency controls cannot block enforcement.

Opening fees and interest already recorded in `claimableFeesAssets` remain
claimable after foreclosure, matching Mint Market bad-debt accounting. Public
`liquidate(...)` remains unsupported and no liquidation engine, partial seizure,
callback, repayment, auction, or liquidation incentive is involved.

## Convex custody

Initialization validates that the selected Booster pool returns the configured
Curve LP, a nonzero deposit token, gauge and reward pool, and is not shut down.
It also validates that the reward pool reports the selected pool ID, Booster
operator, and deposit token before granting the Booster an LP allowance.

Deposits and withdrawals verify exact raw-LP and staked-balance deltas. Tokens
with transfer fees or other balance-changing behavior are unsupported.
Withdrawals use `withdrawAndUnwrap(amount, false)`, so a broken reward token or
extra-reward claim is not intended to block repayment-driven LP exit.

The owner can permanently exit Convex only while the market is fully paused.
This moves all reward-pool stake into idle market custody without changing
position accounting, clears the Booster allowance, and disables future LP
deposits. After unpausing, repayment and zero-debt withdrawal use the idle LP.

Governance foreclosure uses the same withdrawal path to seize the full LP
position after an oracle-confirmed foreclosure-LTV breach.

## Rewards

Convex claims are permissionless because the caller cannot choose either the
recipient or tokens during a claim. The exact credit account may update
`rewardRecipient`; borrowing delegates and governance cannot do so. Unclaimed
rewards follow the recipient configured when `claimRewards()` executes.

The primary reward-pool token must be allowlisted and cannot be removed.
Governance may add reward-token addresses subject to the initialization
constraints and the 16-token cap. It may remove a non-primary token only while
the market holds none of that token. Every configured reward balance is
forwarded to the current `rewardRecipient`; reward balances never affect credit
or LP accounting.

> [!WARNING]
> Reward tokens are a trusted configuration boundary. Every configured address
> must be a functioning ERC-20 whose `balanceOf` and `transfer` calls remain
> callable. If governance adds a malformed or non-compliant token,
> `claimRewards()` can revert while decoding `balanceOf()`. Because
> `removeRewardToken()` also reads `balanceOf()`, the invalid entry may be
> impossible to remove through the current interface, blocking reward claims
> until the implementation provides a recovery path or is upgraded.

Convex may add new extra rewards after deployment. Governance should add the
corresponding token before the next claim. An unconfigured reward will otherwise
remain in the market if claimed. Live pool rewards must therefore be monitored,
including any StashTokenWrapper used by newer Convex pools. Removing a token does
not stop Convex from distributing it: governance must claim existing rewards and
confirm that the reward program has ended before removal. If emissions resume,
the token must be re-added so that its balance can be forwarded.

## Fixed-rate IRM

The credit market accepts only an IRM reporting `IRMType.FIXED_RATE`.
