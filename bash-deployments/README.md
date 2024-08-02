### Deprecation notice

Bash scripts are not maintained anymore and should be replaced with Foundry script orchestration. Saving bash scripts due may be helpful to still access bash deployment scripts.

# How-to deploy with gitmodules

1. Copy paste `.env.example/` to `.env/` and fill in the values. This is the `.env/` that'll be copied into each repo. It is needed for the Hardhat execution
2. Give `init.bash` execution rights with `chmod +x init.bash`
3. Run `./init.bash` to initialize the repos, and hardhat compilation
