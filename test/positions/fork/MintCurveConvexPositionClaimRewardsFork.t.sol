// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionForkCommon} from "./MintCurveConvexPositionForkCommon.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMintCurveConvexPositionEvents} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    CRV_TOKEN_MAINNET,
    CVX_TOKEN_MAINNET,
    FRXUSD_MAINNET,
    VELORA_AUGUSTUS_V6_MAINNET,
    WETH_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";

contract MintCurveConvexPositionClaimRewardsForkTest is MintCurveConvexPositionForkCommon {
    string internal constant DUSD_TO_FRXUSD_PRICE_JSON =
        "test/positions/fork/swapData/priceRoute_swap_10000_dusd_to_frxUSD.json";
    string internal constant DUSD_TO_FRXUSD_TX_JSON =
        "test/positions/fork/swapData/data_swap_10000_dusd_to_frxUSD.json";

    uint256 internal constant REWARD_ACCRUAL_BLOCKS = 100_000;
    uint256 internal constant REWARD_ACCRUAL_PERIOD = 14 days;

    bytes internal dusdToFrxUsdSwapData;

    function setUp() public override {
        uint256 forkBlock = vm.parseJsonUint(vm.readFile(DUSD_TO_FRXUSD_PRICE_JSON), ".priceRoute.blockNumber");
        vm.createSelectFork(vm.rpcUrl("ethereum"), forkBlock);

        dusdToFrxUsdSwapData = vm.parseJsonBytes(vm.readFile(DUSD_TO_FRXUSD_TX_JSON), ".data");

        super.setUp();
    }

    function test_ClaimRewards_TransfersAccruedRewardsToOwner() public {
        uint256 stakedLp = _openBorrowPosition();
        Position memory marketPositionBefore = _marketPosition(address(position));

        _advanceChainForRewards();

        assertEq(_stakedLpBalance(), stakedLp, "convex reward pool stake should be unchanged after time advance");

        uint256 userCrvBefore = IERC20(CRV_TOKEN_MAINNET).balanceOf(user);
        uint256 userCvxBefore = IERC20(CVX_TOKEN_MAINNET).balanceOf(user);

        vm.recordLogs();
        vm.prank(user);
        position.claimRewards();

        uint256 crvReceived = IERC20(CRV_TOKEN_MAINNET).balanceOf(user) - userCrvBefore;
        uint256 cvxReceived = IERC20(CVX_TOKEN_MAINNET).balanceOf(user) - userCvxBefore;

        assertGt(crvReceived, 0);
        assertGt(cvxReceived, 0);
        assertEq(IERC20(CRV_TOKEN_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(CVX_TOKEN_MAINNET).balanceOf(address(position)), 0);
        assertEq(_stakedLpBalance(), stakedLp);
        assertEq(_marketPosition(address(position)).collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition(address(position)).borrowShares, marketPositionBefore.borrowShares);
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(position)), 0);

        _assertClaimRewardsLogged(crvReceived, cvxReceived);
    }

    function _openBorrowPosition() internal returns (uint256 stakedLp) {
        _fundUserWeth(COLLATERAL_WETH);
        vm.prank(user);
        position.add(_encodeAdd(_addParams(COLLATERAL_WETH, BORROW_ASSETS, dusdToFrxUsdSwapData, false)));
        stakedLp = _stakedLpBalance();
        assertGt(stakedLp, 0);
        assertGt(_marketPosition(address(position)).borrowShares, 0);
    }

    function _advanceChainForRewards() internal {
        vm.roll(block.number + REWARD_ACCRUAL_BLOCKS);
        vm.warp(block.timestamp + REWARD_ACCRUAL_PERIOD);
    }

    function _assertClaimRewardsLogged(uint256 expectedCrv, uint256 expectedCvx) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.ClaimRewards.selector) {
                (uint256 loggedCrv, uint256 loggedCvx) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(loggedCrv, expectedCrv);
                assertEq(loggedCvx, expectedCvx);
                found = true;
            }
        }
        assertTrue(found);
    }
}
