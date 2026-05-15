// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TestDusdBase} from "./TestDusdBase.t.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @notice End-to-end test mirroring the DeprecatePermissionlessUsdcUsm script.
///         Freezes PSM, drains USDC via buyAsset, distributes fees, rescues dust,
///         and revokes all DUSD config. Asserts zero USDC and DUSD on the PSM.
contract TestDeprecateUsm is TestDusdBase {
    address timelock;
    address buyer;

    function setUp() public override {
        timelock = address(this);
        buyer = makeAddr("buyer");
    }

    function test_fullDeprecationFlow() public {
        _sellAsset(DUSD_USM, USDC_TOKEN, ALICE, 1_000e6);

        // Step 1: Drain via buyAsset
        uint256 available = DUSD_USM.getAvailableLiquidity();
        (, uint256 dusdNeeded,,) = DUSD_USM.getStableTokenAmountForBuyAsset(available);
        dusdFaucet(buyer, dusdNeeded);

        vm.startPrank(buyer);
        DUSD_TOKEN.approve(address(DUSD_USM), dusdNeeded);
        DUSD_USM.buyAsset(available, buyer);
        vm.stopPrank();

        // Step 2: Distribute fees
        DUSD_USM.distributeFeesToFeeRecipient();

        // Step 4: Rescue USDC dust (mirrors timelock batch)
        uint256 usdcDust = USDC_TOKEN.balanceOf(address(DUSD_USM));
        DUSD_USM.grantRole(USM_TOKEN_RESCUER_ROLE, timelock);
        if (usdcDust > 0) {
            DUSD_USM.rescueTokens(address(USDC_TOKEN), TREASURY, usdcDust);
        }

        // Step 5: Revoke DUSD config
        DUSD(DUSD_TOKEN).setMinterStatus(address(DUSD_USM), false);
        DUSD(DUSD_TOKEN).setMinterCeiling(address(DUSD_USM), 0);
        DUSD(DUSD_TOKEN).setBurnerStatus(address(DUSD_USM), false);

        // Assertions
        assertEq(USDC_TOKEN.balanceOf(address(DUSD_USM)), 0, "PSM USDC balance should be zero");
        assertEq(DUSD_TOKEN.balanceOf(address(DUSD_USM)), 0, "PSM DUSD balance should be zero");
        assertEq(DUSD_USM.getAvailableLiquidity(), 0, "available liquidity should be zero");

        (uint256 minted, uint256 ceiling) = IDUSD(address(DUSD_TOKEN)).minterConfig(address(DUSD_USM));
        assertEq(minted, 0, "minted should be zero");
        assertEq(ceiling, 0, "ceiling should be zero");
        assertFalse(IDUSD(address(DUSD_TOKEN)).allowedMinter(address(DUSD_USM)), "minter should be revoked");
        assertFalse(IDUSD(address(DUSD_TOKEN)).allowedBurner(address(DUSD_USM)), "burner should be revoked");
    }
}
