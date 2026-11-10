// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_PreviewDeposit_Test is SDUSDCommon {
    function test_EmptyVaultReturnsFullInitialPreview() public {
        _useEmptyVault();
        uint256 assets = SEED_SHARES * 2;
        assertEq(vault.previewDeposit(assets), assets);
        assertEq(vault.previewDeposit(assets), _expectedShares(assets, Math.Rounding.Floor));
    }

    function test_ExistingVaultMatchesRoundedDownConvertToShares() public view {
        uint256 assets = 10 ether + 1;
        assertEq(vault.previewDeposit(assets), vault.convertToShares(assets));
    }

    function test_UsesOnlyUnlockedAssetsDuringActiveRewardPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 assets = 10 ether;
        assertEq(vault.previewDeposit(assets), _expectedShares(assets, Math.Rounding.Floor));
    }

    function test_ContinuesReturningMathematicalPreviewWhilePaused() public {
        uint256 expected = vault.previewDeposit(10 ether);
        _pauseVault();
        assertEq(vault.previewDeposit(10 ether), expected);
    }

    function test_IgnoresRawDonation() public {
        uint256 beforeDonation = vault.previewDeposit(10 ether);
        _donate(100 ether);
        assertEq(vault.previewDeposit(10 ether), beforeDonation);
    }
}
