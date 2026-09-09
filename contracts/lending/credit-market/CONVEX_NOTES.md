# Curve LP and Convex Flow

This document is a practical guide to how Curve LP tokens move through Convex
in `AltoConvexCreditLineMarket`. It is intended to give enough context surrounding the
follow of custody, rewards, and withdrawals.

The important tokens are:

- **Curve LP token (`lpToken`)**: received when liquidity is added to a Curve
  pool. This is the token deposited into the credit line by the user.
- **Convex deposit token (`depositToken`)**: a 1:1 receipt created when the
  Curve LP is deposited through Convex. It is often named `cvx<Curve LP>`.
- **Reward-pool staking token**: the token accepted by the Convex reward pool.
  For the selected pool, this must be the same `depositToken` returned by the
  Booster.
- **Reward tokens**: CRV, CVX, and any pool-specific extra rewards. These are
  yield and do not form part of the credit line's facility-deposit accounting.

## Example Pool Configuration

These are the current Ethereum pool targets for the frxUSD+DUSD integration.
They must be independently verified against `Booster.poolInfo(pid)` before any
deployment; this list should not be treated as a deployment source of truth.

- frxUSD+DUSD Curve LP: `0x104d6a1b97A6CEf88D905d7b865A378d90be932A`
- frxUSD+DUSD Curve Gauge: `0xA41eb3062FD68B6Fa9f11439C86503913806761D`
- Convex Booster: `0xF403C135812408BFbE8713b5A23a04b3D48AAE31`
- Convex Rewards: `0x0E80Fe9D6F6dF530ab2Ff69ad0259e77E2ffEdeb`
- Convex Deposit Token (`cvxfrxUSDDUSD`): `0xEFB03B5f93c0E7C29Ab0AD4DE06bfA871aE23749`
- Convex Stash: `0x63a59A5733c15F83C5Cb088F14Af08Bac674877f`
- Convex PID: `565`

## Convex Components

### Booster

The Booster is the main entry point used by the credit line. A pool ID selects
a `poolInfo` record containing:

- the Curve LP accepted by the pool;
- the Convex deposit token;
- the underlying Curve gauge;
- the Convex reward pool;
- the pool's stash; and
- whether the pool has been shut down.

`deposit(pid, amount, stake)` moves Curve LP into the Convex system. Convex
ultimately stakes the LP through its Curve gauge position and creates the
corresponding deposit-token receipt.

The `stake` argument controls what Convex does with that receipt:

- `true`: stake the deposit token in the reward pool on behalf of the caller;
- `false`: transfer the unstaked deposit token back to the caller.

It does **not** decide whether the raw Curve LP enters Convex. The raw LP enters
Convex in both cases.

### Curve gauge

The Curve gauge is where the Convex system places the raw Curve LP to earn Curve
incentives. The credit line does not call the gauge directly.

### Deposit token

The deposit token represents the Curve LP deposited through Convex. It is a
transferable receipt.

The reward pool reports this token from `stakingToken()`. The credit line checks
that it matches the deposit token returned by `Booster.poolInfo(pid)`.

### Reward pool

The reward pool accepts the Convex deposit token and attributes a staked balance
to each account. In the current design, `balanceOf(address(creditLine))` is the
observable custody record for the credit line's Convex position.

The reward pool also exposes the two operations used here:

- `getReward(account, true)` claims primary and extra rewards; and
- `withdrawAndUnwrap(amount, false)` removes the reward-pool stake and unwraps
  the Convex position back into raw Curve LP without also claiming rewards.

### Stash

The stash is part of Convex's handling of pool-specific extra rewards. The
credit line does not call it directly. Its practical relevance is that extra
reward tokens can be added or changed outside the credit line.

## Current deposit flow (`stake = true`)

Before interacting with this market, a user obtains Curve LP by adding liquidity
to the relevant Curve pool. Depositing that LP into the credit line then follows
this general flow:

1. User deposits the Curve LP to the `AltoConvexCreditLineMarket` contract.
2. `AltoConvexCreditLineMarket` calls into the Convex `Booster` contract to deposit.
3. The Convex system places the Curve LP into the pool's Gauge, creates the
   deposit-token receipt, and stakes that token in the reward pool.

At the market level, the sequence is:

1. `addCollateral` increases the credit account's
   `position.collateralAssets` in raw Curve-LP units.
2. `_receiveCollateral` transfers exactly that amount of Curve LP from the
   caller into the credit line.
3. The credit line calls `Booster.deposit(pid, amount, true)`.
4. The Booster consumes the raw LP and stakes the resulting deposit token in
   the reward pool on behalf of the credit line.
5. The credit line verifies that its idle Curve-LP balance returned to its
   previous value and that its reward-pool balance increased by exactly
   `amount`.

The credit line therefore does not retain either raw Curve LP or unstaked Convex
deposit tokens. Its assets are represented by the position inside the Convex
reward pool.

The accounting unit nevertheless remains the raw Curve LP:

- `position.collateralAssets` records the amount deposited by the user; and
- `stakedCollateralAssets()` reads the corresponding reward-pool balance.

The implementation assumes these quantities remain 1:1. It does not contain a
share-price or exchange-rate calculation.

## Reward flow

While the Convex deposit token is staked, rewards accrue to the credit line's
reward-pool account.

`claimRewards()` is permissionless, but the caller cannot choose either the
tokens or their destination:

1. The credit line calls `getReward(address(this), true)`. Passing `true` asks
   Convex to include extra rewards.
2. Convex transfers or mints the claimed reward tokens to the credit line.
3. The credit line checks the balance of every configured reward token.
4. Each entire configured balance is forwarded to the current
   `rewardRecipient`.

Rewards do not increase collateral, credit capacity, or repayment balances.
They are economically separate from the line of credit.

The exact credit account can update `rewardRecipient`; unclaimed rewards follow
the recipient configured at claim time. Governance can add reward-token
addresses to the reward list, up to the 16-token cap. Governance can remove an
inactive non-primary reward only when the credit line holds none of that token.
Removal uses swap-and-pop, so token indices are not stable.

> [!WARNING]
> Reward tokens are a trusted configuration boundary. Every configured address
> must be a functioning ERC-20 whose `balanceOf` and `transfer` calls remain
> callable. If governance adds a malformed or non-compliant token,
> `claimRewards()` can revert while decoding `balanceOf()`. Because
> `removeRewardToken()` also reads `balanceOf()`, the invalid entry may be
> impossible to remove through the current interface, blocking reward claims
> until the implementation provides a recovery path or is upgraded.
>
> A contract-code check before storing a token rejects EOAs. It does not prove
> ERC-20 compliance or protect against a contract that later changes behavior,
> so governance must still verify and trust every reward token before adding it.

Convex may introduce a new extra reward after deployment. If governance has not
added that token before `getReward(..., true)`, it will remain in the credit line
because `claimRewards()` only forwards known tokens. Operational review of live
pool rewards is therefore still required. The same applies after removal:
governance must first claim accrued rewards and confirm that future distribution
has ended. A token that resumes distribution must be re-added before its market
balance can be forwarded.

## Withdrawal flow

The credit account can unwind part or all of its LP while it has borrow shares,
provided the remaining position is solvent at the market's `maxLtv`. Removing
collateral reverses the corresponding portion of the Convex position.

`withdrawAndUnwrap(amount, false)` performs both layers of the exit: it removes
the deposit token from the reward pool and unwraps the Convex receipt back into
raw Curve LP. Passing `false` avoids coupling a collateral withdrawal to reward
claiming.

The credit line checks that its raw LP balance increases by exactly `amount`
before sending that LP to the receiver. This deliberately rejects fee-on-
transfer tokens and other behavior that breaks the assumed 1:1 accounting.

## Emergency exit

While fully paused, the owner may call `emergencyExitConvex()`. This unwraps the
entire reward-pool stake into raw Curve LP but leaves the LP idle in the credit
line rather than sending it to the borrower.

The operation:

- does not change `position.collateralAssets`;
- clears the Booster allowance;
- permanently marks the Convex strategy inactive; and
- leaves repayment and solvent LP withdrawal available after unpausing.

This is a custody migration from “staked through Convex” to “idle in the credit
line,” not a collateral withdrawal.

Permissioned full foreclosure uses this same custody flow. After interest is
accrued and the oracle-valued position exceeds `foreclosureLtv`, governance
clears the credit account's entire debt and collateral position, unwraps all
staked (or idle) LP, and receives the raw LP. Public and partial liquidation
remain unsupported.
