// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployAltoEthereumMainnetScript} from "../../script/DeployAltoEthereumMainnet.s.sol";
import {
    AltoEthereumMainnetInput,
    DeploymentPhase
} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";

contract DeployAltoEthereumMainnetScriptHarness is DeployAltoEthereumMainnetScript {
    function validateImplementations(DeploymentPhase phase, address dusd) external {
        AltoEthereumMainnetInput memory deploymentInput;
        deploymentInput.contracts.dusd = dusd;
        _validateImplementations(phase, deploymentInput);
    }
}

contract DeployAltoEthereumMainnetUpgradeValidationTest is Test {
    DeployAltoEthereumMainnetScriptHarness internal validator;
    address internal constant DUSD = address(0xD05D);

    function setUp() public {
        validator = new DeployAltoEthereumMainnetScriptHarness();
    }

    function test_MintCurveConvexPositionImplementationsPassUpgradeSafetyValidation() public {
        if (!_shouldVerifyProxy()) return;
        validator.validateImplementations(DeploymentPhase.MINT_CURVE_CONVEX_POSITION, address(0));
    }

    function test_StandardUsmsPassUpgradeSafetyValidation() public {
        if (!_shouldVerifyProxy()) return;
        validator.validateImplementations(DeploymentPhase.PERMISSIONED_USM, DUSD);
        validator.validateImplementations(DeploymentPhase.PERMISSIONLESS_USM, DUSD);
        validator.validateImplementations(DeploymentPhase.PERMISSIONED_FRXUSD_USM, DUSD);
        validator.validateImplementations(DeploymentPhase.PERMISSIONLESS_FRXUSD_USM, DUSD);
    }

    function test_AdvancedPermissionsUsmPassesUpgradeSafetyValidation() public {
        if (!_shouldVerifyProxy()) return;
        validator.validateImplementations(DeploymentPhase.ADVANCED_PERMISSIONS_FRXUSD_USM, DUSD);
    }

    function test_ConvexCreditLineMarketPassesUpgradeSafetyValidation() public {
        if (!_shouldVerifyProxy()) return;
        validator.validateImplementations(DeploymentPhase.CONVEX_CREDIT_LINE_MARKET, address(0));
        validator.validateImplementations(DeploymentPhase.UPGRADE_CONVEX_CREDIT_LINE_MARKET, address(0));
    }

    function test_SDUSDPhaseImplementationsPassUpgradeSafetyValidation() public {
        if (!_shouldVerifyProxy()) return;
        validator.validateImplementations(DeploymentPhase.SDUSD, address(0));
    }

    function test_MarketImplementationsPassUpgradeSafetyValidation() public {
        if (!_shouldVerifyProxy()) return;
        validator.validateImplementations(DeploymentPhase.MINT_MARKET_WETH, address(0));
        validator.validateImplementations(DeploymentPhase.BORROW_MARKET_WBTC, address(0));
    }

    function test_RevertWhen_UsmValidationHasNoDusd() public {
        vm.expectRevert("DUSD not deployed");
        validator.validateImplementations(DeploymentPhase.PERMISSIONED_USM, address(0));
    }

    function _shouldVerifyProxy() internal view returns (bool) {
        return vm.envOr("VERIFY_PROXY", false);
    }
}
