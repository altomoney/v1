// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {DUSDAdvancedPermissionsUsm} from "@alto/usm/DUSDAdvancedPermissionsUsm.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {AdvancedPermissionsFeeStrategy} from "@alto/usm/AdvancedPermissionsFeeStrategy.sol";
import {DirectionAccess, IAdvancedPermissionsUsm} from "@alto/usm/interfaces/IAdvancedPermissionsUsm.sol";
import {IAdvancedPermissionsUsmFeeStrategy} from "@alto/usm/interfaces/IAdvancedPermissionsUsmFeeStrategy.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

struct AdvancedPermissionsUsmBatchParams {
    address owner;
    address dusd;
    address usmRegistry;
    address feeRecipient;
    address freezer;
    address treasuryMultisig;
    address liquidationPeriphery;
    address underlyingAsset;
    uint256 priceRatio;
    uint256 buyFee;
    uint256 sellFee;
    uint128 exposureCap;
    uint256 mintCeiling;
    bool useUnsafeUpgrades;
    bool finalizeDusdAndRegistry;
}

struct AdvancedPermissionsUsmBatchReport {
    address dusdUsm;
    address dusdUsmImplementation;
    address fixedPriceStrategy;
    address advancedPermissionsFeeStrategy;
}

/// @notice Deploys an Advanced Permissions USM and configures liquidation periphery sell access in one transaction
contract AdvancedPermissionsUsmBatch {
    AdvancedPermissionsUsmBatchReport public report;

    constructor(AdvancedPermissionsUsmBatchParams memory _params) {
        require(_params.liquidationPeriphery != address(0), "LiquidationPeriphery not set");

        address fixedPriceStrategy =
            address(new FixedPriceStrategy(_params.priceRatio, _params.underlyingAsset, address(this)));

        address feeStrategy =
            address(new AdvancedPermissionsFeeStrategy(_params.buyFee, _params.sellFee, address(this)));

        bytes memory initData = abi.encodeCall(
            DUSDAdvancedPermissionsUsm.initialize,
            (
                address(this),
                _params.treasuryMultisig,
                _params.exposureCap,
                fixedPriceStrategy,
                DirectionAccess.PERMISSIONED,
                DirectionAccess.PERMISSIONED
            )
        );

        address dusdUsm;
        address dusdUsmImplementation;
        if (_params.useUnsafeUpgrades) {
            dusdUsmImplementation = address(new DUSDAdvancedPermissionsUsm(_params.dusd, _params.underlyingAsset));
            dusdUsm = UnsafeUpgrades.deployUUPSProxy(dusdUsmImplementation, initData);
        } else {
            Options memory opts;
            opts.constructorData = abi.encode(_params.dusd, _params.underlyingAsset);
            dusdUsm =
                Upgrades.deployUUPSProxy("DUSDAdvancedPermissionsUsm.sol:DUSDAdvancedPermissionsUsm", initData, opts);
            dusdUsmImplementation = Upgrades.getImplementationAddress(dusdUsm);
        }

        IAdvancedPermissionsUsm usm = IAdvancedPermissionsUsm(dusdUsm);
        AdvancedPermissionsFeeStrategy(feeStrategy)
            .overrideSellFee(
                _params.liquidationPeriphery,
                IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: 0})
            );

        usm.updateFeeRecipient(_params.feeRecipient);
        usm.updateFeeStrategy(feeStrategy);
        usm.grantRole(usm.SELL_SWAPPER_ROLE(), _params.liquidationPeriphery);
        usm.grantRole(usm.SWAP_FREEZER_ROLE(), _params.freezer);

        bytes32 adminRole = bytes32(0);
        bytes32 configuratorRole = usm.CONFIGURATOR_ROLE();

        IAccessControl(dusdUsm).grantRole(adminRole, _params.owner);
        IAccessControl(dusdUsm).grantRole(configuratorRole, _params.owner);
        IAccessControl(dusdUsm).revokeRole(configuratorRole, address(this));
        IAccessControl(dusdUsm).revokeRole(adminRole, address(this));

        IAccessControl(fixedPriceStrategy).grantRole(adminRole, _params.owner);
        IAccessControl(fixedPriceStrategy).grantRole(configuratorRole, _params.owner);
        IAccessControl(fixedPriceStrategy).revokeRole(configuratorRole, address(this));
        IAccessControl(fixedPriceStrategy).revokeRole(adminRole, address(this));

        IAccessControl(feeStrategy).grantRole(adminRole, _params.owner);
        IAccessControl(feeStrategy).grantRole(configuratorRole, _params.owner);
        IAccessControl(feeStrategy).revokeRole(configuratorRole, address(this));
        IAccessControl(feeStrategy).revokeRole(adminRole, address(this));

        if (_params.finalizeDusdAndRegistry) {
            IDUSD(_params.dusd).setMinterStatus(dusdUsm, true);
            IDUSD(_params.dusd).setMinterCeiling(dusdUsm, _params.mintCeiling);
            IDUSD(_params.dusd).setBurnerStatus(dusdUsm, true);
            IUsmRegistry(_params.usmRegistry).addUsm(dusdUsm);
        }

        report = AdvancedPermissionsUsmBatchReport({
            dusdUsm: dusdUsm,
            dusdUsmImplementation: dusdUsmImplementation,
            fixedPriceStrategy: fixedPriceStrategy,
            advancedPermissionsFeeStrategy: feeStrategy
        });
    }

    function getReport() external view returns (AdvancedPermissionsUsmBatchReport memory) {
        return report;
    }
}
