// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {USDC_MAINNET, FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

interface ISparkUsdsPsmWrapper {
    function buyGem(address user, uint256 gemAmount) external returns (uint256 usdsInWad);
}

interface ICurvePool {
    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount) external returns (uint256);
}

interface IBooster {
    function depositAll(uint256 pid, bool isStake) external returns (bool);
}

interface IRewardPool {
    function balanceOf(address account) external view returns (uint256);
}

struct TreasurySafeTx {
    address to;
    bytes data;
}

address constant TREASURY_MULTISIG = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
address constant DUSD_VAULT = 0x6954785783c6EE90400fA715E591fBbA0D0Bd749;
address constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
address constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
address constant SPARK_USDS_PSM = 0xA188EEC8F81263234dA3622A406892F3D630f98c;
address constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;
address constant PERMISSIONED_FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
address constant FRXUSD_DUSD_CURVE_POOL = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
address constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

uint256 constant TREASURY_SAFE_TX_COUNT = 12;
uint256 constant DUSD_WITHDRAW_AMOUNT = 100_000 ether;
uint256 constant USDS_WITHDRAW_AMOUNT = 500_000 ether;
uint256 constant USDC_BUY_AMOUNT = 500_000 * 1e6;
uint256 constant USDC_FRXUSD_SWAP_AMOUNT = 500_000 * 1e6;
uint256 constant FRXUSD_SELL_AMOUNT = 200_000 ether;
uint256 constant CURVE_LIQUIDITY_AMOUNT = 300_000 ether;
uint256 constant CURVE_MIN_MINT_AMOUNT = 599_900 ether;
uint256 constant BOOSTER_POOL_ID = 565;

string constant SAFE_TX_OUTPUT_PATH = "contracts/deployments/ethereum-mainnet/output/safe-tx-treasury-migration.json";

/// @title Generate Treasury Safe Transaction Data
/// @notice Generates transaction data for treasury multisig Safe wallet bulk execution
/// @dev Run with `forge script script/GenerateTreasurySafeTransactions.s.sol:GenerateTreasurySafeTransactionsScript --rpc-url <RPC_URL> -vvvv`
contract GenerateTreasurySafeTransactionsScript is Script {
    function run() public {
        TreasurySafeTx[] memory txs = getSafeTransactions();

        console.log("=== Treasury Safe Transaction Generator ===");
        console.log("Treasury Multisig:", TREASURY_MULTISIG);
        console.log("Transaction count:", TREASURY_SAFE_TX_COUNT);
        console.log("Safe JSON output:", SAFE_TX_OUTPUT_PATH);

        console.log("\n=== TRANSACTION DATA FOR SAFE WALLET ===");
        _logSafeTransaction(txs, 0, "Transaction 1: Withdraw 100,000 DUSD from DUSD Vault");
        _logSafeTransaction(txs, 1, "Transaction 2: Withdraw 500,000 USDS from sUSDS");
        _logSafeTransaction(txs, 2, "Transaction 3: Approve USDS for Spark PSM");
        _logSafeTransaction(txs, 3, "Transaction 4: Buy 500,000 USDC with USDS via Spark PSM");
        _logSafeTransaction(txs, 4, "Transaction 5: Approve USDC for Frax Custodian");
        _logSafeTransaction(txs, 5, "Transaction 6: Deposit 500,000 USDC for frxUSD via Frax Custodian");
        _logSafeTransaction(txs, 6, "Transaction 7: Approve frxUSD for Permissioned frxUSD USM");
        _logSafeTransaction(txs, 7, "Transaction 8: Sell 200,000 frxUSD for DUSD via Permissioned frxUSD USM");
        _logSafeTransaction(txs, 8, "Transaction 9: Approve DUSD for frxUSD/DUSD Curve Pool");
        _logSafeTransaction(txs, 9, "Transaction 10: Approve frxUSD for frxUSD/DUSD Curve Pool");
        _logSafeTransaction(txs, 10, "Transaction 11: Add 300,000 DUSD and 300,000 frxUSD to Curve Pool");
        _logSafeTransaction(txs, 11, "Transaction 12: Deposit all Curve LP to Booster (stake)");

        string memory safeJson = _buildSafeBatchJson("Treasury Migration", txs);
        vm.writeFile(SAFE_TX_OUTPUT_PATH, safeJson);
        console.log("\nSafe Transaction Builder JSON written to:", SAFE_TX_OUTPUT_PATH);
    }

    function getSafeTransactions() public pure returns (TreasurySafeTx[] memory txs) {
        txs = new TreasurySafeTx[](TREASURY_SAFE_TX_COUNT);

        txs[0] = TreasurySafeTx({
            to: DUSD_VAULT,
            data: abi.encodeWithSelector(
                IERC4626.withdraw.selector, DUSD_WITHDRAW_AMOUNT, TREASURY_MULTISIG, TREASURY_MULTISIG
            )
        });

        txs[1] = TreasurySafeTx({
            to: SUSDS,
            data: abi.encodeWithSelector(
                IERC4626.withdraw.selector, USDS_WITHDRAW_AMOUNT, TREASURY_MULTISIG, TREASURY_MULTISIG
            )
        });

        txs[2] = TreasurySafeTx({
            to: USDS, data: abi.encodeWithSelector(IERC20.approve.selector, SPARK_USDS_PSM, USDS_WITHDRAW_AMOUNT)
        });

        txs[3] = TreasurySafeTx({
            to: SPARK_USDS_PSM,
            data: abi.encodeWithSelector(ISparkUsdsPsmWrapper.buyGem.selector, TREASURY_MULTISIG, USDC_BUY_AMOUNT)
        });

        txs[4] = TreasurySafeTx({
            to: USDC_MAINNET,
            data: abi.encodeWithSelector(IERC20.approve.selector, FRAX_CUSTODIAN, USDC_FRXUSD_SWAP_AMOUNT)
        });

        txs[5] = TreasurySafeTx({
            to: FRAX_CUSTODIAN,
            data: abi.encodeWithSelector(IERC4626.deposit.selector, USDC_FRXUSD_SWAP_AMOUNT, TREASURY_MULTISIG)
        });

        txs[6] = TreasurySafeTx({
            to: FRXUSD_MAINNET,
            data: abi.encodeWithSelector(IERC20.approve.selector, PERMISSIONED_FRXUSD_USM, FRXUSD_SELL_AMOUNT)
        });

        txs[7] = TreasurySafeTx({
            to: PERMISSIONED_FRXUSD_USM,
            data: abi.encodeWithSelector(IUsm.sellAsset.selector, FRXUSD_SELL_AMOUNT, TREASURY_MULTISIG)
        });

        txs[8] = TreasurySafeTx({
            to: DUSD,
            data: abi.encodeWithSelector(IERC20.approve.selector, FRXUSD_DUSD_CURVE_POOL, CURVE_LIQUIDITY_AMOUNT)
        });

        txs[9] = TreasurySafeTx({
            to: FRXUSD_MAINNET,
            data: abi.encodeWithSelector(IERC20.approve.selector, FRXUSD_DUSD_CURVE_POOL, CURVE_LIQUIDITY_AMOUNT)
        });

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = CURVE_LIQUIDITY_AMOUNT;
        amounts[1] = CURVE_LIQUIDITY_AMOUNT;

        txs[10] = TreasurySafeTx({
            to: FRXUSD_DUSD_CURVE_POOL,
            data: abi.encodeWithSelector(ICurvePool.add_liquidity.selector, amounts, CURVE_MIN_MINT_AMOUNT)
        });

        txs[11] = TreasurySafeTx({
            to: BOOSTER, data: abi.encodeWithSelector(IBooster.depositAll.selector, BOOSTER_POOL_ID, true)
        });
    }

    function _logSafeTransaction(TreasurySafeTx[] memory txs, uint256 index, string memory title) internal pure {
        console.log("\n---", title, "---");
        console.log("To:", txs[index].to);
        console.log("Value: 0");
        console.logBytes(txs[index].data);
    }

    function _buildSafeBatchJson(string memory name, TreasurySafeTx[] memory txs)
        internal
        pure
        returns (string memory)
    {
        string memory json = string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"', name, '","txBuilderVersion":"1.16.5"},"transactions":['
        );

        for (uint256 i = 0; i < txs.length; ++i) {
            if (i > 0) {
                json = string.concat(json, ",");
            }
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
}
