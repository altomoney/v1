// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDUSD, FlashFee} from "@alto/tokens/interfaces/IDUSD.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract DUSDSetFlashFee is DUSDCommon {
    uint128 constant MIN_FLASH_FEE_0_1_PERCENT = 0.001 ether; // 0.1%
    uint128 constant MAX_FLASH_FEE_1_PERCENT = 0.01 ether; // 1%
    uint128 constant FLAT_FLASH_FEE_0_5_PERCENT = 0.005 ether; // 0.5%

    modifier givenCallerIsNotOwner() {
        _;
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        FlashFee memory newFlashFee =
            FlashFee({minFlashFee: MIN_FLASH_FEE_0_1_PERCENT, maxFlashFee: MAX_FLASH_FEE_1_PERCENT});

        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        dusd.setFlashFee(newFlashFee);
    }

    function test_RevertWhen_MinFlashFeeIsGreaterThanMATH_PRECISION() external givenCallerIsOwner {
        FlashFee memory invalidFlashFee =
            FlashFee({minFlashFee: uint128(MATH_PRECISION + 1), maxFlashFee: MAX_FLASH_FEE_1_PERCENT});

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IDUSD.DUSDInvalidInput.selector));
        dusd.setFlashFee(invalidFlashFee);
    }

    function test_RevertWhen_MaxFlashFeeIsGreaterThanMATH_PRECISION() external givenCallerIsOwner {
        FlashFee memory invalidFlashFee =
            FlashFee({minFlashFee: MIN_FLASH_FEE_0_1_PERCENT, maxFlashFee: uint128(MATH_PRECISION + 1)});

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IDUSD.DUSDInvalidInput.selector));
        dusd.setFlashFee(invalidFlashFee);
    }

    function test_WhenBothMinAndMaxFlashFeeAreZero() external givenCallerIsOwner {
        FlashFee memory zeroFlashFee = FlashFee({minFlashFee: 0, maxFlashFee: 0});

        (uint128 oldMin, uint128 oldMax) = dusd.flashFee();
        FlashFee memory oldFlashFee = FlashFee({minFlashFee: oldMin, maxFlashFee: oldMax});

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashFee(oldFlashFee, zeroFlashFee);

        vm.prank(OWNER);
        dusd.setFlashFee(zeroFlashFee);

        (uint128 newMin, uint128 newMax) = dusd.flashFee();
        assertEq(newMin, 0);
        assertEq(newMax, 0);
    }

    function test_WhenMinFlashFeeEqualsMaxFlashFee() external givenCallerIsOwner {
        FlashFee memory newFlashFee =
            FlashFee({minFlashFee: FLAT_FLASH_FEE_0_5_PERCENT, maxFlashFee: FLAT_FLASH_FEE_0_5_PERCENT});

        (uint128 oldMin, uint128 oldMax) = dusd.flashFee();
        FlashFee memory oldFlashFee = FlashFee({minFlashFee: oldMin, maxFlashFee: oldMax});

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashFee(oldFlashFee, newFlashFee);

        vm.prank(OWNER);
        dusd.setFlashFee(newFlashFee);

        (uint128 newMin, uint128 newMax) = dusd.flashFee();
        assertEq(newMin, FLAT_FLASH_FEE_0_5_PERCENT);
        assertEq(newMax, FLAT_FLASH_FEE_0_5_PERCENT);
    }

    function test_WhenMaxFlashFeeIsGreaterThanMinFlashFee() external givenCallerIsOwner {
        FlashFee memory newFlashFee =
            FlashFee({minFlashFee: MIN_FLASH_FEE_0_1_PERCENT, maxFlashFee: MAX_FLASH_FEE_1_PERCENT});

        (uint128 oldMin, uint128 oldMax) = dusd.flashFee();
        FlashFee memory oldFlashFee = FlashFee({minFlashFee: oldMin, maxFlashFee: oldMax});

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashFee(oldFlashFee, newFlashFee);

        vm.prank(OWNER);
        dusd.setFlashFee(newFlashFee);

        (uint128 newMin, uint128 newMax) = dusd.flashFee();
        assertEq(newMin, MIN_FLASH_FEE_0_1_PERCENT);
        assertEq(newMax, MAX_FLASH_FEE_1_PERCENT);
    }

    function test_WhenMinFlashFeeIsGreaterThanMaxFlashFee() external givenCallerIsOwner {
        FlashFee memory newFlashFee =
            FlashFee({minFlashFee: MAX_FLASH_FEE_1_PERCENT, maxFlashFee: MIN_FLASH_FEE_0_1_PERCENT});

        (uint128 oldMin, uint128 oldMax) = dusd.flashFee();
        FlashFee memory oldFlashFee = FlashFee({minFlashFee: oldMin, maxFlashFee: oldMax});

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashFee(oldFlashFee, newFlashFee);

        vm.prank(OWNER);
        dusd.setFlashFee(newFlashFee);

        (uint128 newMin, uint128 newMax) = dusd.flashFee();
        assertEq(newMin, MAX_FLASH_FEE_1_PERCENT);
        assertEq(newMax, MIN_FLASH_FEE_0_1_PERCENT);
    }

    function test_WhenSettingFlashFeeStructToSameValues() external givenCallerIsOwner {
        FlashFee memory flashFee =
            FlashFee({minFlashFee: MIN_FLASH_FEE_0_1_PERCENT, maxFlashFee: MAX_FLASH_FEE_1_PERCENT});

        vm.prank(OWNER);
        dusd.setFlashFee(flashFee);

        (uint128 oldMin, uint128 oldMax) = dusd.flashFee();
        FlashFee memory oldFlashFee = FlashFee({minFlashFee: oldMin, maxFlashFee: oldMax});

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashFee(oldFlashFee, flashFee);

        vm.prank(OWNER);
        dusd.setFlashFee(flashFee);

        (uint128 newMin, uint128 newMax) = dusd.flashFee();
        assertEq(newMin, MIN_FLASH_FEE_0_1_PERCENT);
        assertEq(newMax, MAX_FLASH_FEE_1_PERCENT);
    }
}
