// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerCanLockWithDebtTest is TOBTestBase {
    address testUser;

    uint256 _collateralAmount;
    uint256 _borrowAmount;

    modifier whenValidConditions() {
        _collateralAmount = 3e18;
        _borrowAmount = 1e18;
        _addCollateralBigBang(_collateralAmount, bigBangInstance, testUser, testUser, testUser, testUser, false);
        _borrowBigBang(_borrowAmount, bigBangInstance, testUser, testUser, testUser);
        _;
    }

    function setUp() public override {
        super.setUp();
        testUser = makeAddr("testUser");

        // Set up cluster
        vm.startPrank(owner);
        tob.setCluster(address(cluster));
        vm.stopPrank();
    }

    function test_revertWhen_clusterNotSet() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes("NotValid"));
        tob.setCluster(address(0));
        vm.stopPrank();
    }

    function test_revertWhen_bigBangNotSet() public {
        // Mock empty bigBang markets array
        vm.mockCall(address(report.penrose), abi.encodeWithSignature("bigBangMarkets()"), abi.encode(new address[](0)));

        (bool canLock,,) = tob.canLockWithDebt(testUser, 0);
        assertFalse(canLock, "Should not be able to lock");
    }

    function test_revertWhen_noDebt() public {
        (bool canLock,,) = tob.canLockWithDebt(testUser, 0);
        assertFalse(canLock, "Should not be able to lock");
    }

    function test_canLockWithDebt_validConditions() public whenValidConditions {
        (bool canLock,,) = tob.canLockWithDebt(testUser, 0);
        assertTrue(canLock, "Should be able to lock");
    }
}
