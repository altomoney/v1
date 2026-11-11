# Alto v1

[![CI](https://github.com/altomoney/v1/actions/workflows/ci.yml/badge.svg?branch=dev)](https://github.com/altomoney/v1/actions/workflows/ci.yml)

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

## Layout

- `contracts/`: the protocol. `lending/` holds the markets, interest rate models, leverage, liquidation and the vault; `oracles/`, `usm/` (stability modules), `sdusd/`, `tokens/` (DUSD and ALTO), `staking/`, `rewards/` and `vesting/` are the other modules; `utils/` holds the adapter, registries, authorization and the emergency controller; `deployments/` holds the mainnet deployment library and the recorded addresses.
- `test/`: Foundry tests, mostly Branching Tree Technique suites with a `.tree` file next to each test, plus fork tests that need `ALCHEMY_KEY`.
- `script/`: the mainnet deployment script with its shell wrappers, run with `pnpm deploy:mainnet` and `pnpm verify:mainnet`.

## Deployments

Mainnet addresses are recorded in [`contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json`](contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json). The deployed contracts in scope of the bug bounty are listed in [security-review-engagements](https://github.com/altomoney/security-review-engagements/blob/main/deployments/mainnet.md).

Work that is not on mainnet, such as parked feature branches, is listed in [`PENDING.md`](PENDING.md).

## Development

Use the VS Code devcontainer for automatic tool and dependency setup.

For a local setup, install and activate [mise](https://mise.jdx.dev/getting-started.html), then run:

```bash
mise install
mise run setup
```

Without mise, install [Foundry](https://getfoundry.sh) 1.7.1 and pnpm 11, then run:

```bash
git submodule update --init --recursive
pnpm install --frozen-lockfile
forge build
```

### Tests

```bash
forge test
```

Fork tests run against Ethereum mainnet and are skipped unless `ALCHEMY_KEY` holds a key. Copy `.env.example` to `.env` and fill it in, or export the variable, to include them.

Proxy upgrade validation runs OpenZeppelin's upgrade checks through `ffi`, which is disabled by default. Rebuild the artifacts first:

```bash
forge clean && forge build && VERIFY_PROXY=true forge test --ffi
```

## Security

To report a vulnerability, email security@altofoundation.org. Audit reports, the commits they covered and the bug bounty terms are published in [security-review-engagements](https://github.com/altomoney/security-review-engagements). See [SECURITY.md](SECURITY.md) for details.

## License

Alto v1 is licensed under the GNU General Public License v3.0 or later, see [LICENSE](LICENSE). Alto's interfaces under `*/interfaces/` are MIT so integrators can import them freely; interfaces adapted from third-party code keep their original license. Files adapted from third-party code keep their original license and attribution, stated in each file's SPDX header and NatSpec.
