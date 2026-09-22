// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_MaxWithdraw_Test is SDUSDCommon {
    function test_ReturnsZeroWhenOwnerHasNoShares() public view {
        assertEq(vault.maxWithdraw(RECEIVER), 0);
    }

    function test_ReturnsRoundedDownOwnerAssetValueAndExcludesSeedBacking() public view {
        uint256 expected = _expectedAssets(vault.balanceOf(USER), Math.Rounding.Floor);
        assertEq(vault.maxWithdraw(USER), expected);
        assertLt(vault.maxWithdraw(USER), vault.totalAssets());
    }

    function test_ActiveRewardIncludesOnlyUnlockedRewardsAndExcludesLockedRewards() public {
        _notifyRewards(REWARD_AMOUNT);
        vm.warp(vault.periodStart() + REWARD_DURATION / 2);
        uint256 ownerShares = vault.balanceOf(USER);
        uint256 supply = vault.totalSupply();
        uint256 locked = vault.lockedRewardsRemaining();
        uint256 expected =
            Math.mulDiv(ownerShares, vault.accountedAssets() - locked + 1, supply + 1, Math.Rounding.Floor);
        uint256 assetsIfLockedRewardsWereIncluded =
            Math.mulDiv(ownerShares, vault.accountedAssets() + 1, supply + 1, Math.Rounding.Floor);

        assertEq(vault.maxWithdraw(USER), expected);
        assertGt(locked, 0);
        assertLt(expected, assetsIfLockedRewardsWereIncluded);
    }

    function test_RemainsAvailableWhileFrozen() public {
        uint256 beforePause = vault.maxWithdraw(USER);
        _freezeVault();
        assertEq(vault.maxWithdraw(USER), beforePause);
    }

    function test_DoesNotIncludeRawDonation() public {
        uint256 beforeDonation = vault.maxWithdraw(USER);
        _donate(100 ether);
        assertEq(vault.maxWithdraw(USER), beforeDonation);
    }
}
