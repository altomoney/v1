# Pending changes

Work that is not live on Ethereum mainnet.

## Parked branches

Features that are not on `dev` and are kept on their own branch until work on them resumes.

- [`11-11-feat_add_mint_curve_convex_positions`](https://github.com/altomoney/v1/tree/11-11-feat_add_mint_curve_convex_positions): the Mint Curve Convex positions feature, where a position borrows DUSD from a mint market, deposits it into a Curve pool and stakes the LP tokens on Convex. The branch holds the factory, position and beacon contracts with their deployment phase and tests, including the claiming of multiple reward tokens, and none of it was deployed.
- [`11-11-feat_add_wrapper_tokens_for_pt_rollover_markets`](https://github.com/altomoney/v1/tree/11-11-feat_add_wrapper_tokens_for_pt_rollover_markets): wrapper tokens that keep Pendle PT collateral in the same market across expiries, where a bot swaps the wrapped PT into the next PT with the same decimals so borrowers do not have to move markets. The branch holds the `WrapperToken` contract and a leverage swapper that unwraps and wraps it, with unit and fork tests, and none of it was deployed.
- [`11-11-feat_add_linear_discount_pt_oracles`](https://github.com/altomoney/v1/tree/11-11-feat_add_linear_discount_pt_oracles): oracles that price Pendle PT collateral with a linear discount that shrinks to zero at maturity, like Spark's PT oracles, starting with PT-reUSD. The branch holds `ModuleLinearDiscount`, `AltoERC4626RatioLinearDiscountOracle` and its PT-reUSD implementation with the oracle deployer entry and tests, from PRs #488, #489, #511, #490 and #624, and none of it was deployed.

## Pending fixes

Fixes that are not on `dev` and are kept on their own branch until the contract they change is deployed again or upgraded.

- [`09-24-fix_altovault_maxdeposit_and_deposit_to_consider_borrow_market_s_supply_cap`](https://github.com/altomoney/v1/tree/09-24-fix_altovault_maxdeposit_and_deposit_to_consider_borrow_market_s_supply_cap): keeps `AltoVault.maxDeposit` and `maxMint` within what `deposit` and `mint` accept, from PR #663. The branch limits each market's room to the smaller of the vault's cap and the market's own supply cap, leaves paused and frozen markets out of the quote and rejects duplicate markets in the supply queue. The deployed vault is not upgradeable, so the branch must be applied before a new vault is deployed. Akira Nakao ([everforyou](https://github.com/everforyou)) reported that `maxDeposit` ignored the market's own supply cap and is credited in [ACKNOWLEDGEMENTS.md](https://github.com/altomoney/security-review-engagements/blob/main/ACKNOWLEDGEMENTS.md). When the branch is applied, update the Resolution of that acknowledgement.
- [`10-20-fix_guard_unpause_when_market_has_no_irm`](https://github.com/altomoney/v1/tree/10-20-fix_guard_unpause_when_market_has_no_irm): lets a market without an IRM be unpaused, from PR #681. On `dev`, `AltoBaseMarket` notifies the IRM on every unpause, so a market whose `irm` is the zero address can be paused but not unpaused. The branch skips the notification when no IRM is set. The branch must be applied before new markets are deployed or before the next upgrade of the existing markets, whichever comes first.
