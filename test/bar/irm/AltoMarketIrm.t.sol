// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {AltoMarketIrm} from "../../../contracts/bar/irm/AltoMarketIrm.sol";
import {AltoAdaptiveCurveIrm} from "../../../contracts/bar/irm/AltoAdaptiveCurveIrm.sol";
import {WAD_INT, MathLib} from "../../../contracts/bar/irm/libraries/MathLib.sol";
import {IrmConfiguration, IrmMarketData} from "../../../contracts/bar/irm/IAltoAdaptiveCurveIrm.sol";
import {IAltoAdaptiveCurveIrm} from "../../../contracts/bar/irm/IAltoAdaptiveCurveIrm.sol";

contract AltoMarketIrmMock is AltoMarketIrm {
    address public irm;

    constructor(IrmConfiguration memory _irmConfiguration) AltoMarketIrm(_irmConfiguration) {
        irm = address(new AltoAdaptiveCurveIrm());
    }

    function accrueMarket(uint256 interest, uint256 feeAmount, uint256 borrowRate) public override {
        // Do nothing
    }

    function getIrm() public view override returns (address) {
        return irm;
    }
}

contract AltoMarketIrmTest is Test {
    using MathLib for int256;

    AltoMarketIrm internal altoMarketIrm;

    function setUp() public {
        altoMarketIrm = new AltoMarketIrmMock(_getDefaultIrmConfiguration());
    }

    function _getDefaultIrmConfiguration() internal pure returns (IrmConfiguration memory) {
        // Default values from ConstantsLib: https://github.com/morpho-org/morpho-blue-irm/blob/0e99e647c9bd6d3207f450144b6053cf807fa8c4/src/adaptive-curve-irm/libraries/ConstantsLib.sol#L7
        return IrmConfiguration({
            targetUtilization: 0.9 ether,
            initialRateAtTarget: 0.04 ether / int256(365 days),
            adjustmentSpeed: 50 ether / int256(365 days),
            minRateAtTarget: 0.001 ether / int256(365 days),
            maxRateAtTarget: 2.0 ether / int256(365 days),
            curveSteepness: 4 ether
        });
    }

    function test_constructor() external {
        new AltoMarketIrmMock(_getDefaultIrmConfiguration());
    }

    function test_accrueInterest_valid(uint256 _totalSupplyAssets, uint256 _totalBorrowAssets) external {
        _totalSupplyAssets = bound(_totalSupplyAssets, 1 ether, type(uint64).max);
        _totalBorrowAssets = bound(_totalBorrowAssets, 1 ether, type(uint64).max);

        int256 initialRateAtTarget = altoMarketIrm.irmCurrentRateAtTarget();
        vm.warp(block.timestamp + 10); // Ensure block.timestamp > irmLastUpdateTimestamp

        vm.expectEmit(false, false, false, false, address(altoMarketIrm));
        emit AltoMarketIrm.BorrowRateUpdated(0, 0);
        altoMarketIrm.accrueInterest(_totalSupplyAssets, _totalBorrowAssets);

        assertNotEq(
            altoMarketIrm.irmCurrentRateAtTarget(), initialRateAtTarget, "irmCurrentRateAtTarget should be updated"
        );
        assertEq(altoMarketIrm.irmLastUpdateTimestamp(), block.timestamp, "irmLastUpdateTimestamp should be updated");
    }

    function test_accrueInterest_valid_mock_internal_call(
        uint256 _totalSupplyAssets,
        uint256 _totalBorrowAssets,
        int256 _initialRateAtTarget
    ) external {
        _totalSupplyAssets = bound(_totalSupplyAssets, 1 ether, type(uint64).max);
        _totalBorrowAssets = bound(_totalBorrowAssets, 1 ether, type(uint64).max);
        _initialRateAtTarget = bound(_initialRateAtTarget, 0.001 ether / int256(365 days), 2.0 ether / int256(365 days));
        vm.warp(block.timestamp + 10); // Ensure block.timestamp != irmLastUpdateTimestamp

        vm.mockCall(
            altoMarketIrm.getIrm(),
            abi.encodeWithSelector(IAltoAdaptiveCurveIrm.getAccruedInterest.selector),
            abi.encode(0, 0, 0, _initialRateAtTarget)
        );

        vm.expectEmit(false, false, false, false, address(altoMarketIrm));
        emit AltoMarketIrm.BorrowRateUpdated(0, 0);
        altoMarketIrm.accrueInterest(_totalSupplyAssets, _totalBorrowAssets);

        assertEq(
            altoMarketIrm.irmCurrentRateAtTarget(), _initialRateAtTarget, "irmCurrentRateAtTarget should be updated"
        );
        assertEq(altoMarketIrm.irmLastUpdateTimestamp(), block.timestamp, "irmLastUpdateTimestamp should be updated");
    }

    function test_setIrmConfiguration_curveSteepness_valid() external {
        IrmConfiguration memory defaultIrmConfiguration = _getDefaultIrmConfiguration();
        IrmConfiguration memory newIrmConfiguration;
        newIrmConfiguration.curveSteepness = 10 ether;
        altoMarketIrm.setIrmConfiguration(newIrmConfiguration);

        _assertIrmConfiguration(
            altoMarketIrm,
            newIrmConfiguration.curveSteepness,
            defaultIrmConfiguration.adjustmentSpeed,
            defaultIrmConfiguration.targetUtilization,
            defaultIrmConfiguration.initialRateAtTarget,
            defaultIrmConfiguration.minRateAtTarget,
            defaultIrmConfiguration.maxRateAtTarget
        );
    }

    function test_setIrmConfiguration_adjustmentSpeed_valid() external {
        IrmConfiguration memory defaultIrmConfiguration = _getDefaultIrmConfiguration();
        IrmConfiguration memory newIrmConfiguration;
        newIrmConfiguration.adjustmentSpeed = 10 ether / int256(365 days);
        altoMarketIrm.setIrmConfiguration(newIrmConfiguration);

        _assertIrmConfiguration(
            altoMarketIrm,
            defaultIrmConfiguration.curveSteepness,
            newIrmConfiguration.adjustmentSpeed,
            defaultIrmConfiguration.targetUtilization,
            defaultIrmConfiguration.initialRateAtTarget,
            defaultIrmConfiguration.minRateAtTarget,
            defaultIrmConfiguration.maxRateAtTarget
        );
    }

    function test_setIrmConfiguration_targetUtilization_valid() external {
        IrmConfiguration memory defaultIrmConfiguration = _getDefaultIrmConfiguration();
        IrmConfiguration memory newIrmConfiguration;
        newIrmConfiguration.targetUtilization = 0.8 ether;
        altoMarketIrm.setIrmConfiguration(newIrmConfiguration);

        _assertIrmConfiguration(
            altoMarketIrm,
            defaultIrmConfiguration.curveSteepness,
            defaultIrmConfiguration.adjustmentSpeed,
            newIrmConfiguration.targetUtilization,
            defaultIrmConfiguration.initialRateAtTarget,
            defaultIrmConfiguration.minRateAtTarget,
            defaultIrmConfiguration.maxRateAtTarget
        );
    }

    function test_setIrmConfiguration_initialRateAtTarget_valid() external {
        IrmConfiguration memory defaultIrmConfiguration = _getDefaultIrmConfiguration();
        IrmConfiguration memory newIrmConfiguration;
        newIrmConfiguration.initialRateAtTarget = 0.02 ether / int256(365 days);
        altoMarketIrm.setIrmConfiguration(newIrmConfiguration);

        _assertIrmConfiguration(
            altoMarketIrm,
            defaultIrmConfiguration.curveSteepness,
            defaultIrmConfiguration.adjustmentSpeed,
            defaultIrmConfiguration.targetUtilization,
            newIrmConfiguration.initialRateAtTarget,
            defaultIrmConfiguration.minRateAtTarget,
            defaultIrmConfiguration.maxRateAtTarget
        );
    }

    function test_setIrmConfiguration_minRateAtTarget_valid() external {
        IrmConfiguration memory defaultIrmConfiguration = _getDefaultIrmConfiguration();
        IrmConfiguration memory newIrmConfiguration;
        newIrmConfiguration.minRateAtTarget = 0.001 ether / int256(365 days);
        altoMarketIrm.setIrmConfiguration(newIrmConfiguration);

        _assertIrmConfiguration(
            altoMarketIrm,
            defaultIrmConfiguration.curveSteepness,
            defaultIrmConfiguration.adjustmentSpeed,
            defaultIrmConfiguration.targetUtilization,
            defaultIrmConfiguration.initialRateAtTarget,
            newIrmConfiguration.minRateAtTarget,
            defaultIrmConfiguration.maxRateAtTarget
        );
    }

    function test_setIrmConfiguration_maxRateAtTarget_valid() external {
        IrmConfiguration memory defaultIrmConfiguration = _getDefaultIrmConfiguration();
        IrmConfiguration memory newIrmConfiguration;
        newIrmConfiguration.maxRateAtTarget = 2.0 ether / int256(365 days);
        altoMarketIrm.setIrmConfiguration(newIrmConfiguration);

        _assertIrmConfiguration(
            altoMarketIrm,
            defaultIrmConfiguration.curveSteepness,
            defaultIrmConfiguration.adjustmentSpeed,
            defaultIrmConfiguration.targetUtilization,
            defaultIrmConfiguration.initialRateAtTarget,
            defaultIrmConfiguration.minRateAtTarget,
            newIrmConfiguration.maxRateAtTarget
        );
    }

    function test_setIrmConfiguration_invalid_not_owner(address _notOwner) external {
        vm.assume(_notOwner != altoMarketIrm.owner());

        IrmConfiguration memory defaultIrmConfiguration = _getDefaultIrmConfiguration();
        IrmConfiguration memory newIrmConfiguration;
        newIrmConfiguration.targetUtilization = 0.8 ether;

        vm.startPrank(_notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        altoMarketIrm.setIrmConfiguration(newIrmConfiguration);
        vm.stopPrank();

        _assertIrmConfiguration(
            altoMarketIrm,
            defaultIrmConfiguration.curveSteepness,
            defaultIrmConfiguration.adjustmentSpeed,
            defaultIrmConfiguration.targetUtilization,
            defaultIrmConfiguration.initialRateAtTarget,
            defaultIrmConfiguration.minRateAtTarget,
            defaultIrmConfiguration.maxRateAtTarget
        );
    }

    function _assertIrmConfiguration(
        AltoMarketIrm _altoMarketIrm,
        int256 _curveSteepness,
        int256 _adjustmentSpeed,
        int256 _targetUtilization,
        int256 _initialRateAtTarget,
        int256 _minRateAtTarget,
        int256 _maxRateAtTarget
    ) internal view {
        (
            int256 curveSteepness,
            int256 adjustmentSpeed,
            int256 targetUtilization,
            int256 initialRateAtTarget,
            int256 minRateAtTarget,
            int256 maxRateAtTarget
        ) = _altoMarketIrm.irmConfiguration();
        assertEq(curveSteepness, _curveSteepness, "curveSteepness should be updated");
        assertEq(adjustmentSpeed, _adjustmentSpeed, "adjustmentSpeed should be updated");
        assertEq(targetUtilization, _targetUtilization, "targetUtilization should be updated");
        assertEq(initialRateAtTarget, _initialRateAtTarget, "initialRateAtTarget should be updated");
        assertEq(minRateAtTarget, _minRateAtTarget, "minRateAtTarget should be updated");
        assertEq(maxRateAtTarget, _maxRateAtTarget, "maxRateAtTarget should be updated");
    }
}
