// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_PreviewWithdraw_Test is SDUSDCommon {
    function test_EmptyVaultUsesInitialRatio() public {
        _useEmptyVault();
        assertEq(vault.previewWithdraw(10 ether), 10 ether);
    }

    function test_ExistingVaultRoundsRequiredSharesUp() public {
        _notifyRewards(REWARD_AMOUNT + 1);
        _finishRewardPeriod();
        uint256 assets = 10 ether + 1;
        assertEq(vault.previewWithdraw(assets), _expectedShares(assets, Math.Rounding.Ceil));
    }

    function test_UsesOnlyUnlockedAssetsDuringActiveRewardPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 assets = 10 ether;
        assertEq(vault.previewWithdraw(assets), _expectedShares(assets, Math.Rounding.Ceil));
    }

    function test_ContinuesReturningMathematicalPreviewWhilePaused() public {
        uint256 expected = vault.previewWithdraw(1 ether);
        _pauseVault();
        assertEq(vault.previewWithdraw(1 ether), expected);
    }

    function test_IgnoresRawDonation() public {
        uint256 beforeDonation = vault.previewWithdraw(1 ether);
        _donate(100 ether);
        assertEq(vault.previewWithdraw(1 ether), beforeDonation);
    }
}
