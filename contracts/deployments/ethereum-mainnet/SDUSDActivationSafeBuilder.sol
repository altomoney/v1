// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IAltoVaultBase} from "@alto/lending/interfaces/IAltoVault.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {EmergencyController} from "@alto/utils/EmergencyController.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IAltoMintMarketFees} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {IStableTokenFacilitator} from "@alto/usm/interfaces/IStableTokenFacilitator.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";
import {IVaultRegistry} from "@alto/utils/interfaces/IVaultRegistry.sol";
import {AltoEthereumMainnetInput} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";
import {SafeTransactionBuilder} from "@alto/deployments/ethereum-mainnet/SafeTransactionBuilder.sol";

struct SDUSDActivationSafeBatch {
    address[] targets;
    uint256[] values;
    bytes[] payloads;
}

/// @notice Builds and writes the timelock Safe transactions used to activate sDUSD fee collection.
/// @dev The caller must validate deployment and source state before invoking this library.
library SDUSDActivationSafeBuilder {
    string private constant SAFE_BATCH_NAME = "sdusd-activation";

    function write(AltoEthereumMainnetInput memory input) internal {
        SDUSDActivationSafeBatch memory activationBatch = buildActivationBatch(input);
        SafeTransactionBuilder.writeTimelockBatch(
            SAFE_BATCH_NAME,
            input.contracts.timelock,
            activationBatch.targets,
            activationBatch.values,
            activationBatch.payloads,
            TimelockController(payable(input.contracts.timelock)).getMinDelay()
        );
    }

    function buildActivationBatch(AltoEthereumMainnetInput memory input)
        internal
        view
        returns (SDUSDActivationSafeBatch memory batch)
    {
        _validateEmergencyControls(input);
        address[] memory borrowMarkets = IMarketRegistry(input.contracts.marketRegistry).getBorrowMarkets();
        address[] memory mintMarkets = IMarketRegistry(input.contracts.marketRegistry).getMintMarkets();
        address[] memory usms = IUsmRegistry(input.contracts.usmRegistry).getUsmList();
        address[] memory vaults = IVaultRegistry(input.contracts.vaultRegistry).getVaultList();

        uint256 dusdVaults;
        for (uint256 i; i < vaults.length; ++i) {
            if (IERC4626(vaults[i]).asset() == input.contracts.dusd) ++dusdVaults;
        }

        // Only fee-bearing USMs need activation calls. The registered zero-recipient USMs are permissioned and
        // configured without fees, so their recipient remains unset.
        uint256 usmsWithFeeRecipient;
        for (uint256 i; i < usms.length; ++i) {
            if (IStableTokenFacilitator(usms[i]).getFeeRecipient() != address(0)) ++usmsWithFeeRecipient;
        }

        // Activation timelock calls:
        //   2                              EmergencyController whitelist for sDUSD and the collector
        // + 1                              ProtocolFeeCollector.setSdusdVault
        // + dusdVaults                     setFeeRecipient for each registered DUSD vault (accrues fees internally)
        // + 2 * borrowMarkets.length       accrueInterest + setFeeRecipient for each borrow market
        // + 3 * mintMarkets.length         accrueInterest + claimInterest + setFeeRecipient for each mint market
        // + 2 * usmsWithFeeRecipient       distributeFeesToFeeRecipient + updateFeeRecipient for fee-bearing USMs
        // + 2                              distributeFeesToFeeRecipient + updateFeeRecipient for the flash minter
        uint256 callCount =
            3 + dusdVaults + borrowMarkets.length * 2 + mintMarkets.length * 3 + usmsWithFeeRecipient * 2 + 2;
        batch.targets = new address[](callCount);
        batch.values = new uint256[](callCount);
        batch.payloads = new bytes[](callCount);

        uint256 index;
        index = _appendEmergencyControllerConfiguration(input, batch, index);
        index = _appendCollectorVaultConfiguration(input, batch, index);
        index = _appendVaultFeeRecipientUpdates(input, batch, index);
        index = _appendBorrowMarketFeeAccrualAndRecipientUpdates(input, batch, index);
        index = _appendMintMarketFeeSettlementAndRecipientUpdates(input, batch, index);
        index = _appendUsmFeeSettlementAndRecipientUpdates(input, batch, index);
        index = _appendFlashMinterFeeSettlementAndRecipientUpdate(input, batch, index);
        assert(index == callCount);
    }

    function _validateEmergencyControls(AltoEthereumMainnetInput memory input) private view {
        EmergencyController controller = EmergencyController(input.contracts.emergencyController);
        require(controller.owner() == input.contracts.timelock, "Unexpected emergency controller owner");
        address pauserSafe = address(controller.pauserSafe());
        SDUSD vault = SDUSD(input.contracts.sdusd);
        ProtocolFeeCollector collector = ProtocolFeeCollector(input.contracts.protocolFeeCollector);
        require(
            vault.pausers(pauserSafe, PAUSE_TYPE) && vault.pausers(pauserSafe, FROZEN_TYPE)
                && collector.pausers(pauserSafe, PAUSE_TYPE),
            "Missing Pauser Safe permissions"
        );
        require(
            vault.pausers(address(controller), PAUSE_TYPE) && vault.pausers(address(controller), FROZEN_TYPE)
                && collector.pausers(address(controller), PAUSE_TYPE),
            "Missing emergency controller permissions"
        );
    }

    function _appendEmergencyControllerConfiguration(
        AltoEthereumMainnetInput memory input,
        SDUSDActivationSafeBatch memory batch,
        uint256 index
    ) private pure returns (uint256) {
        address controller = input.contracts.emergencyController;
        _append(
            batch,
            index++,
            controller,
            abi.encodeCall(EmergencyController.setContractWhitelist, (input.contracts.sdusd, true))
        );
        _append(
            batch,
            index++,
            controller,
            abi.encodeCall(EmergencyController.setContractWhitelist, (input.contracts.protocolFeeCollector, true))
        );
        return index;
    }

    function _appendCollectorVaultConfiguration(
        AltoEthereumMainnetInput memory input,
        SDUSDActivationSafeBatch memory batch,
        uint256 index
    ) private pure returns (uint256) {
        _append(
            batch,
            index++,
            input.contracts.protocolFeeCollector,
            abi.encodeCall(ProtocolFeeCollector.setSdusdVault, (input.contracts.sdusd))
        );
        return index;
    }

    function _appendVaultFeeRecipientUpdates(
        AltoEthereumMainnetInput memory input,
        SDUSDActivationSafeBatch memory batch,
        uint256 index
    ) private view returns (uint256) {
        address[] memory vaults = IVaultRegistry(input.contracts.vaultRegistry).getVaultList();
        for (uint256 i; i < vaults.length; ++i) {
            if (IERC4626(vaults[i]).asset() != input.contracts.dusd) continue;

            _append(
                batch,
                index++,
                vaults[i],
                abi.encodeCall(IAltoVaultBase.setFeeRecipient, (input.contracts.protocolFeeCollector))
            );
        }
        return index;
    }

    function _appendBorrowMarketFeeAccrualAndRecipientUpdates(
        AltoEthereumMainnetInput memory input,
        SDUSDActivationSafeBatch memory batch,
        uint256 index
    ) private view returns (uint256) {
        address[] memory markets = IMarketRegistry(input.contracts.marketRegistry).getBorrowMarkets();
        for (uint256 i; i < markets.length; ++i) {
            _append(batch, index++, markets[i], abi.encodeCall(IMarketBase.accrueInterest, ()));
            _append(
                batch,
                index++,
                markets[i],
                abi.encodeCall(IMarketBase.setFeeRecipient, (input.contracts.protocolFeeCollector))
            );
        }
        return index;
    }

    function _appendMintMarketFeeSettlementAndRecipientUpdates(
        AltoEthereumMainnetInput memory input,
        SDUSDActivationSafeBatch memory batch,
        uint256 index
    ) private view returns (uint256) {
        address[] memory markets = IMarketRegistry(input.contracts.marketRegistry).getMintMarkets();
        for (uint256 i; i < markets.length; ++i) {
            _append(batch, index++, markets[i], abi.encodeCall(IMarketBase.accrueInterest, ()));
            _append(batch, index++, markets[i], abi.encodeCall(IAltoMintMarketFees.claimInterest, (0)));
            _append(
                batch,
                index++,
                markets[i],
                abi.encodeCall(IMarketBase.setFeeRecipient, (input.contracts.protocolFeeCollector))
            );
        }
        return index;
    }

    function _appendUsmFeeSettlementAndRecipientUpdates(
        AltoEthereumMainnetInput memory input,
        SDUSDActivationSafeBatch memory batch,
        uint256 index
    ) private view returns (uint256) {
        address[] memory usms = IUsmRegistry(input.contracts.usmRegistry).getUsmList();
        for (uint256 i; i < usms.length; ++i) {
            if (IStableTokenFacilitator(usms[i]).getFeeRecipient() == address(0)) continue;
            _append(batch, index++, usms[i], abi.encodeCall(IStableTokenFacilitator.distributeFeesToFeeRecipient, ()));
            _append(
                batch,
                index++,
                usms[i],
                abi.encodeCall(IStableTokenFacilitator.updateFeeRecipient, (input.contracts.protocolFeeCollector))
            );
        }
        return index;
    }

    function _appendFlashMinterFeeSettlementAndRecipientUpdate(
        AltoEthereumMainnetInput memory input,
        SDUSDActivationSafeBatch memory batch,
        uint256 index
    ) private pure returns (uint256) {
        _append(
            batch,
            index++,
            input.contracts.dusdFlashMinter,
            abi.encodeCall(IStableTokenFacilitator.distributeFeesToFeeRecipient, ())
        );
        _append(
            batch,
            index++,
            input.contracts.dusdFlashMinter,
            abi.encodeCall(IStableTokenFacilitator.updateFeeRecipient, (input.contracts.protocolFeeCollector))
        );
        return index;
    }

    function _append(SDUSDActivationSafeBatch memory batch, uint256 index, address target, bytes memory payload)
        private
        pure
    {
        batch.targets[index] = target;
        batch.payloads[index] = payload;
    }
}
