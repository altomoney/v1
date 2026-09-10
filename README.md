# Alto v1

## Setup

### Devcontainer

Open the repository in the VS Code devcontainer. It installs the tools declared
in `mise.toml` and runs `mise run setup` when the container is created or rebuilt.
Normal restarts do not reinstall dependencies.

### Fully Local Environment

Install [mise](https://mise.jdx.dev/getting-started.html), then run:

```bash
mise install
mise run setup
```

The same Node, Foundry, and Graphite versions are used locally and in the
devcontainer. mise reads the pnpm version from `package.json`. Install `lcov`
separately if you need code coverage outside the devcontainer.

Activate mise in your shell as described in its installation guide, or prefix
commands with `mise exec --`, for example `mise exec -- forge test`. Editors and
Git clients also need mise's shims on their PATH. The devcontainer configures
this automatically.

After pulling dependency or tool version changes, rerun `mise install` and
`mise run setup`. Setup installs the Git hook that formats staged Solidity files
with the pinned `forge fmt` before each commit.

## Testing
Test without proxy verification.
```bash
forge test
```
or with proxy verification (proxy verification requires up to date build)
```bash
forge clean && forge build && VERIFY_PROXY=true forge test
```

## Creating Addresses in Forge

**For development purposes only!**

Create a new wallet (private key will be displayed):
```bash
cast wallet new
```

Import the private key securely to vault:
```bash
cast wallet import --interactive <account_name>
```

## Deployment

- Create address as described above.
- Copy and create `.env` file using `.env.example` supplying address data and other information

### Testnet Deployment
```bash
pnpm deploy:testnet
```
The output is stored to `contracts/deployments/testnet/output`.

Verify (Optional)
```bash
pnpm verify:testnet
```
