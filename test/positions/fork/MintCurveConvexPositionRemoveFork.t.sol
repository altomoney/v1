// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionForkCommon} from "./MintCurveConvexPositionForkCommon.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IMintCurveConvexPositionEvents,
    MintCurveConvexRemoveMode,
    MintCurveConvexRemoveParams
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    FRXUSD_MAINNET,
    VELORA_AUGUSTUS_V6_MAINNET,
    WETH_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";

contract MintCurveConvexPositionRemoveForkTest is MintCurveConvexPositionForkCommon {
    string internal constant DUSD_TO_FRXUSD_TX_JSON =
        "test/positions/fork/swapData/data_swap_10000_dusd_to_frxUSD.json";
    string internal constant FRXUSD_TO_DUSD_PRICE_JSON =
        "test/positions/fork/swapData/priceRoute_swap_5000_frxUSD_to_dusd.json";
    string internal constant FRXUSD_TO_DUSD_TX_JSON = "test/positions/fork/swapData/data_swap_5000_frxUSD_to_dusd.json";
    string internal constant FRXUSD_TO_DUSD_FULL_CLOSE_PRICE_JSON =
        "test/positions/fork/swapData/priceRoute_swap_8500_frxUSD_to_dusd.json";
    string internal constant FRXUSD_TO_DUSD_FULL_CLOSE_TX_JSON =
        "test/positions/fork/swapData/data_swap_8500_frxUSD_to_dusd.json";

    uint256 internal constant FRX_SWAP_AMOUNT = 5_000 ether;
    uint256 internal constant FRX_SWAP_AMOUNT_FULL_CLOSE = 8_570 ether;

    bytes internal dusdToFrxUsdSwapData;
    bytes internal frxUsdToDusdSwapData;
    bytes internal frxUsdToDusdFullCloseSwapData;
    uint256 internal expectedDusdFromFrxSwap;
    uint256 internal expectedDusdFromFrxFullCloseSwap;
    uint256 internal stakedLp;

    function setUp() public override {
        uint256 forkBlock = vm.parseJsonUint(vm.readFile(FRXUSD_TO_DUSD_PRICE_JSON), ".priceRoute.blockNumber");
        vm.createSelectFork(vm.rpcUrl("ethereum"), forkBlock);

        dusdToFrxUsdSwapData = vm.parseJsonBytes(vm.readFile(DUSD_TO_FRXUSD_TX_JSON), ".data");
        expectedDusdFromFrxSwap = vm.parseJsonUint(vm.readFile(FRXUSD_TO_DUSD_PRICE_JSON), ".priceRoute.destAmount");
        frxUsdToDusdSwapData = vm.parseJsonBytes(vm.readFile(FRXUSD_TO_DUSD_TX_JSON), ".data");
        expectedDusdFromFrxFullCloseSwap =
            vm.parseJsonUint(vm.readFile(FRXUSD_TO_DUSD_FULL_CLOSE_PRICE_JSON), ".priceRoute.destAmount");
        frxUsdToDusdFullCloseSwapData = vm.parseJsonBytes(vm.readFile(FRXUSD_TO_DUSD_FULL_CLOSE_TX_JSON), ".data");

        super.setUp();
        stakedLp = _openFullPosition();
    }

    function test_Remove_Normal_RepaysHalfDebtUnwindsFullLpAndLeavesCollateral() public {
        Position memory marketPositionBefore = _marketPosition(address(position));
        uint256 repayShares = marketPositionBefore.borrowShares / 2;
        assertGt(repayShares, 0);

        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);
        uint256 userFrxBefore = IERC20(FRXUSD_MAINNET).balanceOf(user);
        uint256 userWethBefore = IERC20(WETH_MAINNET).balanceOf(user);

        uint256 repayAssets = _borrowAssetsForShares(repayShares);

        MintCurveConvexRemoveParams memory params = _removeParams(
            MintCurveConvexRemoveMode.NORMAL, // mode
            stakedLp, // convexLpAmount
            FRX_SWAP_AMOUNT, // frxUsdAmountToSwap
            repayShares, // repayShares
            0, // collateralAmountToWithdraw
            false, // claimRewards
            frxUsdToDusdSwapData, // swapData
            expectedDusdFromFrxSwap // expectedDusdFromFrxSwap
        );

        vm.recordLogs();
        vm.prank(user);
        position.remove(_encodeRemove(params));

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition(address(position)).borrowShares, marketPositionBefore.borrowShares - repayShares);
        assertEq(IERC20(DUSD_MAINNET).allowance(address(position), VELORA_AUGUSTUS_V6_MAINNET), 0);
        assertEq(IERC20(FRXUSD_MAINNET).allowance(address(position), VELORA_AUGUSTUS_V6_MAINNET), 0);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), userWethBefore);

        uint256 frxReceived = IERC20(FRXUSD_MAINNET).balanceOf(user) - userFrxBefore;
        uint256 dusdReceived = IERC20(DUSD_MAINNET).balanceOf(user) - userDusdBefore;
        uint256 lpSideRecovered = repayAssets + frxReceived + dusdReceived;

        assertGe(
            lpSideRecovered,
            _applySlippage(BORROW_ASSETS),
            "repaid + frxUSD + dusd should be within slippage of borrow amount"
        );
        assertLe(
            lpSideRecovered,
            _addSlippage(BORROW_ASSETS),
            "repaid + frxUSD + dusd should be within slippage of borrow amount"
        );

        _assertRemovePositionLogged(MintCurveConvexRemoveMode.NORMAL, stakedLp, 0, repayShares);
    }

    function test_Remove_Normal_RepaysAllDebtWithdrawsAllCollateralAndUnwindsFullLp() public {
        Position memory marketPositionBefore = _marketPosition(address(position));
        uint256 repayShares = marketPositionBefore.borrowShares;
        uint256 collateralWithdraw = marketPositionBefore.collateralAssets;
        assertGt(repayShares, 0);
        assertGt(collateralWithdraw, 0);

        uint256 repayAssets = _borrowAssetsForShares(repayShares);

        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);
        uint256 userFrxBefore = IERC20(FRXUSD_MAINNET).balanceOf(user);
        uint256 userWethBefore = IERC20(WETH_MAINNET).balanceOf(user);

        uint256 dusdTopUp = _fullCloseRepayBuffer(repayAssets, stakedLp, expectedDusdFromFrxFullCloseSwap);
        deal(DUSD_MAINNET, user, dusdTopUp);
        vm.prank(user);
        IERC20(DUSD_MAINNET).transfer(address(position), dusdTopUp);

        MintCurveConvexRemoveParams memory params = _removeParams(
            MintCurveConvexRemoveMode.NORMAL, // mode
            stakedLp, // convexLpAmount
            FRX_SWAP_AMOUNT_FULL_CLOSE, // frxUsdAmountToSwap
            repayShares, // repayShares
            collateralWithdraw, // collateralAmountToWithdraw
            false, // claimRewards
            frxUsdToDusdFullCloseSwapData, // swapData
            expectedDusdFromFrxFullCloseSwap // expectedDusdFromFrxSwap
        );

        vm.recordLogs();
        vm.prank(user);
        position.remove(_encodeRemove(params));

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).collateralAssets, 0);
        assertEq(_marketPosition(address(position)).borrowShares, 0);
        assertEq(IERC20(DUSD_MAINNET).allowance(address(position), VELORA_AUGUSTUS_V6_MAINNET), 0);
        assertEq(IERC20(FRXUSD_MAINNET).allowance(address(position), VELORA_AUGUSTUS_V6_MAINNET), 0);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(position)), 0);

        uint256 frxReceived = IERC20(FRXUSD_MAINNET).balanceOf(user) - userFrxBefore;
        uint256 dusdReceived = IERC20(DUSD_MAINNET).balanceOf(user) - userDusdBefore;
        uint256 lpSideRecovered = dusdReceived + frxReceived + repayAssets - dusdTopUp;

        assertGe(
            lpSideRecovered,
            _applySlippage(BORROW_ASSETS),
            "frxUSD + dusd recovered should be within slippage of borrow added"
        );
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), userWethBefore + collateralWithdraw);

        _assertRemovePositionLogged(MintCurveConvexRemoveMode.NORMAL, stakedLp, collateralWithdraw, repayShares);
    }

    function test_Remove_Normal_AfterFullLiquidation_UnwindsLpAndDistributesProceedsAsDusd() public {
        Position memory marketPositionBefore = _marketPosition(address(position));
        assertGt(marketPositionBefore.collateralAssets, 0);
        assertGt(marketPositionBefore.borrowShares, 0);

        _governanceLiquidatePosition(address(position));

        Position memory marketPositionAfterLiquidation = _marketPosition(address(position));
        assertEq(marketPositionAfterLiquidation.collateralAssets, 0);
        assertEq(marketPositionAfterLiquidation.borrowShares, 0);
        assertGt(_stakedLpBalance(), 0);

        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);
        uint256 userFrxBefore = IERC20(FRXUSD_MAINNET).balanceOf(user);
        uint256 userWethBefore = IERC20(WETH_MAINNET).balanceOf(user);

        MintCurveConvexRemoveParams memory params = _removeParams(
            MintCurveConvexRemoveMode.NORMAL, // mode
            stakedLp, // convexLpAmount
            FRX_SWAP_AMOUNT_FULL_CLOSE, // frxUsdAmountToSwap
            0, // repayShares
            0, // collateralAmountToWithdraw
            false, // claimRewards
            frxUsdToDusdFullCloseSwapData, // swapData
            expectedDusdFromFrxFullCloseSwap // expectedDusdFromFrxSwap
        );

        vm.recordLogs();
        vm.prank(user);
        position.remove(_encodeRemove(params));

        uint256 frxReceived = IERC20(FRXUSD_MAINNET).balanceOf(user) - userFrxBefore;
        uint256 dusdReceived = IERC20(DUSD_MAINNET).balanceOf(user) - userDusdBefore;

        assertLt(frxReceived, 10 ether, "frxUSD received should be less than 10 ether");
        assertGe(
            dusdReceived, _applySlippage(BORROW_ASSETS), "dusd received should be within slippage of borrow amount"
        );
        assertLe(dusdReceived, _addSlippage(BORROW_ASSETS), "dusd received should be within slippage of borrow amount");

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).collateralAssets, 0);
        assertEq(_marketPosition(address(position)).borrowShares, 0);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), userWethBefore);

        _assertRemovePositionLogged(MintCurveConvexRemoveMode.NORMAL, stakedLp, 0, 0);
    }

    function test_Remove_EmergencyUnwindLp_UnwindsLpWithoutChangingMarketPosition() public {
        Position memory marketPositionBefore = _marketPosition(address(position));

        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);
        uint256 userFrxBefore = IERC20(FRXUSD_MAINNET).balanceOf(user);

        MintCurveConvexRemoveParams memory params = _removeParams(
            MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP, // mode
            stakedLp, // convexLpAmount
            0, // frxUsdAmountToSwap
            0, // repayShares
            0, // collateralAmountToWithdraw
            false, // claimRewards
            "", // swapData
            0 // expectedDusdFromFrxSwap
        );

        vm.recordLogs();
        vm.prank(user);
        position.remove(_encodeRemove(params));

        uint256 frxReceived = IERC20(FRXUSD_MAINNET).balanceOf(user) - userFrxBefore;
        uint256 dusdReceived = IERC20(DUSD_MAINNET).balanceOf(user) - userDusdBefore;

        assertGt(
            dusdReceived + frxReceived,
            _applySlippage(BORROW_ASSETS),
            "frxUSD + dusd received should be near to what was borrowed earlier"
        );

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition(address(position)).borrowShares, marketPositionBefore.borrowShares);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(position)), 0);

        _assertRemovePositionLogged(MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP, stakedLp, 0, 0);
    }

    function test_Remove_Normal_UnwindsHalfLpWithoutRepayOrCollateralChange() public {
        uint256 partialLp = stakedLp / 2;
        assertGt(partialLp, 0);
        assertLt(partialLp, stakedLp);

        Position memory marketPositionBefore = _marketPosition(address(position));
        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);
        uint256 userFrxBefore = IERC20(FRXUSD_MAINNET).balanceOf(user);
        uint256 userWethBefore = IERC20(WETH_MAINNET).balanceOf(user);

        MintCurveConvexRemoveParams memory params = _removeParams(
            MintCurveConvexRemoveMode.NORMAL, // mode
            partialLp, // convexLpAmount
            0, // frxUsdAmountToSwap
            0, // repayShares
            0, // collateralAmountToWithdraw
            false, // claimRewards
            "", // swapData
            0 // expectedDusdFromFrxSwap
        );

        vm.recordLogs();
        vm.prank(user);
        position.remove(_encodeRemove(params));

        uint256 frxReceived = IERC20(FRXUSD_MAINNET).balanceOf(user) - userFrxBefore;
        uint256 dusdReceived = IERC20(DUSD_MAINNET).balanceOf(user) - userDusdBefore;
        uint256 expectedDusdFromLp = _estimateDusdFromLpRemove(partialLp);

        assertEq(_stakedLpBalance(), stakedLp - partialLp);
        assertEq(_marketPosition(address(position)).collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition(address(position)).borrowShares, marketPositionBefore.borrowShares);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), userWethBefore);
        assertGt(frxReceived, 0);
        assertGe(dusdReceived, expectedDusdFromLp);

        uint256 lpSideRecovered = dusdReceived + frxReceived;
        uint256 halfBorrowAssets = BORROW_ASSETS / 2;
        assertGe(
            lpSideRecovered,
            _applySlippage(halfBorrowAssets),
            "partial unwind should recover within slippage of half the borrow leg"
        );
        assertLe(
            lpSideRecovered,
            _addSlippage(halfBorrowAssets),
            "partial unwind should recover within slippage of half the borrow leg"
        );

        _assertRemovePositionLogged(MintCurveConvexRemoveMode.NORMAL, partialLp, 0, 0);
    }

    function test_Remove_Normal_AfterPartialLiquidation_RepaysHalfDebtAndUnwindsLp() public {
        Position memory marketPositionAfterLiquidation = _partialLiquidatePositionState();

        uint256 repayShares = marketPositionAfterLiquidation.borrowShares / 2;
        assertGt(repayShares, 0);

        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);
        uint256 userFrxBefore = IERC20(FRXUSD_MAINNET).balanceOf(user);

        MintCurveConvexRemoveParams memory params = _removeParams(
            MintCurveConvexRemoveMode.NORMAL, // mode
            stakedLp, // convexLpAmount
            FRX_SWAP_AMOUNT, // frxUsdAmountToSwap
            repayShares, // repayShares
            0, // collateralAmountToWithdraw
            false, // claimRewards
            frxUsdToDusdSwapData, // swapData
            expectedDusdFromFrxSwap // expectedDusdFromFrxSwap
        );

        vm.prank(user);
        position.remove(_encodeRemove(params));

        assertEq(_stakedLpBalance(), 0);
        assertEq(
            _marketPosition(address(position)).borrowShares, marketPositionAfterLiquidation.borrowShares - repayShares
        );
        assertEq(_marketPosition(address(position)).collateralAssets, marketPositionAfterLiquidation.collateralAssets);
        assertGt(IERC20(DUSD_MAINNET).balanceOf(user), userDusdBefore);
        assertGt(IERC20(FRXUSD_MAINNET).balanceOf(user), userFrxBefore);
    }

    function test_Remove_Normal_AfterPartialLiquidation_ClosesRemainingDebtAndWithdrawsAllCollateral() public {
        Position memory marketPositionAfterLiquidation = _partialLiquidatePositionState();
        uint256 repayShares = marketPositionAfterLiquidation.borrowShares;
        uint256 collateralWithdraw = marketPositionAfterLiquidation.collateralAssets;

        uint256 userWethBefore = IERC20(WETH_MAINNET).balanceOf(user);

        MintCurveConvexRemoveParams memory params = _removeParams(
            MintCurveConvexRemoveMode.NORMAL, // mode
            stakedLp, // convexLpAmount
            FRX_SWAP_AMOUNT, // frxUsdAmountToSwap
            repayShares, // repayShares
            collateralWithdraw, // collateralAmountToWithdraw
            false, // claimRewards
            frxUsdToDusdSwapData, // swapData
            expectedDusdFromFrxSwap // expectedDusdFromFrxSwap
        );

        vm.recordLogs();
        vm.prank(user);
        position.remove(_encodeRemove(params));

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).collateralAssets, 0);
        assertEq(_marketPosition(address(position)).borrowShares, 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), userWethBefore + collateralWithdraw);

        _assertRemovePositionLogged(MintCurveConvexRemoveMode.NORMAL, stakedLp, collateralWithdraw, repayShares);
    }

    function test_Remove_Normal_AfterPartialLiquidation_RepaysAllDebtAndWithdrawsHalfCollateral() public {
        Position memory marketPositionAfterLiquidation = _partialLiquidatePositionState();
        uint256 repayShares = marketPositionAfterLiquidation.borrowShares;
        uint256 collateralWithdraw = uint256(marketPositionAfterLiquidation.collateralAssets) / 2;
        assertGt(collateralWithdraw, 0);

        uint256 userWethBefore = IERC20(WETH_MAINNET).balanceOf(user);

        MintCurveConvexRemoveParams memory params = _removeParams(
            MintCurveConvexRemoveMode.NORMAL, // mode
            stakedLp, // convexLpAmount
            FRX_SWAP_AMOUNT, // frxUsdAmountToSwap
            repayShares, // repayShares
            collateralWithdraw, // collateralAmountToWithdraw
            false, // claimRewards
            frxUsdToDusdSwapData, // swapData
            expectedDusdFromFrxSwap // expectedDusdFromFrxSwap
        );

        vm.recordLogs();
        vm.prank(user);
        position.remove(_encodeRemove(params));

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).borrowShares, 0);
        assertEq(
            _marketPosition(address(position)).collateralAssets,
            marketPositionAfterLiquidation.collateralAssets - uint128(collateralWithdraw)
        );
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), userWethBefore + collateralWithdraw);

        _assertRemovePositionLogged(MintCurveConvexRemoveMode.NORMAL, stakedLp, collateralWithdraw, repayShares);
    }

    function test_Remove_EmergencyUnwindLp_AfterFullLiquidation_RecoversBorrowLegProceeds() public {
        Position memory marketPositionBefore = _marketPosition(address(position));
        assertGt(marketPositionBefore.collateralAssets, 0);
        assertGt(marketPositionBefore.borrowShares, 0);

        _governanceLiquidatePosition(address(position));

        Position memory marketPositionAfterLiquidation = _marketPosition(address(position));
        assertEq(marketPositionAfterLiquidation.collateralAssets, 0);
        assertEq(marketPositionAfterLiquidation.borrowShares, 0);
        assertGt(_stakedLpBalance(), 0);

        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);
        uint256 userFrxBefore = IERC20(FRXUSD_MAINNET).balanceOf(user);

        MintCurveConvexRemoveParams memory params = _removeParams(
            MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP, // mode
            stakedLp, // convexLpAmount
            0, // frxUsdAmountToSwap
            0, // repayShares
            0, // collateralAmountToWithdraw
            false, // claimRewards
            frxUsdToDusdSwapData, // swapData
            expectedDusdFromFrxSwap // expectedDusdFromFrxSwap
        );

        vm.prank(user);
        position.remove(_encodeRemove(params));

        uint256 frxReceived = IERC20(FRXUSD_MAINNET).balanceOf(user) - userFrxBefore;
        uint256 dusdReceived = IERC20(DUSD_MAINNET).balanceOf(user) - userDusdBefore;

        assertGt(
            frxReceived + dusdReceived,
            _applySlippage(BORROW_ASSETS),
            "frxUSD + dusd received should be near to what was borrowed earlier"
        );
        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).collateralAssets, 0);
        assertEq(_marketPosition(address(position)).borrowShares, 0);
    }

    function _partialLiquidatePositionState() internal returns (Position memory marketPositionAfterLiquidation) {
        Position memory marketPositionBefore = _marketPosition(address(position));

        _makePositionLiquidatable();
        (uint256 seizedCollateral, uint256 repaidBorrow) = _partialLiquidatePosition(address(position));
        assertGt(seizedCollateral, 0);
        assertGt(repaidBorrow, 0);

        marketPositionAfterLiquidation = _marketPosition(address(position));
        assertLt(marketPositionAfterLiquidation.collateralAssets, marketPositionBefore.collateralAssets);
        assertLt(marketPositionAfterLiquidation.borrowShares, marketPositionBefore.borrowShares);
        assertGt(marketPositionAfterLiquidation.collateralAssets, 0, "partial liquidation should leave collateral");
        assertGt(marketPositionAfterLiquidation.borrowShares, 0, "partial liquidation should leave debt");
        assertGt(_stakedLpBalance(), 0);
    }

    function _openFullPosition() internal returns (uint256 lpStaked) {
        _fundUserWeth(COLLATERAL_WETH);
        vm.prank(user);
        position.add(_encodeAdd(_addParams(COLLATERAL_WETH, BORROW_ASSETS, dusdToFrxUsdSwapData, true)));
        lpStaked = _stakedLpBalance();
        assertGt(lpStaked, 0);
    }

    function _assertRemovePositionLogged(
        MintCurveConvexRemoveMode expectedMode,
        uint256 expectedConvexLpRemoved,
        uint256 expectedCollateralWithdrawn,
        uint256 expectedDebtSharesRepaid
    ) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.RemovePosition.selector) {
                (
                    MintCurveConvexRemoveMode mode,
                    uint256 convexLpRemoved,
                    uint256 collateralWithdrawn,
                    uint256 debtSharesRepaid
                ) = abi.decode(logs[i].data, (MintCurveConvexRemoveMode, uint256, uint256, uint256));
                assertEq(uint256(mode), uint256(expectedMode));
                assertEq(convexLpRemoved, expectedConvexLpRemoved);
                assertEq(collateralWithdrawn, expectedCollateralWithdrawn);
                assertEq(debtSharesRepaid, expectedDebtSharesRepaid);
                found = true;
            }
        }
        assertTrue(found);
    }
}
