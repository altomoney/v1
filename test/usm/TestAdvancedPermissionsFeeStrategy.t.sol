// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AdvancedPermissionsFeeStrategy} from "@alto/usm/AdvancedPermissionsFeeStrategy.sol";
import {IAdvancedPermissionsUsmFeeStrategy} from "@alto/usm/interfaces/IAdvancedPermissionsUsmFeeStrategy.sol";
import {Constants} from "./helpers/Constants.sol";

contract TestAdvancedPermissionsFeeStrategy is Test, Constants {
    AdvancedPermissionsFeeStrategy feeStrategy;

    bytes32 constant SOME_ROLE = keccak256("SOME_ROLE");

    uint256 constant PERCENTAGE_PRECISION = 10000;
    uint256 constant TEST_GROSS_AMOUNT = 10000e18;

    uint16 constant DEFAULT_BUY_FEE = 100; // 1%
    uint16 constant DEFAULT_SELL_FEE = 200; // 2%
    uint16 constant ROLE_BUY_FEE = 150; // 1.5%
    uint16 constant ROLE_SELL_FEE = 250; // 2.5%
    uint16 constant OVERRIDE_BUY_FEE = 75; // 0.75%
    uint16 constant OVERRIDE_SELL_FEE = 125; // 1.25%

    function setUp() public {
        feeStrategy = new AdvancedPermissionsFeeStrategy(DEFAULT_BUY_FEE, DEFAULT_SELL_FEE, address(this));
    }

    function testRevertAboveMaximumFee() public {
        vm.expectRevert("INVALID_BUY_FEE");
        new AdvancedPermissionsFeeStrategy(5000, DEFAULT_SELL_FEE, address(this));

        vm.expectRevert("INVALID_SELL_FEE");
        new AdvancedPermissionsFeeStrategy(DEFAULT_BUY_FEE, 5000, address(this));
    }

    function testRevertZeroAdmin() public {
        vm.expectRevert("ZERO_ADDRESS_NOT_VALID");
        new AdvancedPermissionsFeeStrategy(DEFAULT_BUY_FEE, DEFAULT_SELL_FEE, address(0));
    }

    function testConstructor_SetsValuesAndEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IAdvancedPermissionsUsmFeeStrategy.FeeSet(0, 50, 0, 75);
        AdvancedPermissionsFeeStrategy newStrategy = new AdvancedPermissionsFeeStrategy(50, 75, ALICE);
        assertEq(newStrategy.getDefaultBuyFee(), 50);
        assertEq(newStrategy.getDefaultSellFee(), 75);
        assertTrue(newStrategy.hasRole(newStrategy.DEFAULT_ADMIN_ROLE(), ALICE));
        assertTrue(newStrategy.hasRole(newStrategy.CONFIGURATOR_ROLE(), ALICE));
    }

    function testSetFee_OnlyConfigurator() public {
        vm.expectEmit(true, true, true, true, address(feeStrategy));
        emit IAdvancedPermissionsUsmFeeStrategy.FeeSet(
            DEFAULT_BUY_FEE, DEFAULT_BUY_FEE + 50, DEFAULT_SELL_FEE, DEFAULT_SELL_FEE + 50
        );
        feeStrategy.setFee(DEFAULT_BUY_FEE + 50, DEFAULT_SELL_FEE + 50);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, ALICE, USM_CONFIGURATOR_ROLE
            )
        );
        feeStrategy.setFee(DEFAULT_BUY_FEE, DEFAULT_SELL_FEE);
    }

    function testOverrideBuyFee_OnlyConfigurator() public {
        IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData memory data =
            IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: OVERRIDE_BUY_FEE});

        vm.expectEmit(true, false, false, true, address(feeStrategy));
        emit IAdvancedPermissionsUsmFeeStrategy.OverrideBuyFeeSet(ALICE, data);
        feeStrategy.overrideBuyFee(ALICE, data);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, USM_CONFIGURATOR_ROLE)
        );
        feeStrategy.overrideBuyFee(ALICE, data);
    }

    function testOverrideSellFee_OnlyConfigurator() public {
        IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData memory data =
            IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: OVERRIDE_SELL_FEE});

        vm.expectEmit(true, false, false, true, address(feeStrategy));
        emit IAdvancedPermissionsUsmFeeStrategy.OverrideSellFeeSet(ALICE, data);
        feeStrategy.overrideSellFee(ALICE, data);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, USM_CONFIGURATOR_ROLE)
        );
        feeStrategy.overrideSellFee(ALICE, data);
    }

    function testSetBuyFeeByRoleHash_OnlyConfigurator() public {
        IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData memory data =
            IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: ROLE_BUY_FEE});

        vm.expectEmit(true, false, false, true, address(feeStrategy));
        emit IAdvancedPermissionsUsmFeeStrategy.BuyFeeByRoleHashSet(SOME_ROLE, data);
        feeStrategy.setBuyFeeByRoleHash(SOME_ROLE, data);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, USM_CONFIGURATOR_ROLE)
        );
        feeStrategy.setBuyFeeByRoleHash(SOME_ROLE, data);
    }

    function testRevertSetBuyFeeByRoleHash_ZeroRoleHash() public {
        vm.expectRevert("INVALID_ROLE_HASH");
        feeStrategy.setBuyFeeByRoleHash(
            bytes32(0), IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: ROLE_BUY_FEE})
        );
    }

    function testSetSellFeeByRoleHash_OnlyConfigurator() public {
        IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData memory data =
            IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: ROLE_SELL_FEE});

        vm.expectEmit(true, false, false, true, address(feeStrategy));
        emit IAdvancedPermissionsUsmFeeStrategy.SellFeeByRoleHashSet(SOME_ROLE, data);
        feeStrategy.setSellFeeByRoleHash(SOME_ROLE, data);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, USM_CONFIGURATOR_ROLE)
        );
        feeStrategy.setSellFeeByRoleHash(SOME_ROLE, data);
    }

    function testRevertSetSellFeeByRoleHash_ZeroRoleHash() public {
        vm.expectRevert("INVALID_ROLE_HASH");
        feeStrategy.setSellFeeByRoleHash(
            bytes32(0), IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: ROLE_SELL_FEE})
        );
    }

    function testSetUserBuyFeeRole_OnlyConfigurator() public {
        vm.expectEmit(true, true, false, false, address(feeStrategy));
        emit IAdvancedPermissionsUsmFeeStrategy.UserBuyFeeRoleSet(ALICE, SOME_ROLE);
        feeStrategy.setUserBuyFeeRole(ALICE, SOME_ROLE);
        assertEq(feeStrategy.getUserBuyFeeRole(ALICE), SOME_ROLE);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, USM_CONFIGURATOR_ROLE)
        );
        feeStrategy.setUserBuyFeeRole(ALICE, SOME_ROLE);
    }

    function testSetUserSellFeeRole_OnlyConfigurator() public {
        vm.expectEmit(true, true, false, false, address(feeStrategy));
        emit IAdvancedPermissionsUsmFeeStrategy.UserSellFeeRoleSet(ALICE, SOME_ROLE);
        feeStrategy.setUserSellFeeRole(ALICE, SOME_ROLE);
        assertEq(feeStrategy.getUserSellFeeRole(ALICE), SOME_ROLE);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, BOB, USM_CONFIGURATOR_ROLE)
        );
        feeStrategy.setUserSellFeeRole(ALICE, SOME_ROLE);
    }

    function testSetUserBuyFeeRole_ClearsWithZero() public {
        feeStrategy.setUserBuyFeeRole(ALICE, SOME_ROLE);
        assertEq(feeStrategy.getUserBuyFeeRole(ALICE), SOME_ROLE);

        vm.expectEmit(true, true, false, false, address(feeStrategy));
        emit IAdvancedPermissionsUsmFeeStrategy.UserBuyFeeRoleSet(ALICE, bytes32(0));
        feeStrategy.setUserBuyFeeRole(ALICE, bytes32(0));
        assertEq(feeStrategy.getUserBuyFeeRole(ALICE), bytes32(0));
    }

    function testSetUserSellFeeRole_ClearsWithZero() public {
        feeStrategy.setUserSellFeeRole(ALICE, SOME_ROLE);
        assertEq(feeStrategy.getUserSellFeeRole(ALICE), SOME_ROLE);

        vm.expectEmit(true, true, false, false, address(feeStrategy));
        emit IAdvancedPermissionsUsmFeeStrategy.UserSellFeeRoleSet(ALICE, bytes32(0));
        feeStrategy.setUserSellFeeRole(ALICE, bytes32(0));
        assertEq(feeStrategy.getUserSellFeeRole(ALICE), bytes32(0));
    }

    function testOverrideFee_SkipsFeeValidationWhenNotOverriding() public {
        uint256 overHighFee = 9999; // above MAXIMUM_FEE_PERCENT;
        IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData memory clearData =
            IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: false, fee: uint16(overHighFee)});

        feeStrategy.overrideBuyFee(ALICE, clearData);
        feeStrategy.overrideSellFee(ALICE, clearData);

        // user should still get the default fee since isOverridden=false
        assertEq(feeStrategy.getBuyFeeForUser(ALICE), DEFAULT_BUY_FEE, "buy fee should be default");
        assertEq(feeStrategy.getSellFeeForUser(ALICE), DEFAULT_SELL_FEE, "sell fee should be default");
    }

    function testGetDefaultFees() public {
        assertEq(feeStrategy.getDefaultBuyFee(), DEFAULT_BUY_FEE, "default buy fee");
        assertEq(feeStrategy.getDefaultSellFee(), DEFAULT_SELL_FEE, "default sell fee");

        feeStrategy.setFee(DEFAULT_BUY_FEE + 10, DEFAULT_SELL_FEE + 10);
        assertEq(feeStrategy.getDefaultBuyFee(), DEFAULT_BUY_FEE + 10, "updated buy fee");
        assertEq(feeStrategy.getDefaultSellFee(), DEFAULT_SELL_FEE + 10, "updated sell fee");
    }

    // Scenario 1: no address override, no userFeeRole → default fee
    function testFeeCalcs_DefaultFee() public {
        _assertBuyFeeScenario(ALICE, DEFAULT_BUY_FEE);
        _assertSellFeeScenario(ALICE, DEFAULT_SELL_FEE);
    }

    // Scenario 2: address override AND userFeeRole set → address override takes precedence
    function testFeeCalcs_AddressOverrideWinsOverUserFeeRole() public {
        _setAddressOverrides(ALICE);
        _setRoleFees(SOME_ROLE);
        feeStrategy.setUserBuyFeeRole(ALICE, SOME_ROLE);
        feeStrategy.setUserSellFeeRole(ALICE, SOME_ROLE);

        _assertBuyFeeScenario(ALICE, OVERRIDE_BUY_FEE);
        _assertSellFeeScenario(ALICE, OVERRIDE_SELL_FEE);
    }

    // Scenario 3: address override set, no userFeeRole → address override applies
    function testFeeCalcs_AddressOverrideNoUserFeeRole() public {
        _setAddressOverrides(ALICE);

        _assertBuyFeeScenario(ALICE, OVERRIDE_BUY_FEE);
        _assertSellFeeScenario(ALICE, OVERRIDE_SELL_FEE);
    }

    // Scenario 4: no address override, userFeeRole set → fee role applies
    function testFeeCalcs_UserFeeRoleApplied() public {
        _setRoleFees(SOME_ROLE);
        feeStrategy.setUserBuyFeeRole(BOB, SOME_ROLE);
        feeStrategy.setUserSellFeeRole(BOB, SOME_ROLE);

        _assertBuyFeeScenario(BOB, ROLE_BUY_FEE);
        _assertSellFeeScenario(BOB, ROLE_SELL_FEE);
    }

    // Scenario 5: buy and sell fee roles are different for the same user
    function testFeeCalcs_DifferentBuyAndSellFeeRoles() public {
        bytes32 buyRole = keccak256("BUY_FEE_ROLE");
        bytes32 sellRole = keccak256("SELL_FEE_ROLE");

        feeStrategy.setBuyFeeByRoleHash(
            buyRole, IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: ROLE_BUY_FEE})
        );
        feeStrategy.setSellFeeByRoleHash(
            sellRole, IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: ROLE_SELL_FEE})
        );

        feeStrategy.setUserBuyFeeRole(BOB, buyRole);
        feeStrategy.setUserSellFeeRole(BOB, sellRole);

        // buy role applies only to buy, sell role applies only to sell
        _assertBuyFeeScenario(BOB, ROLE_BUY_FEE);
        _assertSellFeeScenario(BOB, ROLE_SELL_FEE);

        // confirm independence: clearing sell role does not affect buy fee
        feeStrategy.setUserSellFeeRole(BOB, bytes32(0));
        _assertBuyFeeScenario(BOB, ROLE_BUY_FEE);
        _assertSellFeeScenario(BOB, DEFAULT_SELL_FEE);

        // and vice versa
        feeStrategy.setUserBuyFeeRole(BOB, bytes32(0));
        feeStrategy.setUserSellFeeRole(BOB, sellRole);
        _assertBuyFeeScenario(BOB, DEFAULT_BUY_FEE);
        _assertSellFeeScenario(BOB, ROLE_SELL_FEE);
    }

    /// @dev Asserts getBuyFeeForUser, getBuyFee, and getGrossAmountFromTotalBought
    ///      all resolve to the expected fee tier for the given originator.
    function _assertBuyFeeScenario(address originator, uint256 expectedFeePercent) internal {
        assertEq(feeStrategy.getBuyFeeForUser(originator), expectedFeePercent, "getBuyFeeForUser");

        uint256 expectedFee = TEST_GROSS_AMOUNT * expectedFeePercent / PERCENTAGE_PRECISION;
        assertEq(feeStrategy.getBuyFee(TEST_GROSS_AMOUNT, originator), expectedFee, "getBuyFee");
        assertEq(
            feeStrategy.getGrossAmountFromTotalBought(TEST_GROSS_AMOUNT + expectedFee, originator),
            TEST_GROSS_AMOUNT,
            "getGrossAmountFromTotalBought"
        );
    }

    /// @dev Asserts getSellFeeForUser, getSellFee, and getGrossAmountFromTotalSold
    ///      all resolve to the expected fee tier for the given originator.
    function _assertSellFeeScenario(address originator, uint256 expectedFeePercent) internal {
        assertEq(feeStrategy.getSellFeeForUser(originator), expectedFeePercent, "getSellFeeForUser");

        uint256 expectedFee = TEST_GROSS_AMOUNT * expectedFeePercent / PERCENTAGE_PRECISION;
        assertEq(feeStrategy.getSellFee(TEST_GROSS_AMOUNT, originator), expectedFee, "getSellFee");
        assertEq(
            feeStrategy.getGrossAmountFromTotalSold(TEST_GROSS_AMOUNT - expectedFee, originator),
            TEST_GROSS_AMOUNT,
            "getGrossAmountFromTotalSold"
        );
    }

    function _setAddressOverrides(address originator) internal {
        feeStrategy.overrideBuyFee(
            originator,
            IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: OVERRIDE_BUY_FEE})
        );
        feeStrategy.overrideSellFee(
            originator,
            IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: OVERRIDE_SELL_FEE})
        );
    }

    function _setRoleFees(bytes32 role) internal {
        feeStrategy.setBuyFeeByRoleHash(
            role, IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: ROLE_BUY_FEE})
        );
        feeStrategy.setSellFeeByRoleHash(
            role, IAdvancedPermissionsUsmFeeStrategy.OverriddenFeeData({isOverridden: true, fee: ROLE_SELL_FEE})
        );
    }
}
