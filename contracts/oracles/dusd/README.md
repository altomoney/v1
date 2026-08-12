# DUSD Price Oracle

> [!WARNING]
> `DusdPegOracleCurve` is a draft. It has **not been audited**, its deterministic
> and mainnet-fork test suites are only scaffolded, and its production pool and
> parameters have not been approved.

This document summarizes the Curve concepts and assumptions that matter when
deciding whether to use a DUSD/USD-par-token pool, such as DUSD/frxUSD, as the
price source for the DUSD peg-responsive interest rate model.

It also records the behavior of
[`DusdPegOracleCurve`](./DusdPegOracleCurve.sol). Unresolved design,
deployment, and validation decisions are tracked in [`NOTES.md`](./NOTES.md).

## Contract Summary

`DusdPegOracleCurve` is an adapter bound immutably to one approved two-coin
Curve StableSwap NG pool. It returns Curve's EMA price for DUSD quoted in a
USD-par reference token, together with Curve's last stored price-update
timestamp.

The contract is deliberately narrow:

- coin 0 must be the quote token;
- coin 1 must be DUSD;
- both coins must be standard ERC-20 Curve asset type `0`;
- the pool must be a non-meta, factory-registered two-coin pool;
- the factory-reported implementation must match the approved implementation;
- `ma_exp_time` must match the approved EMA time constant; and
- both current and future precise `A` must match the approved amplification.

These properties are checked at deployment. The controller-relevant values
`ma_exp_time`, `A_precise`, and `future_A` are checked again on every validated
price read. If governance changes any of them, the oracle stops producing a
valid observation until the pool state is restored or the oracle owner approves
new values that match the pool's current `ma_exp_time`, `A_precise`, and
`future_A`. These checks cannot be disabled.

The constructor separates these inputs by lifecycle. `curvePoolAddress` is a
standalone immutable pool binding. `DusdPegOracleCurveRuntimeConfig` contains
the approved EMA and amplification values retained by the deployed oracle and
accepted by the owner-only `setRuntimeConfig()` function.
`DusdPegOracleCurveValidationConfig` contains `curveFactory`,
`expectedCurvePoolImplementation`, DUSD, and quote-token addresses used only
for deployment validation; those values are not stored or exposed as oracle
getters.

### Validated price path

`getPrice()` returns:

```solidity
(uint256 priceWad, uint48 observedAt, bool valid)
```

Its current policy is:

1. Extract the price timestamp from the low 128 bits of `ma_last_time`.
2. Return `valid = false` if that timestamp is zero, in the future, or cannot
   fit the PRM's `uint48` timestamp type.
3. Return `valid = false` if `ma_exp_time`, current `A`, or future `A` no longer
   matches the approved configuration.
4. Read `price_oracle(0)` and return `valid = false` if the price is zero.
5. Otherwise return the EMA price and its source timestamp as valid.

The oracle does not enforce observation age. It reports `observedAt`, and the
PRM applies its own `maxOracleAge` when it checkpoints. These are separate
responsibilities: the Curve EMA controls smoothing, while the PRM freshness
limit controls how old the last stored pool observation may be.

Low prices are not invalid merely because they represent a severe depeg. The
oracle reports the signal; the PRM decides the corresponding rate.

Curve source-call failures revert from this adapter. That preserves the
difference between a source/integration failure and a successfully read value
that fails oracle policy. `PegResponsiveIrm` catches a reverting `getPrice()`
call and processes it as an unusable observation.

### Raw diagnostics

`rawPoolState()` exposes the current state price, last state price, stored and
projected EMA prices, packed timestamps, EMA time constant, current and future
`A`, and both pool balances.

This view is intentionally **unsafe for protocol decisions**. It performs no
policy validation or error handling and may revert. It exists for monitoring,
debugging, and explaining why `getPrice()` accepted or rejected a state.

## Curve Summary

A Curve StableSwap NG pool lets two stablecoins trade almost 1:1 while the pool
is reasonably balanced, but makes the price increasingly worse as one coin starts
running out.

StableSwap combines two familiar pool shapes, constant sum and constant product.

The StableSwap curve is almost flat in the middle, like constant sum. Near the
edges, it bends sharply, like constant product.

The pool does not know the USD price of either token. Its price comes from its
balances and trading activity.

StableSwap NG can also charge higher fees as the pool becomes imbalanced. These
fees affect trading and arbitrage, but are separate from the oracle's smoothing.

## Common Terms

### A: Amplification Coefficient

`A` controls how wide the nearly-flat 1:1 part of the curve is:

- Higher `A`: the pool continues offering close to 1:1 through a larger imbalance.
- Lower `A`: the price starts moving sooner.

At extreme imbalance, the protective curved portion eventually takes over.

An intuitive description is:

> A expresses how confident the pool is that the assets should be worth the same
> amount.

A high-`A` pool can become substantially imbalanced before its price moves far
from 1. The oracle thresholds must therefore be calibrated against the actual
pool.

### xp: Normalized Balances

`xp` refers to the token balances after they have been converted into common
18-decimal units. This lets Curve use assets with different decimals in the same
equation:

```python
xp[i] = rates[i] * balances[i] / 1e18
```

The index `i` identifies a coin. If `coins[1]` is DUSD, then `xp[1]` is the
normalized DUSD balance.

### D: The Pool Invariant

`D` is a single number describing the size of the pool's current StableSwap curve.
It is similar in purpose to `k` in a constant-product pool:

```math
k = x \cdot y
```

`get_D()` calculates `D` from the normalized balances, the number of coins and
`A`. When the pool is balanced, `D` is approximately the sum of its normalized
balances. Away from balance, it is best treated as a mathematical measure of pool
liquidity.

### dx, dy and get_y

For a swap from coin `i` to coin `j`:

- `dx` is the amount of coin `i` supplied by the trader.
- `dy` is the amount of coin `j` received by the trader.
- `x` and `y` are normalized pool balances, not the trader's amounts.

Curve adds `dx` to the input balance. `get_y()` then calculates how much of the
output coin must remain in the pool to preserve `D`:

```math
x_{\mathrm{new}} = x_{\mathrm{old}} + dx
```

```math
dy_{\mathrm{gross}} = y_{\mathrm{old}} - y_{\mathrm{new}}
```

The trader receives the gross `dy` less fees. Near balance, a high-`A` pool makes
`dy` close to `dx`. As the pool becomes imbalanced, `dy` becomes progressively
smaller.

## Pricing the Pool

The pool price is the slope of the invariant at its current balance point. It
answers:

> For a very small trade at the current balances, how much of one coin would be
> exchanged for the other?

Curve calls this the AMM State Price. It is calculated by `_get_p()` from the
normalized balances, `A` and `D`.

The state price is not:

- The average execution price of the last trade.
- The price of one particular trade.
- An external market price.

StableSwap NG builds its oracle from this state price rather than the last traded
price.

Curve uses coin 0 as the reference asset. In a two-coin pool,
`price_oracle(0)` represents the price of coin 1 relative to coin 0:

- If coin 0 is frxUSD and coin 1 is DUSD, it represents DUSD priced in frxUSD.
- If the coin order is reversed, the result must be inverted.

The coin order is therefore crucial.

## EMA Oracle

Curve stores the last AMM state price and the previous exponential moving average
(EMA). As time passes, it calculates:

```math
EMA_{\mathrm{now}}
=
\alpha EMA_{\mathrm{old}} + (1 - \alpha)P_{\mathrm{last}}
```

where:

```math
\alpha = e^{-\Delta t / \tau}
```

Said simply:

> The new EMA is partly the old EMA and partly the last observed pool price. The
> longer that price persists, the more weight it receives.

At a price-changing pool operation, Curve:

1. Advances the EMA using the previously stored state price.
2. Calculates the pool's new state price.
3. Stores that new state price for the next interval.

This prevents a newly observed price from being treated as though it existed
during the preceding interval.

Curve exposes four related values:

| Function          | Meaning                                              |
| ----------------- | ---------------------------------------------------- |
| `get_p(i)`        | Current state price calculated from current balances |
| `last_price(i)`   | Last stored state price                              |
| `ema_price(i)`    | EMA stored during the last oracle update             |
| `price_oracle(i)` | EMA projected to the current timestamp               |

### Half-Life and ma_exp_time

The half-life answers:

> If the pool price suddenly changes and stays there, how long does the EMA take
> to move halfway toward it?

Curve calls its exponential time constant `ma_exp_time`, or $\tau$. It is not
directly the half-life:

```math
halfLife = \tau \ln(2)
```

Therefore:

```math
maExpTime = \frac{halfLife}{\ln(2)}
```

The $\ln(2)$ appears because Curve uses the natural exponential for decay. At the
half-life `H`, half of the old information remains:

```math
\frac{1}{2} = e^{-H / \tau}
```

For a 10-minute half-life:

```math
maExpTime = \frac{600}{0.693} \approx 866
```

If the EMA starts at 1 and the pool price moves to 0.99 and remains there:

| Time             |     EMA |
| ---------------- | ------: |
| Immediately      |  1.0000 |
| One half-life    |  0.9950 |
| Two half-lives   |  0.9925 |
| Three half-lives | 0.99125 |

An EMA has no hard cutoff. Older information continuously loses weight instead
of disappearing at the end of a fixed TWAP window.

### Observation Time and Freshness

`price_oracle(i)` is a live calculation, but it is based on the last stored state
price. It does not create a fresh external market observation. A stale underlying
observation can therefore still produce a numerical return value.

Curve packs two update timestamps into `ma_last_time`:

- The low 128 bits contain the price-oracle update time.
- The high 128 bits contain the `D`-oracle update time.

These timestamps can differ. For example, a proportional liquidity withdrawal
can update `D` without changing the relative price.

## Decision-Relevant Assumptions

### DUSD/frxUSD is not necessarily DUSD/USD

The pool reports the relative price of its assets. It does not prove that frxUSD
is worth one USD.

Using the result directly as DUSD/USD assumes:

```math
P_{\mathrm{frxUSD/USD}} = 1
```

Otherwise, it must be combined with an independent frxUSD/USD source:

```math
P_{\mathrm{DUSD/USD}}

=

P_{\mathrm{DUSD/frxUSD}}

\cdot

P_{\mathrm{frxUSD/USD}}
```

### Response Time

The Curve half-life controls how quickly the EMA follows the pool state price.
The peg-responsive interest rate model only samples that EMA when the market
checkpoints.

Practical response time therefore includes:

1. Time for the Curve EMA to move.
2. Time until the next market checkpoint.

The half-life alone should not be treated as a maximum response time.

### Administration and Manipulation

Curve administration can change important parameters, including `A`, fees and
`ma_exp_time`. The current adapter requires exact approved `ma_exp_time`,
`A_precise`, and `future_A` values on validated reads. It does not pin fees or
the off-peg fee multiplier. Its owner can approve a new EMA time and precise
amplification only when both values match the live pool and no `A` ramp is in
progress.

A deep pool and an EMA make short-lived manipulation more expensive, but do not
make manipulation impossible. The pool is also a single price venue. Before
deployment, the response time and manipulation cost should be simulated using
the actual pool balances, `A`, fees, half-life, PRM thresholds and checkpoint
interval.

## Testing Status

The oracle test structure is present but the assertions are intentionally not
yet implemented.

Planned deterministic suites use configurable mock pool and factory contracts
to cover:

- every constructor validation independently;
- retained operational configuration and constructor-only factory provenance;
- validated timestamp, parameter-drift, and price behavior;
- source-call failures;
- broad valid and invalid fuzz inputs; and
- exact `rawPoolState()` field mapping and deliberate revert behavior.

A separate read-only Ethereum mainnet-fork suite is scaffolded to verify the
real pool ABI, factory registration, implementation, coin order, asset types,
approved `A` and EMA settings, timestamp interpretation, and returned prices at
a pinned block. Its addresses, expected values, pinned block, and assertions
must be filled from independently reviewed deployment records before the suite
provides evidence.

These tests do not replace economic analysis. Passing unit and fork tests can
show that the adapter reads the intended source according to its specification;
they cannot establish that manipulating that source is prohibitively expensive.

## Limitations

- The returned value is DUSD/quote-token, not inherently DUSD/USD.
- The quote token's dollar peg is not checked.
- The pool is a single price venue and no independent sanity source is used.
- No minimum-liquidity or manipulation-cost threshold is enforced.
- Pool fees and the off-peg fee multiplier are not pinned by this oracle, even
  though they affect manipulation economics.
- Curve administration can change relevant pool behavior. Changes to pinned
  `A` or `ma_exp_time` invalidate reads until restored or explicitly approved
  by the oracle owner; changes to unpinned parameters require monitoring and
  economic review.
- Curve's EMA needs state-changing pool activity to store a new state price.
- The oracle cannot make the PRM checkpoint and therefore cannot bound the time
  for a new price to affect borrowing rates.
- The contract and its copied Curve interfaces have not been audited in this
  repository.

The exact production choices and evidence required to close these limitations
are checklisted in [`NOTES.md`](./NOTES.md).
