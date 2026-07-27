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
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

struct AdvancedPermissionsUsmBatchOverriddenFee {
    address account;
    IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData fee;
    bool isSell;
}

struct AdvancedPermissionsUsmBatchOverriddenRole {
    address account;
    bytes32 feeRole;
    bool isSell;
}

struct AdvancedPermissionsUsmBatchFeeByRoleHash {
    bytes32 roleHash;
    IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData fee;
    bool isSell;
}

struct AdvancedPermissionsUsmBatchParams {
    address owner;
    address dusd;
    address usmRegistry;
    address feeRecipient;
    address freezer;
    address treasuryMultisig;
    address underlyingAsset;
    uint256 priceRatio;
    uint256 buyFee;
    uint256 sellFee;
    uint128 exposureCap;
    uint256 mintCeiling;
    DirectionAccess buyAccess;
    DirectionAccess sellAccess;
    bool finalizeDusdAndRegistry;
    address[] sellSwappers;
    address[] buySwappers;
    AdvancedPermissionsUsmBatchOverriddenFee[] overriddenFees;
    AdvancedPermissionsUsmBatchOverriddenRole[] overriddenRoles;
    AdvancedPermissionsUsmBatchFeeByRoleHash[] feesByRoleHash;
}

struct AdvancedPermissionsUsmBatchReport {
    address dusdUsm;
    address dusdUsmImplementation;
    address fixedPriceStrategy;
    address advancedPermissionsFeeStrategy;
}

/// @notice Deploys an Advanced Permissions USM with configurable fee overrides and USM role grants in one transaction
/// @dev Upgrade safety must be validated by the calling deployment script before broadcasting.
contract AdvancedPermissionsUsmBatch {
    AdvancedPermissionsUsmBatchReport public report;

    constructor(AdvancedPermissionsUsmBatchParams memory _params) {
        address fixedPriceStrategy =
            address(new FixedPriceStrategy(_params.priceRatio, _params.underlyingAsset, _params.owner));

        AdvancedPermissionsFeeStrategy feeStrategy =
            new AdvancedPermissionsFeeStrategy(uint16(_params.buyFee), uint16(_params.sellFee), address(this));

        bytes memory initData = abi.encodeCall(
            DUSDAdvancedPermissionsUsm.initialize,
            (
                address(this),
                _params.treasuryMultisig,
                _params.exposureCap,
                fixedPriceStrategy,
                _params.buyAccess,
                _params.sellAccess
            )
        );

        address dusdUsmImplementation = address(new DUSDAdvancedPermissionsUsm(_params.dusd, _params.underlyingAsset));
        address dusdUsm = UnsafeUpgrades.deployUUPSProxy(dusdUsmImplementation, initData);

        IAdvancedPermissionsUsm usm = IAdvancedPermissionsUsm(dusdUsm);

        for (uint256 i; i < _params.overriddenFees.length; ++i) {
            AdvancedPermissionsUsmBatchOverriddenFee memory overriddenFee = _params.overriddenFees[i];
            if (overriddenFee.isSell) {
                feeStrategy.overrideSellFee(overriddenFee.account, overriddenFee.fee);
            } else {
                feeStrategy.overrideBuyFee(overriddenFee.account, overriddenFee.fee);
            }
        }

        for (uint256 i; i < _params.overriddenRoles.length; ++i) {
            AdvancedPermissionsUsmBatchOverriddenRole memory overriddenRole = _params.overriddenRoles[i];
            if (overriddenRole.isSell) {
                feeStrategy.setUserSellFeeRole(overriddenRole.account, overriddenRole.feeRole);
            } else {
                feeStrategy.setUserBuyFeeRole(overriddenRole.account, overriddenRole.feeRole);
            }
        }

        for (uint256 i; i < _params.feesByRoleHash.length; ++i) {
            AdvancedPermissionsUsmBatchFeeByRoleHash memory feeByRoleHash = _params.feesByRoleHash[i];
            if (feeByRoleHash.isSell) {
                feeStrategy.setSellFeeByRoleHash(feeByRoleHash.roleHash, feeByRoleHash.fee);
            } else {
                feeStrategy.setBuyFeeByRoleHash(feeByRoleHash.roleHash, feeByRoleHash.fee);
            }
        }

        for (uint256 i; i < _params.sellSwappers.length; ++i) {
            address swapper = _params.sellSwappers[i];
            require(swapper != address(0), "Invalid sell swapper");
            usm.grantRole(usm.SELL_SWAPPER_ROLE(), swapper);
        }

        for (uint256 i; i < _params.buySwappers.length; ++i) {
            address swapper = _params.buySwappers[i];
            require(swapper != address(0), "Invalid buy swapper");
            usm.grantRole(usm.BUY_SWAPPER_ROLE(), swapper);
        }

        usm.updateFeeRecipient(_params.feeRecipient);
        usm.updateFeeStrategy(address(feeStrategy));
        usm.grantRole(usm.SWAP_FREEZER_ROLE(), _params.freezer);

        _transferUsmRoles(dusdUsm, _params.owner);
        _transferFeeStrategyRoles(address(feeStrategy), _params.owner);

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
            advancedPermissionsFeeStrategy: address(feeStrategy)
        });
    }

    function _transferUsmRoles(address usm, address owner) internal {
        bytes32 adminRole = bytes32(0);
        bytes32 configuratorRole = IAdvancedPermissionsUsm(usm).CONFIGURATOR_ROLE();

        IAccessControl(usm).grantRole(adminRole, owner);
        IAccessControl(usm).grantRole(configuratorRole, owner);
        IAccessControl(usm).revokeRole(configuratorRole, address(this));
        IAccessControl(usm).revokeRole(adminRole, address(this));
    }

    function _transferFeeStrategyRoles(address feeStrategy, address owner) internal {
        bytes32 adminRole = bytes32(0);
        bytes32 configuratorRole = AdvancedPermissionsFeeStrategy(feeStrategy).CONFIGURATOR_ROLE();

        IAccessControl(feeStrategy).grantRole(adminRole, owner);
        IAccessControl(feeStrategy).grantRole(configuratorRole, owner);
        IAccessControl(feeStrategy).revokeRole(configuratorRole, address(this));
        IAccessControl(feeStrategy).revokeRole(adminRole, address(this));
    }

    function getReport() external view returns (AdvancedPermissionsUsmBatchReport memory) {
        return report;
    }
}
