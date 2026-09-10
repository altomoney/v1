// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IConvexRewardPool} from "@alto/lending/interfaces/vendor/IConvexRewardPool.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketStakedCollateralAssetsTest is ConvexCreditLineCommon {
    function test_ReturnsExactRewardPoolBalanceForMarket() external {
        bytes memory callData = abi.encodeCall(IConvexRewardPool.balanceOf, (address(market)));

        vm.expectCall(address(rewardPool), callData);
        assertEq(market.stakedCollateralAssets(), 0);

        rewardPool.setStake(address(market), 123 ether);
        vm.expectCall(address(rewardPool), callData);
        assertEq(market.stakedCollateralAssets(), 123 ether);
    }

    function test_PropagatesRewardPoolBalanceQueryRevert() external {
        bytes memory callData = abi.encodeCall(IConvexRewardPool.balanceOf, (address(market)));

        vm.mockCallRevert(address(rewardPool), callData, "BALANCE_REVERTED");
        vm.expectRevert(bytes("BALANCE_REVERTED"));
        market.stakedCollateralAssets();
        vm.clearMockedCalls();
    }

    function test_RevertWhenRewardPoolBalanceQueryReturnsMalformedData() external {
        bytes memory callData = abi.encodeCall(IConvexRewardPool.balanceOf, (address(market)));

        vm.mockCall(address(rewardPool), callData, hex"01");
        vm.expectRevert();
        market.stakedCollateralAssets();
        vm.clearMockedCalls();
    }
}
