// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_PreviewMint_Test is SDUSDCommon {
    function test_EmptyVaultUsesInitialRatio() public {
        _useEmptyVault();
        uint256 shares = SEED_SHARES * 2;
        assertEq(vault.previewMint(shares), shares);
        assertEq(vault.previewMint(shares), _expectedAssets(shares, Math.Rounding.Ceil));
    }

    function test_ExistingVaultRoundsRequiredAssetsUp() public {
        _notifyRewards(REWARD_AMOUNT + 1);
        _finishRewardPeriod();
        uint256 shares = 10 ether + 1;
        assertEq(vault.previewMint(shares), _expectedAssets(shares, Math.Rounding.Ceil));
    }

    function test_UsesOnlyUnlockedAssetsDuringActiveRewardPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 shares = 10 ether;
        assertEq(vault.previewMint(shares), _expectedAssets(shares, Math.Rounding.Ceil));
    }

    function test_ContinuesReturningMathematicalPreviewWhilePaused() public {
        uint256 expected = vault.previewMint(10 ether);
        _pauseVault();
        assertEq(vault.previewMint(10 ether), expected);
    }

    function test_IgnoresRawDonation() public {
        uint256 beforeDonation = vault.previewMint(10 ether);
        _donate(100 ether);
        assertEq(vault.previewMint(10 ether), beforeDonation);
    }
}
