// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {USDC_MAINNET, FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

struct TreasurySafeTx {
    address to;
    bytes data;
}

struct ZeroExposureParams {
    uint256 frxUsdExposure;
    uint256 dusdNeeded;
    uint256 frxUsdSellAmount;
    uint256 usdcNeeded;
}

/// @title Treasury Zero Permissionless frxUSD USM Exposure
/// @notice Generates Safe txs for treasury multisig to unwind permissionless frxUSD USM exposure to zero
/// @dev Run with `forge script script/TreasuryZeroPermissionlessFrxUsdUsmExposure.s.sol:TreasuryZeroPermissionlessFrxUsdUsmExposureScript --rpc-url ethereum -vvvv`
contract TreasuryZeroPermissionlessFrxUsdUsmExposureScript is Script {
    address constant TREASURY_MULTISIG = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant PERMISSIONLESS_FRXUSD_USM = 0x7b9468fB9f3146ec82ceB2Dd75e6a47F3EAd5f79;
    address constant PERMISSIONED_FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;

    string constant SAFE_BATCH_NAME = "zero-permissionless-frxusd-usm-exposure";
    string constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function run() public {
        ZeroExposureParams memory params = computeParams();
        TreasurySafeTx[] memory txs = getSafeTransactions(params);

        console.log("=== Zero Permissionless frxUSD USM Exposure ===");
        console.log("Treasury Multisig:", TREASURY_MULTISIG);
        console.log("Permissionless frxUSD USM:", PERMISSIONLESS_FRXUSD_USM);
        console.log("Permissioned frxUSD USM:", PERMISSIONED_FRXUSD_USM);
        console.log("Frax Custodian:", FRAX_CUSTODIAN);
        console.log("frxUSD exposure to unwind:", params.frxUsdExposure);
        console.log("DUSD needed (incl. fees):", params.dusdNeeded);
        console.log("frxUSD to mint and sell:", params.frxUsdSellAmount);
        console.log("USDC needed:", params.usdcNeeded);

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", SAFE_BATCH_NAME, ".json"),
            _buildSafeBatchJson(SAFE_BATCH_NAME, txs)
        );

        console.log("\nSafe TX Builder JSON written:");
        console.log("  safe-tx-%s.json", SAFE_BATCH_NAME);
    }

    /// @dev Quotes the amounts required to bring permissionless frxUSD USM exposure to zero.
    /// frxUsdExposure is the frxUSD liquidity currently held by the USM.
    /// dusdNeeded is queried via getStableTokenAmountForBuyAsset and includes buy fees.
    /// frxUsdSellAmount equals dusdNeeded because permissioned USM has no fees (1:1).
    /// usdcNeeded equals dusdNeeded at 1:1 via Frax Custodian (USDC 6 decimals, DUSD/frxUSD 18 decimals).
    function computeParams() public view returns (ZeroExposureParams memory params) {
        params.frxUsdExposure = IUsm(PERMISSIONLESS_FRXUSD_USM).getAvailableLiquidity();
        require(params.frxUsdExposure > 0, "exposure already zero");

        (, params.dusdNeeded,,) =
            IUsm(PERMISSIONLESS_FRXUSD_USM).getStableTokenAmountForBuyAsset(params.frxUsdExposure);

        params.frxUsdSellAmount = params.dusdNeeded;
        params.usdcNeeded = (params.dusdNeeded + 1e12 - 1) / 1e12;
    }

    function getSafeTransactions(ZeroExposureParams memory params)
        public
        pure
        returns (TreasurySafeTx[] memory txs)
    {
        txs = new TreasurySafeTx[](6);

        txs[0] = TreasurySafeTx({
            to: USDC_MAINNET,
            data: abi.encodeWithSelector(IERC20.approve.selector, FRAX_CUSTODIAN, params.usdcNeeded)
        });

        txs[1] = TreasurySafeTx({
            to: FRAX_CUSTODIAN,
            data: abi.encodeWithSelector(IERC4626.mint.selector, params.frxUsdSellAmount, TREASURY_MULTISIG)
        });

        txs[2] = TreasurySafeTx({
            to: FRXUSD_MAINNET,
            data: abi.encodeWithSelector(IERC20.approve.selector, PERMISSIONED_FRXUSD_USM, params.frxUsdSellAmount)
        });

        txs[3] = TreasurySafeTx({
            to: PERMISSIONED_FRXUSD_USM,
            data: abi.encodeWithSelector(IUsm.sellAsset.selector, params.frxUsdSellAmount, TREASURY_MULTISIG)
        });

        txs[4] = TreasurySafeTx({
            to: DUSD,
            data: abi.encodeWithSelector(IERC20.approve.selector, PERMISSIONLESS_FRXUSD_USM, params.dusdNeeded)
        });

        txs[5] = TreasurySafeTx({
            to: PERMISSIONLESS_FRXUSD_USM,
            data: abi.encodeWithSelector(IUsm.buyAsset.selector, params.frxUsdExposure, TREASURY_MULTISIG)
        });
    }

    function _buildSafeBatchJson(string memory name, TreasurySafeTx[] memory txs)
        internal
        pure
        returns (string memory)
    {
        string memory json = string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"',
            name,
            '","txBuilderVersion":"1.16.5"},"transactions":['
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
