// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_ConvertToShares_Test is SDUSDCommon {
    function test_UsesInitialOneToOneRatioWhenEmpty() public {
        _useEmptyVault();
        assertEq(vault.convertToShares(123 ether), 123 ether);
    }

    function test_UsesTotalSupplyAndSdusdTotalAssetsAndRoundsDown() public {
        _notifyRewards(REWARD_AMOUNT + 1);
        _finishRewardPeriod();
        uint256 assets = 3 ether + 1;
        uint256 expected = _expectedShares(assets, Math.Rounding.Floor);
        assertEq(vault.convertToShares(assets), expected);
    }

    function test_UsesOnlyUnlockedAssetsDuringActiveRewardPeriod() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 assets = 10 ether;
        assertEq(vault.convertToShares(assets), _expectedShares(assets, Math.Rounding.Floor));
        assertGt(vault.convertToShares(assets), 0);
    }

    function test_UsesAllAccountedRewardsAfterPeriodFinishes() public {
        _notifyRewards(REWARD_AMOUNT);
        _finishRewardPeriod();
        assertEq(vault.convertToShares(10 ether), _expectedShares(10 ether, Math.Rounding.Floor));
        assertLt(vault.convertToShares(10 ether), 10 ether);
    }

    function test_IgnoresRawDonation() public {
        uint256 beforeDonation = vault.convertToShares(10 ether);
        _donate(100 ether);
        assertEq(vault.convertToShares(10 ether), beforeDonation);
    }
}
