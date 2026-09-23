// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";

struct VaultFeeRedemptionSafeBatch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

struct VaultFeeRedemptionReport {
    address vault;
    uint256 remainingShares;
}

/// @title Generate legacy AltoVault fee-share redemption transactions
/// @notice Generates timelock calldata that redeems the maximum currently available legacy fee shares.
/// @dev IMPORTANT: Run this script only after every registered DUSD vault's fee recipient has been updated away from
///      the legacy fee recipient. Liquidity can change before execution, so regenerate the calldata immediately before
///      scheduling it. Reported residual shares are generation-time projections.
/// @dev Run with:
///      `forge script script/GenerateSDUSDVaultFeeRedemption.s.sol --rpc-url $MAINNET_RPC_URL`
contract GenerateSDUSDVaultFeeRedemptionScript is Script {
    uint256 internal constant SDUSD_DEPLOYMENT_ID_TO_LOAD = 1765364975;

    address internal constant OLD_FEE_RECIPIENT = 0xb9F06fEFc4c53dEd77A90Cb798eD08DC068Bb6dd;

    string internal constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
    string internal constant SAFE_BATCH_NAME = "sdusd-vault-fee-redemption";
    string internal constant REPORT_PATH =
        "contracts/deployments/ethereum-mainnet/output/sdusd-vault-fee-redemption-report.json";

    function run() public {
        require(block.chainid == 1, "Not Ethereum mainnet");

        string memory json = vm.readFile(
            string.concat(
                OUTPUT_DIR,
                "/ethereum-mainnet-",
                vm.toString(block.chainid),
                "-",
                vm.toString(SDUSD_DEPLOYMENT_ID_TO_LOAD),
                "/addresses.json"
            )
        );

        generate(vm.parseJsonAddress(json, ".contracts.vaultRegistry"), vm.parseJsonAddress(json, ".contracts.dusd"));
    }

    function generate(address vaultRegistry, address dusd) public {
        require(vaultRegistry != address(0), "Invalid vault registry");
        require(dusd != address(0), "Invalid DUSD");

        (VaultFeeRedemptionSafeBatch memory batch, VaultFeeRedemptionReport[] memory report) =
            buildVaultFeeRedemption(vaultRegistry, dusd);

        _writeReport(report);

        if (batch.targets.length == 0) {
            console.log("No redeemable legacy AltoVault fee shares");
            return;
        }

        SafeTransactionBuilder.writeTimelockBatch(
            SAFE_BATCH_NAME,
            OLD_FEE_RECIPIENT,
            batch.targets,
            batch.values,
            batch.payloads,
            TimelockController(payable(OLD_FEE_RECIPIENT)).getMinDelay()
        );
    }

    /// @notice Builds maximum-redemption calls and reports projected residual shares for registered DUSD vaults.
    /// @dev Reverts unless every eligible vault has migrated away from `OLD_FEE_RECIPIENT`.
    function buildVaultFeeRedemption(address vaultRegistry, address dusd)
        public
        view
        returns (VaultFeeRedemptionSafeBatch memory batch, VaultFeeRedemptionReport[] memory report)
    {
        address[] memory vaults = IVaultRegistry(vaultRegistry).getVaultList();
        uint256[] memory redeemableShares = new uint256[](vaults.length);
        uint256[] memory remainingShares = new uint256[](vaults.length);
        uint256 redemptionCount;
        uint256 residualCount;

        for (uint256 i; i < vaults.length; ++i) {
            IERC4626 vault = IERC4626(vaults[i]);
            if (vault.asset() != dusd) continue;

            require(
                IAltoVaultBase(vaults[i]).feeRecipient() != OLD_FEE_RECIPIENT, "Legacy fee recipient still configured"
            );

            uint256 legacyShares = vault.balanceOf(OLD_FEE_RECIPIENT);
            if (legacyShares == 0) continue;

            uint256 maximumRedeem = vault.maxRedeem(OLD_FEE_RECIPIENT);
            require(maximumRedeem <= legacyShares, "Invalid max redeem");

            redeemableShares[i] = maximumRedeem;
            remainingShares[i] = legacyShares - maximumRedeem;
            if (maximumRedeem != 0) ++redemptionCount;
            if (remainingShares[i] != 0) ++residualCount;
        }

        batch.targets = new address[](redemptionCount);
        batch.values = new uint256[](redemptionCount);
        batch.payloads = new bytes[](redemptionCount);
        report = new VaultFeeRedemptionReport[](residualCount);

        uint256 batchIndex;
        uint256 reportIndex;
        for (uint256 i; i < vaults.length; ++i) {
            if (redeemableShares[i] != 0) {
                batch.targets[batchIndex] = vaults[i];
                batch.payloads[batchIndex] =
                    abi.encodeCall(IERC4626.redeem, (redeemableShares[i], OLD_FEE_RECIPIENT, OLD_FEE_RECIPIENT));
                ++batchIndex;
            }

            if (remainingShares[i] != 0) {
                report[reportIndex++] =
                    VaultFeeRedemptionReport({vault: vaults[i], remainingShares: remainingShares[i]});
            }
        }

        assert(batchIndex == redemptionCount);
        assert(reportIndex == residualCount);
    }

    function _writeReport(VaultFeeRedemptionReport[] memory report) private {
        if (report.length == 0) {
            if (vm.exists(REPORT_PATH)) vm.removeFile(REPORT_PATH);
            console.log("No residual legacy AltoVault fee shares");
            return;
        }

        string memory rows;
        console.log("Legacy AltoVault fee-share residual report (generation-time projection):");
        for (uint256 i; i < report.length; ++i) {
            console.log("Vault:", report[i].vault);
            console.log("  Projected remaining shares:", report[i].remainingShares);

            rows = string.concat(
                rows,
                i == 0 ? "" : ",",
                '{"vault":"',
                vm.toString(report[i].vault),
                '","remainingShares":"',
                vm.toString(report[i].remainingShares),
                '"}'
            );
        }

        vm.writeFile(
            REPORT_PATH, string.concat('{"projectionBlock":"', vm.toString(block.number), '","vaults":[', rows, "]}")
        );
        console.log("Residual report written:", REPORT_PATH);
    }
}
