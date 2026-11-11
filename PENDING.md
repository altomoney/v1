# Pending changes

Work that is not live on Ethereum mainnet.

## Parked branches

Features that are not on `dev` and are kept on their own branch until work on them resumes.

- [`11-11-feat_add_mint_curve_convex_positions`](https://github.com/altomoney/v1/tree/11-11-feat_add_mint_curve_convex_positions): the Mint Curve Convex positions feature, where a position borrows DUSD from a mint market, deposits it into a Curve pool and stakes the LP tokens on Convex. The branch holds the factory, position and beacon contracts with their deployment phase and tests, including the claiming of multiple reward tokens, and none of it was deployed.
- [`11-11-feat_add_wrapper_tokens_for_pt_rollover_markets`](https://github.com/altomoney/v1/tree/11-11-feat_add_wrapper_tokens_for_pt_rollover_markets): wrapper tokens that keep Pendle PT collateral in the same market across expiries, where a bot swaps the wrapped PT into the next PT with the same decimals so borrowers do not have to move markets. The branch holds the `WrapperToken` contract and a leverage swapper that unwraps and wraps it, with unit and fork tests, and none of it was deployed.
