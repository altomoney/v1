// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestDusdBase.t.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestUsmSampleLiquidator is TestDusdBase {
    function testSeize() public {
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.Seized(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), TREASURY, 0, 0);
        DUSD_USM_LAST_RESORT_LIQUIDATOR.triggerSeize(address(DUSD_USM));
    }

    function testRevertSeizeNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        vm.prank(ALICE);
        DUSD_USM_LAST_RESORT_LIQUIDATOR.triggerSeize(address(DUSD_USM));
    }

    function testRevertSeizeAlreadySeized() public {
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.Seized(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), TREASURY, 0, 0);
        DUSD_USM_LAST_RESORT_LIQUIDATOR.triggerSeize(address(DUSD_USM));

        vm.expectRevert("USM_SEIZED");
        DUSD_USM_LAST_RESORT_LIQUIDATOR.triggerSeize(address(DUSD_USM));
    }

    function testBurnAfterSeize() public {
        // Mint DUSD in the GSM
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        // Seize the GSM
        uint256 seizedAmount = DUSD_USM_LAST_RESORT_LIQUIDATOR.triggerSeize(address(DUSD_USM));
        assertEq(seizedAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected seize amount returned");

        // Mint the current bucket level
        (uint256 bucketLevel,) = DUSD_TOKEN.minterConfig(address(DUSD_USM));
        assertGt(bucketLevel, 0, "Unexpected 0 mintedDUSD");
        dusdFaucet(address(this), bucketLevel);

        DUSD_TOKEN.approve(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), bucketLevel);
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.BurnAfterSeize(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), bucketLevel, 0);
        uint256 burnAmount = DUSD_USM_LAST_RESORT_LIQUIDATOR.triggerBurnAfterSeize(address(DUSD_USM), bucketLevel);
        assertEq(burnAmount, bucketLevel, "Unexpected burn amount returned");
    }

    function testBurnMoreThanMintedAfterSeize() public {
        // Mint DUSD in the USM
        vm.prank(FAUCET);
        USDC_TOKEN.mint(ALICE, DEFAULT_USM_USDC_AMOUNT);
        vm.startPrank(ALICE);
        USDC_TOKEN.approve(address(DUSD_USM), DEFAULT_USM_USDC_AMOUNT);
        DUSD_USM.sellAsset(DEFAULT_USM_USDC_AMOUNT, ALICE);
        vm.stopPrank();

        // Seize the GSM
        uint256 seizedAmount = DUSD_USM_LAST_RESORT_LIQUIDATOR.triggerSeize(address(DUSD_USM));
        assertEq(seizedAmount, DEFAULT_USM_USDC_AMOUNT, "Unexpected seize amount returned");

        // Mint the current bucket level + 1, to have more DUSD than necessary
        (uint256 bucketLevel,) = DUSD_TOKEN.minterConfig(address(DUSD_USM));
        assertGt(bucketLevel, 0, "Unexpected 0 minted DUSD");
        dusdFaucet(address(this), bucketLevel + 1);

        // Attempt to burn more than what was minted, leaving 1 DUSD left-over and burning the bucketLevel
        DUSD_TOKEN.approve(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), bucketLevel + 1);
        vm.expectEmit(true, false, false, true, address(DUSD_USM));
        emit IUsm.BurnAfterSeize(address(DUSD_USM_LAST_RESORT_LIQUIDATOR), bucketLevel, 0);
        uint256 burnAmount = DUSD_USM_LAST_RESORT_LIQUIDATOR.triggerBurnAfterSeize(address(DUSD_USM), bucketLevel + 1);
        assertEq(burnAmount, bucketLevel, "Unexpected burn amount returned");
        assertEq(DUSD_TOKEN.balanceOf(address(this)), 1, "Unexpected final DUSD amount");
    }
}
