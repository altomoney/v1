# EmergencyController mainnet upgrade

This deployment builds on the
[controller refactor](https://github.com/altomoney/v1/pull/661). The script and fork
tests use the refactor's `initializeV2()` and `contractWhitelist` API.

Run from the repository with the same `.env`, Foundry keystore `ACCOUNT`, and
deployer `SENDER` used by `alto-1.sh`. The deployment mode also requires `jq`.

Check the existing proxy, governance ownership, Owner Safe permissions, and live
timelock delay:

```bash
./_scripts/deployment/upgrade-emergency-controller-1.sh --preflight
```

Deploy one new EmergencyController implementation and generate the multisig JSON:

```bash
./_scripts/deployment/upgrade-emergency-controller-1.sh
```

The wrapper broadcasts only the implementation deployment. After that transaction
succeeds, it reads the confirmed implementation address from Foundry's broadcast
receipt and runs the JSON generator against mainnet. The existing proxy is upgraded
through the Owner Safe and timelock.

The generated files are:

- `contracts/deployments/ethereum-mainnet/output/safe-tx-emergency-controller-upgrade-schedule.json`
- `contracts/deployments/ethereum-mainnet/output/safe-tx-emergency-controller-upgrade-execute.json`

Import the schedule file into the [Owner Safe](https://app.safe.global/home?safe=eth:0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0)
and execute that proposal. After the delay printed by the script has elapsed from
the schedule transaction, import and execute the execute file from the same Safe.

Both files target timelock `0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86` and contain
the same one-call batch. The batch upgrades proxy
`0x3c822f14a90955bf35278b42BA509FeEcAD3a305` with
`upgradeToAndCall(newImplementation, abi.encodeCall(EmergencyController.initializeV2, ()))`.
This migrates the existing DUSD and UniversalRewardsDistributor addresses into
`contractWhitelist` in the same transaction as the upgrade.

To regenerate the JSON for an implementation that has already been deployed,
replace `IMPLEMENTATION` with its address:

```bash
./_scripts/deployment/upgrade-emergency-controller-1.sh --generate-json IMPLEMENTATION
```

This mode makes no deployment transaction. It checks that the supplied address has
deployed UUPS implementation code and that the proxy still uses the expected legacy
implementation. The generator prints the timelock operation ID for the batch.
