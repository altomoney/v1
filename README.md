# Tapioca Protocol V1 Monorepo

### Getting started

Install dependencies via forge and yarn

```
forge install
yarn
```

Compile contracts

```
forge build
```

Run tests locally (skip some fork tests for speed)

```
forge test
```

Run tests in fork mode

```
FORGE_PROFILE=fork forge test
```

# How-to deploy with gitmodules

1. Copy paste `.env.example/` to `.env/` and fill in the values. This is the `.env/` that'll be copied into each repo. It is needed for the Hardhat execution
2. Give `init.bash` execution rights with `chmod +x init.bash`
3. Run `./init.bash` to initialize the repos, and hardhat compilation
