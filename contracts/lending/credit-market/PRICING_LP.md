# Pricing a StableSwap Cruve LP

## Option 1. Virtual Price x Minimum Asset Price

For a plain same-peg pool (_not a Meta pool_), an approach using the Pool's
`get_virtual_price`:

```math
P_{LP} = \text{virtualPrice} \cdot \min(P_1, \ldots , P_n)
```

where $P_i$ are independent prices for the underlying assets.

This approach was documented in [Nov 2020 from Chainlink](https://chain.link/blog/using-chainlink-oracles-to-securely-utilize-curve-lp-pools).

## Option 2. Compute the simple NAV

For pool balances $B_i$, independent underlying prices $P_i$, and LP total
supply $S$:

```math
P_{NAV} = \frac{\sum_iB_iP_i} {S}
```

with decimals normalized appropriately.

