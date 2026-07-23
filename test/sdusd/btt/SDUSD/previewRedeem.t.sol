// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_PreviewRedeem_Test is SDUSDCommon {
    function test_EmptyVaultUsesInitialRatio() public {
        _useEmptyVault();
        assertEq(vault.previewRedeem(10 ether), 10 ether);
    }

    function test_ExistingVaultMatchesRoundedDownConvertToAssets() public view {
        uint256 shares = 1 ether + 1;
        assertEq(vault.previewRedeem(shares), vault.convertToAssets(shares));
    }

    function test_UsesOnlyUnlockedAssetsDuringActiveRewardPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 shares = 1 ether;
        assertEq(vault.previewRedeem(shares), _expectedAssets(shares, Math.Rounding.Floor));
    }

    function test_ContinuesReturningMathematicalPreviewWhilePaused() public {
        uint256 expected = vault.previewRedeem(1 ether);
        _pauseVault();
        assertEq(vault.previewRedeem(1 ether), expected);
    }

    function test_IgnoresRawDonation() public {
        uint256 beforeDonation = vault.previewRedeem(1 ether);
        _donate(100 ether);
        assertEq(vault.previewRedeem(1 ether), beforeDonation);
    }
}
