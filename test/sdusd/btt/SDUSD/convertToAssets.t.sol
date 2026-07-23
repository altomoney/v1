// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_ConvertToAssets_Test is SDUSDCommon {
    function test_UsesInitialOneToOneRatioWhenEmpty() public {
        _useEmptyVault();
        assertEq(vault.convertToAssets(123 ether), 123 ether);
    }

    function test_UsesSdusdTotalAssetsAndTotalSupplyAndRoundsDown() public {
        _notifyRewards(REWARD_AMOUNT + 1);
        _finishRewardPeriod();
        uint256 shares = 3 ether + 1;
        uint256 expected = _expectedAssets(shares, Math.Rounding.Floor);
        assertEq(vault.convertToAssets(shares), expected);
    }

    function test_UsesOnlyUnlockedAssetsDuringActiveRewardPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 shares = 10 ether;
        assertEq(vault.convertToAssets(shares), _expectedAssets(shares, Math.Rounding.Floor));
    }

    function test_UsesAllAccountedRewardsAfterPeriodFinishes() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        assertEq(vault.convertToAssets(1 ether), _expectedAssets(1 ether, Math.Rounding.Floor));
        assertGt(vault.convertToAssets(1 ether), 1 ether);
    }

    function test_IgnoresRawDonation() public {
        uint256 beforeDonation = vault.convertToAssets(1 ether);
        _donate(100 ether);
        assertEq(vault.convertToAssets(1 ether), beforeDonation);
    }
}
