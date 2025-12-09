// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "@alto/usm/FixedFeeStrategy.sol";
import {IUsm, AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {AltoAdapter} from "@alto/utils/AltoAdapter.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {AccessMode} from "@alto/usm/interfaces/IUsm.sol";

struct UsmBatchParams {
    address owner;
    address dusd;
    address altoAdapter;
    address feeRecipient;
    address freezer;
    uint256 buyFee;
    uint256 sellFee;
    uint256 exposureCap;
    address underlyingAsset;
    uint256 priceRatio;
    bool isPermissioned;
    bool useUnsafeUpgrades;
    address treasuryMultisig;
}

struct UsmBatchReport {
    address dusdUsm;
    address dusdUsmImplementation;
    address fixedPriceStrategy;
    address fixedFeeStrategy;
}

/// @notice Deploys USM components in a single transaction
contract UsmBatch {
    UsmBatchReport public report;

    constructor(UsmBatchParams memory _params) {
        // Deploy FixedPriceStrategy
        address fixedPriceStrategy =
            address(new FixedPriceStrategy(_params.priceRatio, _params.underlyingAsset, _params.owner));

        // Deploy FixedFeeStrategy
        address fixedFeeStrategy;
        AccessMode accessMode;

        if (_params.isPermissioned) {
            fixedFeeStrategy = address(0);
            accessMode = AccessMode.PERMISSIONED;
        } else {
            fixedFeeStrategy = address(new FixedFeeStrategy(_params.buyFee, _params.sellFee, _params.owner));
            accessMode = AccessMode.PERMISSIONLESS;
        }

        // Deploy DUSDUsm Proxy with constructor data
        bytes memory initData = abi.encodeCall(
            DUSDUsm.initialize,
            (
                address(this),
                _params.feeRecipient,
                uint128(_params.exposureCap),
                fixedPriceStrategy,
                accessMode,
                _params.feeRecipient
            )
        );
        address dusdUsm;
        address dusdUsmImplementation;
        if (_params.useUnsafeUpgrades) {
            dusdUsmImplementation = address(new DUSDUsm(_params.dusd, _params.underlyingAsset));
            dusdUsm = UnsafeUpgrades.deployUUPSProxy(dusdUsmImplementation, initData);
        } else {
            Options memory opts;
            opts.constructorData = abi.encode(_params.dusd, _params.underlyingAsset);
            dusdUsm = Upgrades.deployUUPSProxy("DUSDUsm.sol:DUSDUsm", initData, opts);
            dusdUsmImplementation = Upgrades.getImplementationAddress(dusdUsm);
        }

        // Grant SWAP_FREEZER_ROLE to freezer (requires DUSDUsm admin role)
        IAccessControl(dusdUsm).grantRole(IUsm(dusdUsm).SWAP_FREEZER_ROLE(), _params.freezer);

        if (!_params.isPermissioned) {
            // Set FixedFeeStrategy on DUSDUsm (requires CONFIGURATOR_ROLE, which is granted to admin)
            IUsm(dusdUsm).updateFeeStrategy(fixedFeeStrategy);
        } else {
            IUsm(dusdUsm).updateAccessMode(AccessMode.PERMISSIONED);
        }

        // Transfer admin role to final owner (timelock)
        bytes32 adminRole = bytes32(0); // DEFAULT_ADMIN_ROLE
        IAccessControl(dusdUsm).grantRole(adminRole, _params.owner);
        IAccessControl(dusdUsm).grantRole(IUsm(dusdUsm).CONFIGURATOR_ROLE(), _params.owner);
        if (_params.isPermissioned) {
            IAccessControl(dusdUsm).grantRole(IUsm(dusdUsm).SWAPPER_ROLE(), _params.treasuryMultisig);
        }
        IAccessControl(dusdUsm).revokeRole(IUsm(dusdUsm).CONFIGURATOR_ROLE(), address(this));
        IAccessControl(dusdUsm).revokeRole(adminRole, address(this));

        report = UsmBatchReport({
            dusdUsm: dusdUsm,
            dusdUsmImplementation: dusdUsmImplementation,
            fixedPriceStrategy: fixedPriceStrategy,
            fixedFeeStrategy: fixedFeeStrategy
        });
    }

    function getReport() public view returns (UsmBatchReport memory) {
        return report;
    }
}

