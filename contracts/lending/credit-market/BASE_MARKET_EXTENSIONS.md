# AltoBaseMarket Extensions for Convex Credit Line

This note summarizes the changes made to `AltoBaseMarket` for
`AltoConvexCreditLineMarket` relative to `origin/dev` commit
`aa71ec686335b0e372fa79a7096dc2ba0290520a`.

## Changes

- **Optional liquidation engine at initialization:** Base initialization now
  accepts `liquidationEngine == address(0)` and skips `setMarketOnce` in that
  case.
- **Virtual admin hooks:** Existing external owner-only setters now delegate to
  `_setIrm`, `_setOracle`, `_setMaxLtv`, `_setLiquidationEngine`,
  `_setAuthorizedLiquidationPeriphery`, and `_setAuthorizedCallback`. Their
  default behavior is unchanged.
- **Virtual collateral hooks:** `_addCollateral` calls `_receiveCollateral`, and
  `_removeCollateral` calls `_sendCollateral`. The default hooks retain the
  original ERC-20 transfers.
- **Overridable risk logic:** `_isSolvent` and `governanceLiquidate` are now
  `virtual` so the credit market can provide its own solvency and foreclosure
  rules.

## Credit-market overrides

- Accepts only fixed-rate IRMs.
- Validates `maxLtv` against `foreclosureLtv`.
- Disables public liquidation, liquidation-engine replacement, liquidation-
  periphery authorization, callback authorization, and lender supply.
- Uses the collateral hooks to stake Curve LP in Convex and unwrap it during
  withdrawal or foreclosure.
- Uses governance foreclosure to move active debt into cumulative
  `badDebtAssets`.

## Compatibility and constraints

- Base storage declarations and the storage gap are unchanged.
- No existing external Base function signature changed.
- Borrow and Mint markets continue to use the default setter and collateral
  hooks.
- Initializing any market with a zero liquidation engine is permanent under the
  current `_setLiquidationEngine` guard. Engine-dependent Base operations will
  fail for that market.
- The Convex credit market may start with no engine because it overrides the
  engine-dependent paths it exposes.

## Verification

```sh
forge test --match-path "test/lending/btt/Markets/convexcreditline/*.t.sol"
forge test --match-path "test/lending/btt/Markets/**/*.t.sol"
forge build --sizes contracts/lending/credit-market/AltoConvexCreditLineMarket.sol
```
