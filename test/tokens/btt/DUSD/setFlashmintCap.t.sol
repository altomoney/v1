// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DUSDCommon} from "./DUSDCommon.t.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";

contract DUSDSetFlashMintCap is DUSDCommon {
    uint256 constant DEFAULT_FLASH_MINT_CAP = 1000e18;

    modifier givenCallerIsNotOwner() {
        _;
    }

    modifier givenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_CallerIsNotOwner() external givenCallerIsNotOwner {
        vm.prank(NON_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
        dusd.setFlashMintCap(DEFAULT_FLASH_MINT_CAP);
    }

    function test_WhenSettingFlashMintCapToZero() external givenCallerIsOwner {
        // First set a non-zero cap
        vm.prank(OWNER);
        dusd.setFlashMintCap(DEFAULT_FLASH_MINT_CAP);
        assertEq(dusd.flashMintCap(), DEFAULT_FLASH_MINT_CAP);

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashMintCap(DEFAULT_FLASH_MINT_CAP, 0);

        vm.prank(OWNER);
        dusd.setFlashMintCap(0);

        // it should set flashMintCap to zero
        assertEq(dusd.flashMintCap(), 0);
    }

    function test_WhenSettingFlashMintCapToNonZeroValue() external givenCallerIsOwner {
        uint256 oldCap = dusd.flashMintCap();

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashMintCap(oldCap, DEFAULT_FLASH_MINT_CAP);

        vm.prank(OWNER);
        dusd.setFlashMintCap(DEFAULT_FLASH_MINT_CAP);

        // it should set flashMintCap to the new value
        assertEq(dusd.flashMintCap(), DEFAULT_FLASH_MINT_CAP);
    }

    function test_WhenSettingFlashMintCapToSameValue() external givenCallerIsOwner {
        // First set the cap
        vm.prank(OWNER);
        dusd.setFlashMintCap(DEFAULT_FLASH_MINT_CAP);
        assertEq(dusd.flashMintCap(), DEFAULT_FLASH_MINT_CAP);

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashMintCap(DEFAULT_FLASH_MINT_CAP, DEFAULT_FLASH_MINT_CAP);

        vm.prank(OWNER);
        dusd.setFlashMintCap(DEFAULT_FLASH_MINT_CAP);

        // it should update flashMintCap to the same value
        assertEq(dusd.flashMintCap(), DEFAULT_FLASH_MINT_CAP);
    }

    function test_WhenSettingFlashMintCapToMaxValue() external givenCallerIsOwner {
        uint256 maxValue = type(uint256).max;
        uint256 oldCap = dusd.flashMintCap();

        vm.expectEmit(true, true, true, true);
        emit IDUSD.SetFlashMintCap(oldCap, maxValue);

        vm.prank(OWNER);
        dusd.setFlashMintCap(maxValue);

        assertEq(dusd.flashMintCap(), maxValue);
    }
}
