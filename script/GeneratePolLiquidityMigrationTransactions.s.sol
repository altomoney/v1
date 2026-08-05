// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IConvexRewardPool {
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function operator() external view returns (address);
    function pid() external view returns (uint256);
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
}

interface IConvexBooster {
    function poolInfo(uint256 pid)
        external
        view
        returns (address lpToken, address depositToken, address gauge, address rewardPool, address stash, bool shutdown);
}

interface IYearnV2Vault {
    function token() external view returns (address);
    function totalAssets() external view returns (uint256);
    function availableDepositLimit() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function deposit(uint256 amount, address recipient) external returns (uint256 shares);
}

struct PolMigrationSafeTx {
    address to;
    bytes data;
}

/// @title Generate POL Liquidity Migration Safe Transactions
/// @notice Generates and simulates the Treasury Safe batch requested in Notion under "Rebalance POL Liquidity".
/// @dev Run with:
///      forge script script/GeneratePolLiquidityMigrationTransactions.s.sol:
///      GeneratePolLiquidityMigrationTransactionsScript --rpc-url ethereum
contract GeneratePolLiquidityMigrationTransactionsScript is Script {
    address public constant TREASURY_SAFE = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;

    address public constant CURVE_LP_TOKEN = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address public constant CONVEX_REWARD_POOL = 0x0E80Fe9D6F6dF530ab2Ff69ad0259e77E2ffEdeb;
    uint256 public constant CONVEX_POOL_ID = 565;

    address public constant YEARN_VAULT = 0xB53B70Cb960FeEAf2093Df3C733E368F6D254898;
    address public constant STAKE_DAO_VAULT = 0x6ea128D83bc4223A0d1e6E475CEE85998AcB6337;

    uint256 public constant YEARN_AMOUNT = 215_246 ether;
    uint256 public constant STAKE_DAO_AMOUNT = 306_081 ether;
    uint256 public constant TOTAL_MIGRATION_AMOUNT = 521_327 ether;

    string public constant OUTPUT_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-rebalance-pol-liquidity.json";

    function run() public {
        require(block.chainid == 1, "not Ethereum mainnet");

        PolMigrationSafeTx[] memory txs = getMigrationTransactions();
        validateAndSimulateMigrationTransactions(txs);
        vm.writeFile(OUTPUT_PATH, buildSafeBatchJson(txs));

        console.log("Safe Transaction Builder JSON:", OUTPUT_PATH);
        console.log("Total Convex LP withdrawn:", TOTAL_MIGRATION_AMOUNT);
        console.log("Yearn LP deposit:", YEARN_AMOUNT);
        console.log("Stake DAO LP deposit:", STAKE_DAO_AMOUNT);
    }

    function getMigrationTransactions() public pure returns (PolMigrationSafeTx[] memory txs) {
        require(YEARN_AMOUNT + STAKE_DAO_AMOUNT == TOTAL_MIGRATION_AMOUNT, "migration split mismatch");

        txs = new PolMigrationSafeTx[](5);
        txs[0] = PolMigrationSafeTx({
            to: CONVEX_REWARD_POOL,
            data: abi.encodeCall(IConvexRewardPool.withdrawAndUnwrap, (TOTAL_MIGRATION_AMOUNT, false))
        });
        txs[1] =
            PolMigrationSafeTx({to: CURVE_LP_TOKEN, data: abi.encodeCall(IERC20.approve, (YEARN_VAULT, YEARN_AMOUNT))});
        txs[2] = PolMigrationSafeTx({
            to: YEARN_VAULT, data: abi.encodeCall(IYearnV2Vault.deposit, (YEARN_AMOUNT, TREASURY_SAFE))
        });
        txs[3] = PolMigrationSafeTx({
            to: CURVE_LP_TOKEN, data: abi.encodeCall(IERC20.approve, (STAKE_DAO_VAULT, STAKE_DAO_AMOUNT))
        });
        txs[4] = PolMigrationSafeTx({
            to: STAKE_DAO_VAULT, data: abi.encodeCall(IERC4626.deposit, (STAKE_DAO_AMOUNT, TREASURY_SAFE))
        });
    }

    function validateMainnetState() public view {
        require(block.chainid == 1, "not Ethereum mainnet");
        require(TREASURY_SAFE.code.length > 0, "Treasury Safe has no code");
        require(CURVE_LP_TOKEN.code.length > 0, "Curve LP token has no code");
        require(CONVEX_BOOSTER.code.length > 0, "Convex booster has no code");
        require(CONVEX_REWARD_POOL.code.length > 0, "Convex reward pool has no code");
        require(YEARN_VAULT.code.length > 0, "Yearn vault has no code");
        require(STAKE_DAO_VAULT.code.length > 0, "Stake DAO vault has no code");
        require(YEARN_AMOUNT + STAKE_DAO_AMOUNT == TOTAL_MIGRATION_AMOUNT, "migration split mismatch");

        IConvexRewardPool rewardPool = IConvexRewardPool(CONVEX_REWARD_POOL);
        require(rewardPool.operator() == CONVEX_BOOSTER, "Convex booster mismatch");
        require(rewardPool.pid() == CONVEX_POOL_ID, "Convex pool id mismatch");

        (address lpToken,,, address rewardPoolAddress,, bool shutdown) =
            IConvexBooster(CONVEX_BOOSTER).poolInfo(CONVEX_POOL_ID);
        require(lpToken == CURVE_LP_TOKEN, "Convex LP token mismatch");
        require(rewardPoolAddress == CONVEX_REWARD_POOL, "Convex reward pool mismatch");
        require(!shutdown, "Convex pool is shut down");
        require(rewardPool.balanceOf(TREASURY_SAFE) >= TOTAL_MIGRATION_AMOUNT, "insufficient Treasury Convex balance");

        require(IYearnV2Vault(YEARN_VAULT).token() == CURVE_LP_TOKEN, "Yearn vault token mismatch");
        require(
            IYearnV2Vault(YEARN_VAULT).availableDepositLimit() >= YEARN_AMOUNT, "insufficient Yearn deposit capacity"
        );
        require(IERC4626(STAKE_DAO_VAULT).asset() == CURVE_LP_TOKEN, "Stake DAO vault asset mismatch");
        require(
            IERC4626(STAKE_DAO_VAULT).maxDeposit(TREASURY_SAFE) >= STAKE_DAO_AMOUNT,
            "insufficient Stake DAO deposit capacity"
        );
        require(IERC4626(STAKE_DAO_VAULT).previewDeposit(STAKE_DAO_AMOUNT) > 0, "zero Stake DAO shares");
    }

    function validateAndSimulateMigrationTransactions(PolMigrationSafeTx[] memory txs) public {
        validateMainnetState();
        require(txs.length == 5, "unexpected migration transaction count");

        IConvexRewardPool rewardPool = IConvexRewardPool(CONVEX_REWARD_POOL);
        IERC20 lpToken = IERC20(CURVE_LP_TOKEN);
        IYearnV2Vault yearnVault = IYearnV2Vault(YEARN_VAULT);
        IERC4626 stakeDaoVault = IERC4626(STAKE_DAO_VAULT);

        uint256 convexBalanceBefore = rewardPool.balanceOf(TREASURY_SAFE);
        uint256 convexEarnedBefore = rewardPool.earned(TREASURY_SAFE);
        uint256 treasuryLpBefore = lpToken.balanceOf(TREASURY_SAFE);
        uint256 yearnAssetsBefore = yearnVault.totalAssets();
        uint256 yearnSharesBefore = yearnVault.balanceOf(TREASURY_SAFE);
        uint256 stakeDaoAssetsBefore = stakeDaoVault.totalAssets();
        uint256 stakeDaoSharesBefore = stakeDaoVault.balanceOf(TREASURY_SAFE);

        uint256 snapshot = vm.snapshotState();
        _simulateSafeTransactions(txs);

        require(
            rewardPool.balanceOf(TREASURY_SAFE) == convexBalanceBefore - TOTAL_MIGRATION_AMOUNT,
            "Convex withdrawal mismatch"
        );
        require(rewardPool.earned(TREASURY_SAFE) == convexEarnedBefore, "Convex rewards were claimed");
        require(lpToken.balanceOf(TREASURY_SAFE) == treasuryLpBefore, "Treasury LP residual mismatch");
        require(yearnVault.totalAssets() == yearnAssetsBefore + YEARN_AMOUNT, "Yearn asset deposit mismatch");
        require(yearnVault.balanceOf(TREASURY_SAFE) > yearnSharesBefore, "Yearn shares not received");
        require(
            stakeDaoVault.totalAssets() == stakeDaoAssetsBefore + STAKE_DAO_AMOUNT, "Stake DAO asset deposit mismatch"
        );
        require(stakeDaoVault.balanceOf(TREASURY_SAFE) > stakeDaoSharesBefore, "Stake DAO shares not received");
        require(lpToken.allowance(TREASURY_SAFE, YEARN_VAULT) == 0, "Yearn allowance not consumed");
        require(lpToken.allowance(TREASURY_SAFE, STAKE_DAO_VAULT) == 0, "Stake DAO allowance not consumed");

        require(vm.revertToState(snapshot), "failed to revert migration simulation");
    }

    function buildSafeBatchJson(PolMigrationSafeTx[] memory txs) public pure returns (string memory) {
        require(txs.length == 5, "unexpected migration transaction count");

        string memory json = string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"Rebalance POL Liquidity",',
            '"txBuilderVersion":"1.16.5"},"transactions":['
        );

        for (uint256 i = 0; i < txs.length; ++i) {
            if (i > 0) json = string.concat(json, ",");
            json = string.concat(
                json,
                '{"to":"',
                vm.toString(txs[i].to),
                '","value":"0","data":"',
                vm.toString(txs[i].data),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }

        return string.concat(json, "]}");
    }

    function _simulateSafeTransactions(PolMigrationSafeTx[] memory txs) internal {
        vm.startPrank(TREASURY_SAFE);
        for (uint256 i = 0; i < txs.length; ++i) {
            _callOrRevert(txs[i].to, txs[i].data);
        }
        vm.stopPrank();
    }

    function _callOrRevert(address target, bytes memory data) internal returns (bytes memory returnData) {
        bool success;
        (success, returnData) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }
}
