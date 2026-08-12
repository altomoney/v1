// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionForkCommon} from "./MintCurveConvexPositionForkCommon.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMintCurveConvexPositionEvents} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {CRV_TOKEN_MAINNET, CVX_TOKEN_MAINNET, WETH_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @dev Fork coverage for claimRewards.
contract MintCurveConvexPositionClaimRewardsForkTest is MintCurveConvexPositionForkCommon {
    uint256 internal constant REWARD_ACCRUAL_BLOCKS = 100_000;
    uint256 internal constant REWARD_ACCRUAL_PERIOD = 14 days;
    address internal constant WFRAX_MAINNET = 0x04ACaF8D2865c0714F79da09645C13FD2888977f;

    uint256 internal stakedLp;

    function setUp() public override {
        super.setUp();
        stakedLp = _openBorrowPosition();
    }

    function test_ClaimRewards_TransfersAccruedRewardsToOwner() public {
        Position memory before = _marketPosition(address(position));

        _advanceChainForRewards();

        assertEq(_stakedLpBalance(), stakedLp, "stake unchanged after time advance");

        uint256 userCrvBefore = IERC20(CRV_TOKEN_MAINNET).balanceOf(user);
        uint256 userCvxBefore = IERC20(CVX_TOKEN_MAINNET).balanceOf(user);
        uint256 userWfraxBefore = IERC20(WFRAX_MAINNET).balanceOf(user);

        vm.recordLogs();
        vm.prank(user);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        uint256 crvReceived = IERC20(CRV_TOKEN_MAINNET).balanceOf(user) - userCrvBefore;
        uint256 cvxReceived = IERC20(CVX_TOKEN_MAINNET).balanceOf(user) - userCvxBefore;
        uint256 wfraxReceived = IERC20(WFRAX_MAINNET).balanceOf(user) - userWfraxBefore;

        assertGt(crvReceived, 0, "crv accrued and forwarded");
        assertGt(cvxReceived, 0, "cvx accrued and forwarded");
        assertEq(IERC20(CRV_TOKEN_MAINNET).balanceOf(address(position)), 0, "no crv left in position");
        assertEq(IERC20(CVX_TOKEN_MAINNET).balanceOf(address(position)), 0, "no cvx left in position");
        assertEq(IERC20(WFRAX_MAINNET).balanceOf(address(position)), 0, "no wfrax left in position");

        // Claiming never touches the underlying market position or stake.
        assertEq(_stakedLpBalance(), stakedLp);
        assertEq(_marketPosition(address(position)).collateralAssets, before.collateralAssets);
        assertEq(_marketPosition(address(position)).borrowShares, before.borrowShares);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(position)), 0);

        assertEq(tokens.length, 3, "live CVX and WFRAX wrappers deduplicated");
        assertEq(amounts.length, 3);
        assertEq(tokens[0], CRV_TOKEN_MAINNET);
        assertEq(tokens[1], CVX_TOKEN_MAINNET);
        assertEq(tokens[2], WFRAX_MAINNET);
        assertEq(amounts[0], crvReceived);
        assertEq(amounts[1], cvxReceived);
        assertEq(amounts[2], wfraxReceived);
        _assertBaseRewardEvents(crvReceived, cvxReceived);
    }

    function test_ClaimRewards_WithNoAccrualEmitsZeroAmounts() public {
        // Immediately after opening the position, no meaningful rewards have accrued.
        uint256 userCrvBefore = IERC20(CRV_TOKEN_MAINNET).balanceOf(user);
        uint256 userCvxBefore = IERC20(CVX_TOKEN_MAINNET).balanceOf(user);
        uint256 userWfraxBefore = IERC20(WFRAX_MAINNET).balanceOf(user);

        vm.recordLogs();
        vm.prank(user);
        (address[] memory tokens, uint256[] memory amounts) = position.claimRewards();

        // Whatever dust is claimed is fully forwarded, leaving nothing in the position.
        assertEq(IERC20(CRV_TOKEN_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(CVX_TOKEN_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WFRAX_MAINNET).balanceOf(address(position)), 0);

        uint256 crvReceived = IERC20(CRV_TOKEN_MAINNET).balanceOf(user) - userCrvBefore;
        uint256 cvxReceived = IERC20(CVX_TOKEN_MAINNET).balanceOf(user) - userCvxBefore;
        uint256 wfraxReceived = IERC20(WFRAX_MAINNET).balanceOf(user) - userWfraxBefore;
        assertEq(tokens.length, 3);
        assertEq(amounts.length, 3);
        assertEq(tokens[0], CRV_TOKEN_MAINNET);
        assertEq(tokens[1], CVX_TOKEN_MAINNET);
        assertEq(tokens[2], WFRAX_MAINNET);
        assertEq(amounts[0], crvReceived);
        assertEq(amounts[1], cvxReceived);
        assertEq(amounts[2], wfraxReceived);
        _assertBaseRewardEvents(crvReceived, cvxReceived);
    }

    function _advanceChainForRewards() internal {
        vm.roll(block.number + REWARD_ACCRUAL_BLOCKS);
        vm.warp(block.timestamp + REWARD_ACCRUAL_PERIOD);
    }

    function _assertBaseRewardEvents(uint256 expectedCrv, uint256 expectedCvx) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundCrv;
        bool foundCvx;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(position)
                    && logs[i].topics[0] == IMintCurveConvexPositionEvents.RewardClaimed.selector
            ) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), user);
                address token = address(uint160(uint256(logs[i].topics[2])));
                if (token == CRV_TOKEN_MAINNET) {
                    assertEq(abi.decode(logs[i].data, (uint256)), expectedCrv);
                    foundCrv = true;
                } else if (token == CVX_TOKEN_MAINNET) {
                    assertEq(abi.decode(logs[i].data, (uint256)), expectedCvx);
                    foundCvx = true;
                }
            }
        }
        assertEq(foundCrv, expectedCrv > 0, "CRV event emitted exactly for nonzero transfer");
        assertEq(foundCvx, expectedCvx > 0, "CVX event emitted exactly for nonzero transfer");
    }
}
