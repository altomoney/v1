// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract DUSDSetFlashFee is DUSDCommon {
    modifier givenCallerIsNotOwner() {
        _;
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        dusd.setFlashFee(DEFAULT_FLASH_FEE);
    }

    function test_WhenSettingFlashFeeToZero() external givenCallerIsOwner {
        // First set a non-zero fee
        vm.prank(OWNER);
        dusd.setFlashFee(DEFAULT_FLASH_FEE);
        assertEq(dusd.flashFee(), DEFAULT_FLASH_FEE);

        vm.expectEmit(true, true, true, true);
        emit SetFlashFee(DEFAULT_FLASH_FEE, 0);

        vm.prank(OWNER);
        dusd.setFlashFee(0);

        uint256 flashFeeAmount = dusd.flashFee(address(dusd), MATH_PRECISION);
        uint256 expectedFlashFee = 0;

        // it should set flashFee to zero
        assertEq(dusd.flashFee(), 0);
        assertEq(flashFeeAmount, expectedFlashFee);
    }

    function test_RevertWhen_SettingFlashFeeToGreaterThanMATH_PRECISION() external givenCallerIsOwner {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IDUSD.DUSDInvalidInput.selector));
        dusd.setFlashFee(MATH_PRECISION + 1);
    }

    function test_WhenSettingFlashFeeToNonZeroValue() external givenCallerIsOwner {
        uint256 oldFee = dusd.flashFee();

        vm.expectEmit(true, true, true, true);
        emit SetFlashFee(oldFee, DEFAULT_FLASH_FEE);

        vm.prank(OWNER);
        dusd.setFlashFee(DEFAULT_FLASH_FEE);

        uint256 flashFeeAmount = dusd.flashFee(address(dusd), MATH_PRECISION);
        uint256 expectedFlashFee = DEFAULT_FLASH_FEE;

        // it should set flashFee to the new value
        assertEq(dusd.flashFee(), DEFAULT_FLASH_FEE);
        assertEq(flashFeeAmount, expectedFlashFee);
    }

    function test_WhenSettingFlashFeeToSameValue() external givenCallerIsOwner {
        // First set the fee
        vm.prank(OWNER);
        dusd.setFlashFee(DEFAULT_FLASH_FEE);
        assertEq(dusd.flashFee(), DEFAULT_FLASH_FEE);

        vm.expectEmit(true, true, true, true);
        emit SetFlashFee(DEFAULT_FLASH_FEE, DEFAULT_FLASH_FEE);

        vm.prank(OWNER);
        dusd.setFlashFee(DEFAULT_FLASH_FEE);

        uint256 flashFeeAmount = dusd.flashFee(address(dusd), MATH_PRECISION);
        uint256 expectedFlashFee = DEFAULT_FLASH_FEE;
        assertEq(flashFeeAmount, expectedFlashFee);

        // it should update flashFee to the same value
        assertEq(dusd.flashFee(), DEFAULT_FLASH_FEE);
        assertEq(flashFeeAmount, expectedFlashFee);
    }
}
