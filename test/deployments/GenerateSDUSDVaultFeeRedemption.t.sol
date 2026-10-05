// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {GenerateSDUSDVaultFeeRedemptionScript} from "../../script/GenerateSDUSDVaultFeeRedemption.s.sol";
import {IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

struct DecodedVaultFeeRedemptionBatch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
    bytes32 predecessor;
    bytes32 salt;
}

contract GenerateSDUSDVaultFeeRedemptionForkTest is Test {
    uint256 internal constant SDUSD_DEPLOYMENT_ID_TO_LOAD = 1765364975;

    string internal constant OUTPUT_DIR = "./contracts/deployments/ethereum-mainnet/output";
    string internal constant SCHEDULE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-vault-fee-redemption-schedule.json";
    string internal constant EXECUTE_PATH =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-sdusd-vault-fee-redemption-execute.json";
    string internal constant REPORT_PATH =
        "contracts/deployments/ethereum-mainnet/output/sdusd-vault-fee-redemption-report.json";

    address internal vaultRegistry;
    address internal dusd;
    address internal legacyFeeRecipient;
    address internal dummyFeeRecipient;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));
        _deleteGeneratedFiles();

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
        vaultRegistry = vm.parseJsonAddress(json, ".contracts.vaultRegistry");
        dusd = vm.parseJsonAddress(json, ".contracts.dusd");
        legacyFeeRecipient = vm.parseJsonAddress(json, ".contracts.legacyFeeRecipient");
        dummyFeeRecipient = makeAddr("dummyFeeRecipient");
    }

    function testFork_GeneratedVaultFeeRedemptionsMatchJsonAndResidualReport() public {
        address[] memory vaults = IVaultRegistry(vaultRegistry).getVaultList();
        assertGt(vaults.length, 0, "no registered vaults");

        (uint256 dusdVaultCount, uint256 legacyShares) = _migrateDusdVaultFeeRecipients(vaults);
        assertGt(dusdVaultCount, 0, "no registered DUSD vaults");
        assertGt(legacyShares, 0, "legacy recipient has no vault shares");

        GenerateSDUSDVaultFeeRedemptionScript generator = new GenerateSDUSDVaultFeeRedemptionScript();
        generator.run();

        assertTrue(vm.exists(SCHEDULE_PATH), "missing schedule file");
        assertTrue(vm.exists(EXECUTE_PATH), "missing execute file");

        DecodedVaultFeeRedemptionBatch memory batch = _readExecuteBatch();
        assertGt(batch.targets.length, 0, "no redemption calldata generated");
        assertEq(batch.targets.length, batch.values.length, "target/value length mismatch");
        assertEq(batch.targets.length, batch.payloads.length, "target/payload length mismatch");
        assertEq(batch.predecessor, bytes32(0), "unexpected predecessor");
        assertEq(batch.salt, bytes32(0), "unexpected salt");

        (uint256[] memory expectedRemainingShares, uint256 residualCount) = _assertGeneratedBatch(vaults, batch);
        _executeGeneratedVaultCalls(batch);
        _assertResidualReport(vaults, expectedRemainingShares, residualCount);

        _deleteGeneratedFiles();
    }

    function _migrateDusdVaultFeeRecipients(address[] memory vaults)
        private
        returns (uint256 dusdVaultCount, uint256 legacyShares)
    {
        for (uint256 i; i < vaults.length; ++i) {
            IERC4626 vault = IERC4626(vaults[i]);
            if (vault.asset() != dusd) continue;

            ++dusdVaultCount;
            _ensureLegacyShares(vault);

            vm.prank(Ownable(vaults[i]).owner());
            IAltoVaultBase(vaults[i]).setFeeRecipient(dummyFeeRecipient);

            assertEq(IAltoVaultBase(vaults[i]).feeRecipient(), dummyFeeRecipient, "vault fee recipient not updated");
            legacyShares += vault.balanceOf(legacyFeeRecipient);
        }
    }

    function _ensureLegacyShares(IERC4626 vault) private {
        if (vault.balanceOf(legacyFeeRecipient) != 0) return;

        uint256 assets = 1e18;
        deal(dusd, legacyFeeRecipient, IERC20(dusd).balanceOf(legacyFeeRecipient) + assets);

        vm.startPrank(legacyFeeRecipient);
        IERC20(dusd).approve(address(vault), assets);
        vault.deposit(assets, legacyFeeRecipient);
        vm.stopPrank();

        assertGt(vault.balanceOf(legacyFeeRecipient), 0, "failed to seed legacy shares");
    }

    function _assertGeneratedBatch(address[] memory vaults, DecodedVaultFeeRedemptionBatch memory batch)
        private
        view
        returns (uint256[] memory expectedRemainingShares, uint256 residualCount)
    {
        expectedRemainingShares = new uint256[](vaults.length);
        uint256 expectedCallCount;

        for (uint256 i; i < vaults.length; ++i) {
            IERC4626 vault = IERC4626(vaults[i]);
            if (vault.asset() != dusd) continue;

            assertTrue(
                IAltoVaultBase(vaults[i]).feeRecipient() != legacyFeeRecipient, "legacy fee recipient still configured"
            );

            uint256 legacyShares = vault.balanceOf(legacyFeeRecipient);
            uint256 maximumRedeem = vault.maxRedeem(legacyFeeRecipient);
            expectedRemainingShares[i] = legacyShares - maximumRedeem;
            if (expectedRemainingShares[i] != 0) ++residualCount;

            (bool included, uint256 batchIndex) = _findTarget(batch.targets, vaults[i]);
            if (maximumRedeem == 0) {
                assertFalse(included, "zero-redeem vault included");
                continue;
            }

            assertTrue(included, "redeemable vault omitted");
            assertEq(batch.values[batchIndex], 0, "unexpected call value");
            ++expectedCallCount;

            (uint256 shares, address receiver, address owner) = _decodeRedeem(batch.payloads[batchIndex]);
            assertEq(shares, maximumRedeem, "generated shares differ from maxRedeem");
            assertEq(receiver, legacyFeeRecipient, "wrong receiver");
            assertEq(owner, legacyFeeRecipient, "wrong owner");
        }

        assertEq(batch.targets.length, expectedCallCount, "unexpected generated call");
    }

    /// @dev Execute the vault payloads decoded from the generated Safe JSON immediately so maxRedeem cannot drift
    ///      during a timelock delay, then prove the legacy fee recipient received DUSD and its shares were burned.
    function _executeGeneratedVaultCalls(DecodedVaultFeeRedemptionBatch memory batch) private {
        for (uint256 i; i < batch.targets.length; ++i) {
            IERC4626 vault = IERC4626(batch.targets[i]);
            (uint256 encodedShares,,) = _decodeRedeem(batch.payloads[i]);

            uint256 sharesBefore = vault.balanceOf(legacyFeeRecipient);
            uint256 totalSupplyBefore = vault.totalSupply();
            uint256 feeRecipientDusdBefore = IERC20(dusd).balanceOf(legacyFeeRecipient);
            uint256 expectedAssets = vault.previewRedeem(encodedShares);

            vm.prank(legacyFeeRecipient);
            (bool success, bytes memory result) = batch.targets[i].call(batch.payloads[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 0x20), mload(result))
                }
            }

            uint256 redeemedAssets = abi.decode(result, (uint256));
            assertGt(redeemedAssets, 0, "fee recipient received no DUSD");
            assertEq(redeemedAssets, expectedAssets, "redeemed assets differ from preview");
            assertEq(
                vault.balanceOf(legacyFeeRecipient),
                sharesBefore - encodedShares,
                "fee recipient shares were not burned"
            );
            assertEq(
                vault.totalSupply(),
                totalSupplyBefore - encodedShares,
                "vault total supply did not burn generated shares"
            );
            assertEq(
                IERC20(dusd).balanceOf(legacyFeeRecipient),
                feeRecipientDusdBefore + expectedAssets,
                "fee recipient DUSD balance did not increase by redeemed assets"
            );
        }
    }

    function _assertResidualReport(
        address[] memory vaults,
        uint256[] memory expectedRemainingShares,
        uint256 residualCount
    ) private view {
        if (residualCount == 0) {
            assertFalse(vm.exists(REPORT_PATH), "unexpected residual report");
        } else {
            assertTrue(vm.exists(REPORT_PATH), "missing residual report");
        }

        string memory reportJson;
        if (residualCount != 0) {
            reportJson = vm.readFile(REPORT_PATH);
            assertEq(vm.parseJsonUint(reportJson, ".projectionBlock"), block.number, "wrong report block");
        }

        uint256 reportIndex;
        for (uint256 i; i < vaults.length; ++i) {
            if (IERC4626(vaults[i]).asset() != dusd) continue;

            assertEq(
                IERC4626(vaults[i]).balanceOf(legacyFeeRecipient),
                expectedRemainingShares[i],
                "actual residual shares differ from projection"
            );
            if (expectedRemainingShares[i] == 0) continue;

            string memory reportEntry = string.concat(".vaults[", vm.toString(reportIndex), "]");
            assertEq(
                vm.parseJsonAddress(reportJson, string.concat(reportEntry, ".vault")), vaults[i], "wrong report vault"
            );
            assertEq(
                vm.parseJsonUint(reportJson, string.concat(reportEntry, ".remainingShares")),
                expectedRemainingShares[i],
                "wrong reported remaining shares"
            );

            ++reportIndex;
        }

        assertEq(reportIndex, residualCount, "wrong residual row count");
        if (residualCount != 0) {
            assertFalse(
                vm.keyExistsJson(reportJson, string.concat(".vaults[", vm.toString(reportIndex), "]")),
                "unexpected residual row"
            );
        }
    }

    function _readExecuteBatch() private view returns (DecodedVaultFeeRedemptionBatch memory batch) {
        string memory json = vm.readFile(EXECUTE_PATH);
        assertEq(vm.parseJsonAddress(json, ".transactions[0].to"), legacyFeeRecipient, "wrong Safe target");

        bytes memory data = vm.parseJsonBytes(json, ".transactions[0].data");
        assertEq(bytes4(data), TimelockController.executeBatch.selector, "wrong execute selector");
        (batch.targets, batch.values, batch.payloads, batch.predecessor, batch.salt) =
            abi.decode(_removeSelector(data), (address[], uint256[], bytes[], bytes32, bytes32));
    }

    function _decodeRedeem(bytes memory payload)
        private
        pure
        returns (uint256 shares, address receiver, address owner)
    {
        assertEq(bytes4(payload), IERC4626.redeem.selector, "wrong vault selector");
        return abi.decode(_removeSelector(payload), (uint256, address, address));
    }

    function _findTarget(address[] memory targets, address vault) private pure returns (bool included, uint256 index) {
        for (uint256 i; i < targets.length; ++i) {
            if (targets[i] == vault) return (true, i);
        }
    }

    function _removeSelector(bytes memory data) private pure returns (bytes memory arguments) {
        require(data.length >= 4, "missing selector");
        arguments = new bytes(data.length - 4);
        for (uint256 i; i < arguments.length; ++i) {
            arguments[i] = data[i + 4];
        }
    }

    function _deleteGeneratedFiles() private {
        _deleteIfExists(SCHEDULE_PATH);
        _deleteIfExists(EXECUTE_PATH);
        _deleteIfExists(REPORT_PATH);
    }

    function _deleteIfExists(string memory path) private {
        if (vm.exists(path)) vm.removeFile(path);
    }
}
