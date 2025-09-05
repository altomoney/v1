# Alto v1

## Setup
### Devcontainer
You may use prepared VS Code devcontainer that will set up all tools necessary.
### Fully Local Environment
Install following tools
- `foundry` tools
- `yarn`
- `lcov` (optional for code coverage)

and install dependencies
```bash
yarn
```

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
yarn deploy:testnet
```
The output is stored to `contracts/deployments/testnet/output`.