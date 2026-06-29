// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionForkCommon} from "./MintCurveConvexPositionForkCommon.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMintCurveConvexPositionEvents} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {FRXUSD_MAINNET, VELORA_AUGUSTUS_V6_MAINNET, WETH_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

contract MintCurveConvexPositionAddForkTest is MintCurveConvexPositionForkCommon {
    string internal constant DUSD_TO_FRXUSD_PRICE_JSON =
        "test/positions/fork/swapData/priceRoute_swap_10000_dusd_to_frxUSD.json";
    string internal constant DUSD_TO_FRXUSD_TX_JSON =
        "test/positions/fork/swapData/data_swap_10000_dusd_to_frxUSD.json";

    bytes internal dusdToFrxUsdSwapData;
    uint256 internal expectedFrxOut;

    function setUp() public override {
        uint256 forkBlock = vm.parseJsonUint(vm.readFile(DUSD_TO_FRXUSD_PRICE_JSON), ".priceRoute.blockNumber");
        vm.createSelectFork(vm.rpcUrl("ethereum"), forkBlock);

        expectedFrxOut = vm.parseJsonUint(vm.readFile(DUSD_TO_FRXUSD_PRICE_JSON), ".priceRoute.destAmount");
        dusdToFrxUsdSwapData = vm.parseJsonBytes(vm.readFile(DUSD_TO_FRXUSD_TX_JSON), ".data");

        super.setUp();
    }

    function test_Add_CollateralOnly() public {
        uint256 collateralAmount = 10 ether;
        _fundUserWeth(collateralAmount);

        Position memory marketPositionBefore = _marketPosition(address(position));
        uint256 stakedLpBefore = _stakedLpBalance();

        vm.expectEmit(true, false, false, true);
        emit IMintCurveConvexPositionEvents.AddPosition(user, collateralAmount, 0, 0);

        vm.prank(user);
        position.add(_encodeAdd(_addParams(collateralAmount, 0, dusdToFrxUsdSwapData, false)));

        assertEq(
            _marketPosition(address(position)).collateralAssets,
            marketPositionBefore.collateralAssets + uint128(collateralAmount)
        );
        assertEq(_marketPosition(address(position)).borrowShares, marketPositionBefore.borrowShares);
        assertEq(_stakedLpBalance(), stakedLpBefore);
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), 0);
    }

    function test_Add_BorrowOnly() public {
        _addCollateralOnly(COLLATERAL_WETH);

        Position memory marketPositionBefore = _marketPosition(address(position));
        uint256 userWethBefore = IERC20(WETH_MAINNET).balanceOf(user);

        vm.recordLogs();
        vm.prank(user);
        position.add(_encodeAdd(_addParams(0, BORROW_ASSETS, dusdToFrxUsdSwapData, false)));

        assertEq(IERC20(WETH_MAINNET).balanceOf(user), userWethBefore);
        assertGt(_marketPosition(address(position)).borrowShares, marketPositionBefore.borrowShares);
        assertEq(_marketPosition(address(position)).collateralAssets, marketPositionBefore.collateralAssets);
        assertGt(_stakedLpBalance(), 0);
        assertEq(IERC20(DUSD_MAINNET).allowance(address(position), VELORA_AUGUSTUS_V6_MAINNET), 0);
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertAddPositionLogged(0, BORROW_ASSETS, logs);
        _assertSwapLogged(
            DUSD_MAINNET, FRXUSD_MAINNET, BORROW_ASSETS / 2, VELORA_AUGUSTUS_V6_MAINNET, _applySlippage(expectedFrxOut), logs
        );
    }

    function test_Add_CollateralPlusBorrow() public {
        uint256 collateralAmount = COLLATERAL_WETH;
        _fundUserWeth(collateralAmount);

        Position memory marketPositionBefore = _marketPosition(address(position));

        vm.recordLogs();
        vm.prank(user);
        position.add(_encodeAdd(_addParams(collateralAmount, BORROW_ASSETS, dusdToFrxUsdSwapData, false)));

        assertEq(
            _marketPosition(address(position)).collateralAssets,
            marketPositionBefore.collateralAssets + uint128(collateralAmount)
        );
        assertGt(_marketPosition(address(position)).borrowShares, marketPositionBefore.borrowShares);
        assertGt(_stakedLpBalance(), 0);
        assertEq(IERC20(DUSD_MAINNET).allowance(address(position), VELORA_AUGUSTUS_V6_MAINNET), 0);
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertAddPositionLogged(collateralAmount, BORROW_ASSETS, logs);
        _assertSwapLogged(
            DUSD_MAINNET, FRXUSD_MAINNET, BORROW_ASSETS / 2, VELORA_AUGUSTUS_V6_MAINNET, _applySlippage(expectedFrxOut), logs
        );
    }

    function _addCollateralOnly(uint256 collateralAmount) internal {
        _fundUserWeth(collateralAmount);
        vm.prank(user);
        position.add(_encodeAdd(_addParams(collateralAmount, 0, dusdToFrxUsdSwapData, false)));
    }

    function _assertAddPositionLogged(uint256 expectedCollateral, uint256 expectedBorrow, Vm.Log[] memory logs)
        internal
    {
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.AddPosition.selector) {
                (uint256 loggedCollateral, uint256 loggedBorrow, uint256 lpStaked) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256));
                assertEq(loggedCollateral, expectedCollateral);
                assertEq(loggedBorrow, expectedBorrow);
                assertGt(lpStaked, 0);
                found = true;
            }
        }
        assertTrue(found);
    }

    function _assertSwapLogged(
        address sellToken,
        address buyToken,
        uint256 amountIn,
        address expectedSwapTarget,
        uint256 minAmountOut,
        Vm.Log[] memory logs
    ) internal {
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.Swap.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), sellToken);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), buyToken);
                (uint256 loggedAmountIn, address loggedSwapTarget, uint256 amountOut) =
                    abi.decode(logs[i].data, (uint256, address, uint256));
                assertEq(loggedAmountIn, amountIn);
                assertEq(loggedSwapTarget, expectedSwapTarget);
                assertGe(amountOut, minAmountOut);
                found = true;
            }
        }
        assertTrue(found);
    }
}
