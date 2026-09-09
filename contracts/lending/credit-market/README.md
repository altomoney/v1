# Convex Credit Line Market

> [!WARNING]
> This implementation has not been audited and is not ready for production
> deployment. Passing tests does not replace an independent security review.

Shared-contract changes are summarized in [Base market extensions](./BASE_MARKET_EXTENSIONS.md).

## Facility model

`AltoConvexCreditLineMarket` is a dedicated, single-account Mint Market. A configured
Curve LP deposit gates access to a revolving credit limit and is staked in one
validated Ethereum Convex pool.

An Alto-compatible lending oracle values the LP for borrowing. New debt must
remain below `maxLtv`, while a separate, higher `foreclosureLtv` gives the
account room to cure a position after price movement or interest accrual. The
market has no permissionless liquidation: only governance may seize the entire
LP position and close all debt after the foreclosure threshold is breached.
Outside foreclosure, LP may be withdrawn if the remaining position is solvent.

## Standard market compatibility

The market implements `IMarketStaticTypes` and reports `MarketType.CREDIT_MINT`.
Existing integrations can query the familiar tuples:

- `totalSupply.assets` is the synthetic credit limit;
- `totalSupply.shares` is always zero;
- `totalBorrowed` uses the standard Mint Market asset/share accounting;
- `badDebtAssets` is cumulative written-off debt that continues to consume the
  credit limit;
- the credit account's `position.borrowShares` is its debt;
- the credit account's `position.collateralAssets` is accounted Curve LP; and
- `position.supplyShares` is always zero.

`oracle()` and `maxLtv()` retain their standard market meanings. The
credit-specific `foreclosureLtv()` reports the threshold for permissioned full
foreclosure. `liquidationEngine()` returns its initialization value, but is not
used by foreclosure and cannot be changed afterward. Supply, liquidation-engine
configuration, callback authorization, and public `liquidate` operations revert
explicitly. `governanceLiquidate` is supported only for the configured credit
account after its foreclosure threshold is breached. Indexers and frontends
must still branch on `MARKET_TYPE()` because this market has no public or partial
liquidation path.

## Borrowing and repayment

A draw requires:

1. the position owner to equal the configured `creditAccount`;
2. the caller to be the account or an authorized account delegate;
3. the market to be neither paused nor frozen;
4. post-accrual debt plus cumulative bad debt, including the opening fee, to
   remain within the credit limit; and
5. post-borrow debt to remain at or below `collateralValue * maxLtv`.

There is no separate absolute LP minimum. A zero-collateral position has zero
oracle-supported borrowing capacity, while any positive deposit supports only
the debt permitted by its current value and `maxLtv`.

Interest may take active debt plus cumulative bad debt above the credit limit.
That prevents new draws but does not itself execute foreclosure. Anyone may
repay the credit account; repayment first claims all accrued interest and fees
to the fee recipient. LP withdrawal requires the caller to be the account or an
authorized delegate and requires the remaining position to be solvent.

The oracle follows `ILendingOracle`: one unit of LP is quoted in one unit of the
borrow token with `1e36` precision. Collateral value is rounded down and debt is
rounded up. A zero oracle price is rejected; production oracle freshness and
validity policy must be enforced by the oracle itself.

## Governance foreclosure

When the market is not fully paused, `governanceLiquidate(creditAccount, false)`
first accrues interest and then requires:

```text
debt value > collateral value * foreclosureLtv
```

Interest accrual is skipped while fully paused or when `skipAccrueInterest` is
true. If breached, the operation moves all active debt into `badDebtAssets`,
clears the account and global active debt, clears the recorded collateral,
unwraps every recorded LP from Convex (or uses idle LP following an emergency
exit), and transfers the LP to governance. New borrowing remains subject to
`totalBorrowed.assets + badDebtAssets <= creditLimit`. The operation is
available while paused or frozen so emergency controls cannot block enforcement.

Opening fees and interest already recorded in `claimableFeesAssets` remain
claimable after foreclosure, matching Mint Market bad-debt accounting. Public
`liquidate(...)` remains unsupported and no liquidation engine, partial seizure,
callback, repayment, auction, or liquidation incentive is involved.

## Convex custody

Initialization validates that the selected Booster pool returns the configured
Curve LP, a nonzero deposit token, gauge and reward pool, and is not shut down.
It also validates that the reward pool reports the selected pool ID, Booster
operator, and deposit token. Each deposit approves only its asset amount and
clears the Booster allowance after the call.

Deposits and withdrawals rely on the validated Convex contracts and their
boolean success values; no separate balance-delta checks are performed.
Withdrawals use `withdrawAndUnwrap(amount, false)` and do not claim rewards, but
still depend on the Convex reward pool and its extra-reward withdrawal calls.

The owner can permanently exit Convex only while the market is fully paused.
This moves all reward-pool stake into idle market custody without changing
position accounting and disables future LP deposits. After unpausing, repayment
and solvent collateral withdrawals use the idle LP.

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
