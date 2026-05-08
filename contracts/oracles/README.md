# Oracle rounding

Oracle modules round in the direction that favors the protocol for the flow they serve.

## Collateral valuation rounds down

Collateral deposits and borrowing capacity are valued with floor division, so collateral is never overvalued.

- `AltoMultiChainlinkLendingOracle` uses `ModuleChainlink`, which floors.
- `AltoERC4626RatioChainlinkOracle` uses `ModuleERC4626Ratio` and `ModuleChainlink`, which both floor.
- `AltoERC4626RatioLinearDiscountOracle` uses `ModuleERC4626Ratio`, which floors, and `ModuleLinearDiscount`, which applies a time-based discount to PT-style assets until maturity and floors the result.

## Payments round up

Amounts users must pay, and prices of tokens users purchase, are rounded up so the protocol never receives less than it is owed.

- `ModuleUniswap` rounds up when `UniswapNode.roundUp` is set.
- `ModuleChainlink` only floors. A consumer that needs a rounded-up USD value rounds at the call site.
- `ModuleLinearDiscount` has no round-up mode.

## AltoRewardsOracle

Prices ALTO for `AltoRewardsDistributor`, which uses it as the exercise price of call options. `ModuleUniswap` rounds the TWAP price up, then `ModuleChainlink` floors the conversion to USD. The result is rounded up at the Uniswap step and down at the Chainlink step; consumers must not assume a final rounding direction.
