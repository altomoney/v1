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