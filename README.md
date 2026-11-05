# Alto v1

Alto v1 is a lending and stablecoin protocol built around DUSD.

## How it works

- **Mint markets back DUSD.** Users deposit collateral and mint DUSD against it,
  creating debt secured by that collateral. Borrowing limits and liquidation
  rules enforce collateral requirements.
- **Borrow markets provide DUSD lending.** Suppliers deposit existing DUSD.
  Borrowers deposit collateral and borrow from that supplied liquidity, paying
  interest. Borrow markets do not mint new DUSD.
- **Credit-line markets provide dedicated DUSD credit.** Each market is deployed
  for a specific credit account, which deposits collateral to obtain DUSD credit.
  Debt can only be opened on behalf of that market's configured credit account.
- **Lending vaults allocate DUSD.** Users deposit DUSD and receive ERC-4626 shares.
  The vault allocates DUSD across configured borrow markets, providing liquidity
  to borrowers. Interest earned by those allocations accrues to vault depositors.
- **Stability modules** exchange DUSD and supported assets using configured
  prices, fees and limits.
- **sDUSD** accepts DUSD deposits in exchange for shares. Allocated protocol fees
  unlock gradually, increasing the DUSD backing those shares.

DUSD minted against collateral can be supplied directly to borrow markets or
deposited into a vault that supplies those markets.

## Development

Use the VS Code devcontainer for automatic tool and dependency setup.

For a local setup, install and activate [mise](https://mise.jdx.dev/getting-started.html), then run:

```bash
mise install
mise run setup
```

Copy `.env.example` to `.env` and set `ALCHEMY_KEY` for fork tests.

### Tests

Run the test suite:

```bash
forge test
```

For proxy upgrade validation, rebuild the artifacts first:

```bash
forge clean && forge build && VERIFY_PROXY=true forge test
```
