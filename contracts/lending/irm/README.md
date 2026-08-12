# Peg-Responsive Interest Rate Model

> [!WARNING]
> `PegResponsiveIrm` has **not been audited** and is **not ready for production
> deployment**. Economic parameter selection, Curve-oracle fuzz and mainnet-fork
> testing, full Mint Market integration, deployment tooling, and external
> security review remain outstanding.

## Overview

This document describes [`PegResponsiveIrm`](./PegResponsiveIrm.sol), an
interest-rate model for an Alto Mint Market that responds to an observed
DUSD/quoteToken peg price.

The controller is intended to make borrowing progressively more expensive as
DUSD trades below its target:

1. At healthy prices, it returns a configurable base rate.
2. Between the recovery and stress thresholds, it increases the rate linearly.
3. Below the stress threshold, it increases the rate exponentially.

The controller also provides recovery hysteresis, oracle freshness validation,
pause-aware accrual timing, and owner-controlled configuration replacement.

The completed PRM work is deliberately narrow:

- **In scope:** the peg-responsive IRM, its interface, mocks, unit tests, fuzz
  tests, and stateful invariant tests.
- **Separate component:** the draft Curve-backed peg oracle is documented in
  its [local README](../../oracles/dusd/README.md).
- **Not yet completed:** integration testing against a real Alto Mint Market,
  oracle-specific fuzz and mainnet-fork testing, deployment tooling, economic
  parameter selection, an audit, or production deployment.

Several contracts, interfaces, libraries, and utilities have been copied from
the main repository only to provide the dependencies needed to compile and
exercise the IRM.

Open design and integration decisions that must be resolved before finalization
are tracked in [`NOTES.md`](./NOTES.md).

## How the controller works

### Price regions

The raw price-to-rate curve has three regions:

| Region  | Price                                  | Raw target                                                |
| ------- | -------------------------------------- | --------------------------------------------------------- |
| Healthy | `price >= recoveryPrice`               | `baseRate`                                                |
| Bridge  | `stressPrice <= price < recoveryPrice` | Linear interpolation from `baseRate` to `stressRate`      |
| Stress  | `price < stressPrice`                  | Exponential growth from `stressRate`, capped at `maxRate` |

The bridge prevents a discontinuous jump when the price first begins weakening.
The exponential region then produces a much stronger response after the
configured stress threshold.

### Example

The default test fixture uses the following illustrative configuration. It is a
test configuration, not a deployment recommendation.

| Parameter          |                       Test value |
| ------------------ | -------------------------------: |
| Recovery price     |                        `$1.0000` |
| Stress price       |                        `$0.9950` |
| Base rate          |   `5%` annualized SPY equivalent |
| Stress rate        | `7.5%` annualized SPY equivalent |
| Doubling distance  |                        `$0.0025` |
| Maximum rate       | `800%` annualized SPY equivalent |
| Recovery delay     |                        `6 hours` |
| Maximum oracle age |                     `30 minutes` |

Ignoring fixed-point rounding, its raw curve produces:

| DUSD price | Raw target | Explanation                           |
| ---------: | ---------: | ------------------------------------- |
|  `$1.0000` |       `5%` | Recovery boundary                     |
|  `$0.9975` |    `6.25%` | Halfway through the linear bridge     |
|  `$0.9950` |     `7.5%` | Stress boundary                       |
|  `$0.9925` |      `15%` | One doubling distance below stress    |
|  `$0.9900` |      `30%` | Two doubling distances below stress   |
|  `$0.9875` |      `60%` | Three doubling distances below stress |
|  `$0.9850` |     `120%` | Four doubling distances below stress  |
|  `$0.9800` |     `480%` | Six doubling distances below stress   |

A smaller `doublingDistance` makes the stress curve steeper. A larger value
makes it gentler. Expressing steepness this way allows governance to reason in
terms of an additional price decline rather than an abstract exponential
coefficient.

### Checkpoint ordering

Rates change only when the market checkpoints the IRM. A checkpoint performs
the following operations:

1. Calculate interest for the elapsed interval using the previously stored
   borrow rate.
2. Read and validate the current peg observation.
3. Update stress and recovery state.
4. Calculate the effective target rate.
5. Store that rate for the next interest interval.

The return tuple from `updateInterestRate` is:

```solidity
(uint256 interest, uint256 borrowRate)
```

`borrowRate` is the old stored rate used to calculate `interest`. The newly
selected rate is stored in the IRM and applies prospectively. A newly observed
depeg therefore does not retroactively charge a higher rate for time that has
already elapsed.

`PegResponsiveIrm` is best understood as a discrete, checkpoint-driven
controller. It accrues the elapsed interval using the previously stored rate,
then samples the oracle and installs a new rate for the next interval.
`maxOracleAge` limits the age of an observation when a checkpoint occurs; it
does not cause checkpoints or bound how long the stored rate may remain active.
Production operation therefore requires a defined maximum checkpoint interval
and a reliable keeper or equivalent liveness mechanism.

The market's `accrueInterest()` function is permissionless while the market is
unpaused, so a keeper is viable. An automation service is one possible
implementation, but it remains an operational assumption rather than an
on-chain guarantee.

The IRM calculates interest but does not itself update user or market balances.
The calling market applies the returned interest to its accounting. In the Mint
Market design, increasing total borrowed assets without increasing borrow shares
increases the debt represented by each existing borrow share.

### Recovery hysteresis

Stress mode begins when a valid price reaches or falls below `stressPrice`.

While stress mode is active:

- the effective rate cannot fall below `stressRate`;
- a valid price at or above `recoveryPrice` starts recovery confirmation;
- a later qualifying checkpoint may end stress mode after `recoveryDelay`; and
- a processed invalid observation or a price below `recoveryPrice` clears the
  recovery timer.

Hysteresis does not hold the rate at its highest crisis value. If a 30% raw
target falls back toward 7.5% as the price improves, the live rate may follow it.
Hysteresis only prevents the effective rate from falling below `stressRate`
until recovery is confirmed.

The contract observes the peg only when called. It cannot prove that the price
remained above `recoveryPrice` continuously between checkpoints. Precisely, one
qualifying checkpoint starts recovery and a later qualifying checkpoint can
complete it after the delay, provided no intervening processed observation
cleared the timer.

### Invalid oracle observations

An observation is unusable when:

- the oracle call reverts;
- the oracle returns `valid == false`;
- the reported price is zero;
- the observation timestamp is zero;
- the observation timestamp is in the future; or
- the observation is older than `maxOracleAge`.

An unusable observation:

- cannot set a new borrow rate;
- leaves the current borrow rate unchanged;
- cannot enter or exit stress mode; and
- clears an in-progress recovery confirmation.

This is a fail-static rate policy, not a complete oracle safety system.

### Pausing

The market is expected to checkpoint immediately before pausing. While paused,
the market must not checkpoint the IRM.

On unpause, the IRM:

- moves `lastUpdate` to the current timestamp so the paused interval is not
  charged interest; and
- clears any in-progress recovery confirmation because no observations were
  processed while paused.

### Administrative updates

The owner can replace the peg oracle or curve configuration.

When the IRM is bound to an unpaused market, the current market state is
checkpointed before controller inputs are changed. If the IRM is unbound or the
market is paused, this checkpoint is skipped. Oracle and configuration changes
clear any in-progress recovery confirmation.

Configuration replacement cannot set `maxRate` below the rate stored after any
required pre-change checkpoint.

## Current design decisions

The following table records the behavior implemented by the current draft. It
does not mean every choice has been approved for production. Decisions requiring
dev-team confirmation, integration evidence, or further design work are
checklisted in [`NOTES.md`](./NOTES.md).

| Topic                     | Current implementation decision                                                                        | Important consequence                                                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| Controller timing         | The controller updates only at market checkpoints                                                      | Oracle updates do not update the live rate by themselves; response latency is unbounded without market activity or a keeper         |
| Accrual ordering          | The elapsed interval accrues at the previously stored rate                                             | A newly sampled price affects only the next interval and never reprices elapsed time                                                |
| Returned rate             | `updateInterestRate` returns the old rate used for elapsed interest                                    | The generic `IIrm` contract and market event semantics must agree that this is the elapsed rate, not the newly installed rate       |
| Rate movement             | A valid price installs the effective target directly                                                   | There is no independent increase/decrease speed limit; smoothing is delegated to the oracle signal and recovery hysteresis          |
| Raw curve                 | Healthy is flat, the bridge is linear, and stress is exponential with a configured cap                 | Curve shape and parameters require economic validation
| Recovery                  | Recovery uses wall-clock time between qualifying checkpoints                                           | It is sampled confirmation, not proof of continuous recovery; the IRM does not currently require `observedAt` to advance            |
| Invalid oracle            | The IRM holds the stored rate, preserves stress mode, clears recovery, and advances accrual time       | The fallback may retain either a low healthy rate or a high stressed rate; new-risk restrictions are outside the IRM                |
| Oracle/config replacement | The market is checkpointed under the old inputs before replacement                                     | The old-input-derived rate remains active until a later checkpoint; only recovery confirmation is reset immediately                 |
| Pause lifecycle           | The market checkpoints before pausing; unpause resets time and recovery but does not sample the oracle | The pre-pause rate remains active until the next checkpoint; the IRM makes no guarantee that a post-unpause checkpoint occurs       |
| Post-unpause liveness     | No keeper policy is encoded in the PRM                                                                 | Any requirement to checkpoint immediately after unpause belongs to market integration and keeper infrastructure                     |
| Compound interest         | `FixedPointMath.calculateCompoundInterest` is used as supplied by the main repository                  | Its approximation, cap, and supported rate/time domain have not been independently proven here                                      |
| Exponential curve         | `ExpLib.wExp` is used as supplied by the main repository                                               | Curve tests validate PRM behavior, but the library's approximation has not been independently proven here                           |
| Rounding                  | `multiplyWithPrecision` rounds accrued interest down                                                   | Rounding is borrower-favorable at the final fixed-point multiplication; the complete numerical error bound remains to be documented |
| Market binding            | `setMarket` is permissionless and one-shot                                                             | Safe deployment depends on atomically binding the intended market                                                                   |

## Curve mathematics

Let:

- $p$ be the observed DUSD/quoteToken price;
- $P_r$ be `recoveryPrice`;
- $P_s$ be `stressPrice`;
- $R_b$ be `baseRate`;
- $R_s$ be `stressRate`;
- $R_{\max}$ be `maxRate`; and
- $D$ be `doublingDistance`.

The raw target is:

```math
T_{\mathrm{raw}}(p)=
\begin{cases}

R_b,
& p \ge P_r \\[10pt]

R_b + (R_s-R_b)\dfrac{P_r-p}{P_r-P_s},
& P_s \le p < P_r \\[10pt]

\min\!\left\{
R_{\max},
R_s\,2^{\frac{P_s-p}{D}}
\right\},
& p < P_s

\end{cases}
```

### Healthy region

For $p \geq P_r$:

```math
T_{\mathrm{raw}}(p) = R_b
```

### Linear bridge

For $P_s \leq p < P_r$:

```math
T_{\mathrm{raw}}(p) = R_b + (R_s-R_b) \frac{P_r-p}{P_r-P_s}
```

The fraction is zero at `recoveryPrice` and one at `stressPrice`, producing a
continuous straight line between the two configured rates.

### Exponential stress region

For $p < P_s$:

```math
T_{\mathrm{raw}}(p) = \min\left( R_{\max}, R_s\,2^{\frac{P_s-p}{D}} \right)
```

The exponent is the number of doubling distances below `stressPrice`:

```math
x = \frac{P_s-p}{D}
```

- $x=0$ gives $R_s$;
- $x=1$ gives $2R_s$;
- $x=2$ gives $4R_s$; and
- $x=0.5$ gives approximately $1.414R_s$.

This is a continuous exponential curve rather than a staircase.

### Why the implementation calls an exponential library

Governance configures a doubling distance, while the existing `ExpLib` evaluates
the natural exponential. The two forms are equivalent:

```math
2^x = e^{\ln(2)x}
```

The implementation therefore evaluates:

```math
R_s e^{\ln(2)\frac{P_s - p}{D}}

```

This conversion is an implementation detail. The economic configuration remains
expressed as a base-2 doubling distance.

The implementation does not use Solidity’s exponentiation operator because it
only supports integer exponents and therefore cannot evaluate fractional doubling
distances. A custom fixed-point routine could compute $2^x$ directly, but the
implementation instead reuses the existing natural-exponential library through
$2^x = e^{\ln(2)x}$. This supports fractional doubling distances such as $2^0.5$
while avoiding a separate binary-exponential implementation.

The repository already provides `ExpLib`, which evaluates fixed-point $e^x$.
Using the mathematically exact change-of-base identity above preserves the governance-facing
doubling-distance formula while avoiding a second power library and its
additional mathematical and audit surface. This is an implementation choice,
not a different economic curve. `ExpLib` remains an existing dependency that must
be independently validated before production use.

In simplified pseudocode:

```solidity
if (price >= recoveryPrice) {
    rawTarget = baseRate;
} else if (price >= stressPrice) {
    progress = (recoveryPrice - price) / (recoveryPrice - stressPrice);
    rawTarget = baseRate + (stressRate - baseRate) * progress;
} else {
    depeg = stressPrice - price;
    exponent = ln(2) * depeg / doublingDistance;
    multiplier = exp(exponent);
    rawTarget = min(stressRate * multiplier, maxRate);
}
```

### Effective rate

Stress hysteresis is applied separately from the raw curve:

```math
T_{\mathrm{effective}} =
\begin{cases}

\max(T_{\mathrm{raw}},R_s), & \text{stress mode active} \\
T_{\mathrm{raw}}, & \text{otherwise}

\end{cases}
```

For a valid observation:

```math
R_{\mathrm{next}} = T_{\mathrm{effective}}
```

For an invalid observation:

```math
R_{\mathrm{next}} = R_{\mathrm{current}}
```

There is no separate rate movement or speed limit. The oracle's averaging policy
filters the price signal, the curve converts price into a target, and hysteresis
controls recovery below `stressRate`.

## Units and fixed-point representation

### Prices

Prices and `doublingDistance` use 18-decimal fixed-point precision:

| Human value | Contract value |
| ----------- | -------------: |
| `$1.00`     |         `1e18` |
| `$0.995`    |     `0.995e18` |
| `$0.0025`   |    `0.0025e18` |

### Rates

Rates use 18-decimal per-second yield, referred to as second percent yield
(`SPY`). They are not stored as APY values.

The curve acts on SPY values. Human-readable annualized percentages used in
examples or simulations must be converted before constructing `CurveConfig`.

### Interest

Conceptually, elapsed interest is:

```math
\mathrm{interest} = \mathrm{totalBorrowed} \left(e^{R_{\mathrm{SPY}} \Delta t} - 1 \right)
```

The implementation delegates the compound factor to the existing
`FixedPointMath.calculateCompoundInterest` Taylor-series approximation. That
library is an imported dependency and has not been independently validated by
this work.

## Configuration reference

| Field              | Unit               | Meaning                                                     |
| ------------------ | ------------------ | ----------------------------------------------------------- |
| `recoveryPrice`    | Price WAD          | Raw curve reaches `baseRate`; qualifying recovery threshold |
| `stressPrice`      | Price WAD          | Raw exponential region and stress-mode entry threshold      |
| `baseRate`         | SPY WAD            | Minimum raw target at healthy prices                        |
| `stressRate`       | SPY WAD            | Raw target at `stressPrice` and stress-mode floor           |
| `maxRate`          | SPY WAD            | Configured ceiling on the raw exponential target            |
| `doublingDistance` | Price WAD          | Additional depeg that doubles the stressed target           |
| `recoveryDelay`    | Seconds (`uint48`) | Required delay between qualifying recovery checkpoints      |
| `maxOracleAge`     | Seconds (`uint48`) | Oldest accepted oracle observation                          |

The contract enforces:

```text
0 < stressPrice < recoveryPrice <= 1.01e18

0 < baseRate <= stressRate < maxRate <= MAX_BORROW_RATE

doublingDistance > 0
recoveryDelay > 0
maxOracleAge > 0
```

`MAX_BORROW_RATE` is currently:

```solidity
8e18 / 365 days
```

This is an annualized continuously compounded rate input of 800%, represented
as SPY. It is a protocol safety bound on configurable `maxRate`, not a recommended
operating rate.

## Oracle boundary

The IRM consumes:

```solidity
function getPrice()
    external
    view
    returns (uint256 priceWad, uint48 observedAt, bool valid);
```

The IRM does **not**:

- read the Curve pool directly;
- calculate or smooth the source price;
- select the averaging window;
- validate pool liquidity or amplification;
- detect manipulation;
- compare independent price sources; or
- cap a valid reported spot price.

The draft [`DusdPegOracleCurve`](../../oracles/dusd/README.md) is responsible
for turning an approved high-amplification `[quoteToken, DUSD]` Curve pool into
a validated DUSD/quoteToken observation. The controller intentionally does not
treat or compose that observation as DUSD/USD; quoteToken/USD is a separate
monitored risk signal. The currently intended deployment uses frxUSD as
`quoteToken`. The Curve EMA period and `maxOracleAge` solve different problems:

- the Curve EMA period controls how quickly price history loses weight; and
- `maxOracleAge` controls how recently that observation must have been produced.

A longer EMA period reduces short-term noise but delays response. A shorter
period responds sooner but may be noisier and more influenceable. The oracle's
local [README](../../oracles/dusd/README.md) and
[handoff notes](../../oracles/dusd/NOTES.md) document this boundary and its
unresolved decisions.

## Market integration boundary

The IRM is bound to one market through `setMarket`.

Important integration assumptions:

- `setMarket` is permissionless and can only succeed once;
- the market address must be nonzero;
- deployment must bind the intended market atomically or otherwise prevent a
  third party from binding first;
- only the bound market can update the live interest rate or call the pause
  hook; and
- the market must obey the checkpoint-before-pause and reset-on-unpause
  lifecycle.

The main deployment flow is expected to deploy and bind deterministically in one
transaction. That deployment flow is not included or tested here.

## Testing

### Unit and fuzz coverage

| Suite           | Covered behavior                                                                                                                                                            |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Constructor     | Initial state, invalid owner/oracle/configuration, inclusive bounds, one-time market binding, authorization                                                                 |
| Curve           | Healthy, bridge, and stress regions; exact boundaries; continuity; monotonicity; integral and fractional doubling; maximum cap; extreme inputs; valid-configuration fuzzing |
| Controller      | Stress entry, stress floor, recovery start/interruption/completion, exact delay boundaries, invalid observations, preview behavior                                          |
| Oracle handling | Validity flag, zero price, zero/future/stale timestamps, exact freshness boundary, reverts, broad valid and invalid fuzz ranges                                             |
| Accrual         | Old-rate accrual, prospective rate storage, zero elapsed time, zero debt, sequential intervals, pause timing, debt/time monotonicity, large values                          |
| Administration  | Ownership, old-input checkpointing, paused/unbound behavior, oracle and configuration replacement, recovery reset, replacement validation fuzzing                           |
| Pause           | Checkpoint-before-pause, paused checkpoint rejection, unpause clock reset, recovery reset, authorization                                                                    |

The curve suite supplies the independent mathematical and metamorphic checks for
raw curve behavior. The accrual suite verifies how the IRM integrates the
existing interest helper, but it does not independently prove the
`FixedPointMath` approximation itself.

### Invariant scope

The invariant campaign is specifically a
`PegResponsiveIrm` **controller-state** campaign.

The handler can:

- produce valid observations;
- produce invalid-flag, zero-price, zero-timestamp, future, stale, and reverting
  oracle conditions;
- warp arbitrary bounded time;
- warp to `recoveryDelay - 1`, `recoveryDelay`, and `recoveryDelay + 1`;
- checkpoint healthy, bridge, and below-stress prices;
- checkpoint exact and adjacent stress/recovery boundaries;
- checkpoint the current observation;
- pause and unpause as separate state transitions; and
- attempt checkpoints while paused.

The invariant suite checks:

1. Exact equality between controller state and the ghost model.
2. Fixed market, oracle, and configuration bindings.
3. `baseRate <= borrowRate <= maxRate`, plus the stress floor while stressed.
4. Coherent `lastUpdate`, `recoveryStartedAt`, and `stressMode`.
5. Exact pause-state and paused-timestamp behavior.
6. Agreement between raw oracle ghost state, IRM validation, and
   `previewBorrowRate`.

The handler independently models oracle acceptance, stress transitions, recovery
timing, and the stress-rate floor. It deliberately treats two components as
trusted outputs:

- raw `targetBorrowRate` curve evaluation; and
- accrual returned by `updateInterestRateView`.

Those components are tested separately by the unit and fuzz suites. This avoids
copying every production calculation into the invariant model, while also
meaning the invariant suite alone is not proof of their mathematical
correctness.

Each handler checkpoint installs a bounded arbitrary debt amount. IRM state,
time, pause state, and recovery state evolve across the full sequence, but market
supply and debt do not evolve as a realistic sequence of deposits, borrows,
repayments, and interest checkpoints.

### Testing not yet completed

The following work remains outside the current test claim:

- integration against the real `AltoMintMarket`;
- deterministic deployment and atomic market binding;
- cumulative Mint Market debt, fee, supply, and share accounting;
- testnet deposit, mint, borrow, repay, liquidation, pause, and governance
  action sequences;
- completed deterministic and mainnet-fork tests for the draft Curve oracle;
- manipulation resistance, pool-liquidity assumptions, and oracle economics;
- independent high-precision verification of `ExpLib`;
- independent verification of `FixedPointMath.calculateCompoundInterest` and
  other utility modules;
- fork, deployment, migration, and upgrade testing;
- gas limits under production deployment conditions;
- economic simulation and governance parameter calibration;
- formal verification; and
- external security review.

## Excluded file rationale

`foundry.toml` intentionally scopes lint, coverage, and generated documentation
to the code developed in this workstream.

This repository contains a minimal slice of the main Alto codebase. Copied files
must compile so the PRM can be exercised, but they were not authored, reviewed,
or comprehensively tested as part of this project. Including them in every
report creates hundreds of inherited warnings and misleadingly lowers PRM
coverage with code outside the stated objective.

Exclusion means **out of scope**, not **safe**, **tested**, or **approved**.
All required source files are still compiled and may execute transitively in
tests. These settings change reporting scope; they do not remove dependencies
from the build or change deployed bytecode.

## Security status and limitations

### Audit status

- The PRM has not received an external audit.
- Passing tests are necessary but are not evidence of production safety.

### Trusted dependencies

The controller depends on existing code from the main Alto repository,
including:

- `ExpLib`;
- `FixedPointMath`;
- `AltoOwnable2Step`;
- the generic IRM and market interfaces;
- pause constants and market lifecycle behavior; and
- the eventual real Mint Market implementation.

The tests exercise some of these dependencies transitively. They do not establish
their independent correctness.

### Controller limitations

- The IRM trusts an owner-selected oracle and checks only the returned value,
  timestamp, validity flag, and ordinary call failure.
- The IRM does not create or independently validate the oracle's averaged price.
- Rate updates are checkpoint-driven.
- Recovery confirmation is based on observed checkpoints, not continuous proof
  of the intervening market price.
- Invalid observations hold the current rate. This may preserve either a low
  pre-stress rate or a high crisis rate until a valid observation returns.
- The configured exponential rate is capped.
- Curve and compounding calculations rely on fixed-point approximations and
  rounding.
- `setMarket` is permissionless and one-shot, so safe deployment depends on
  atomic binding.
- The owner can replace critical oracle and curve inputs.
- No production monitoring or emergency governance procedure is supplied.

### Economic limitations

The example configuration exists to make tests and formulas concrete. It has not
been selected through market simulation.

## Deployment checklist

No production deployment scripts are included. Before adding them:

1. Complete and review the real oracle.
2. Select parameters through economic simulation.
3. Complete the Mint Market integration suite.
4. Pin the toolchain used by CI and deployment.
5. Run formatting, lint, build, unit/fuzz, invariant, mutation, coverage, and
   static-analysis checks.
6. Obtain an external audit covering the IRM, oracle, math dependencies,
   deployment path, and market integration.
7. Deploy the oracle and verify its pool, quote asset, averaging window,
   heartbeat, and validity policy.
8. Deploy the IRM with the final owner and configuration.
9. Bind the intended market atomically.
10. Verify owner, pending owner, oracle, market, curve configuration, initial
    rate, and initial accrual timestamp on-chain.
11. Establish monitoring for oracle validity, observation age, peg price,
    stress state, recovery state, borrow rate, and rate-cap hits.
12. Document emergency oracle replacement, pause, and governance procedures.

## Governance checklist

Before adopting a configuration, governance should answer:

1. At what price should borrowing begin becoming more expensive?
2. At what price should stress mode begin?
3. What target rate is appropriate exactly at the stress threshold?
4. How much additional depeg should double that rate?
5. What extreme ceiling protects the implementation without weakening the
   desired response?
6. How long should recovery remain confirmed before stress mode ends?
7. What oracle averaging period balances manipulation resistance, noise, and
   response time?
8. How old may an observation be before it is rejected?
9. How frequently will the market checkpoint under normal and stressed
   conditions?
10. What off-chain monitoring and emergency actions are available if the oracle
    becomes unusable?

## Contributing and handoff expectations

Changes to the PRM should:

- preserve old-rate accrual and prospective rate updates;
- add unit or fuzz coverage for new mathematical behavior;
- add boundary tests for every changed comparison;
- update the invariant model when controller state transitions change;
- avoid modeling full Mint Market accounting inside the controller handler;
- document any new trusted dependency or Foundry exclusion; and
- update this README when scope or security claims change.
