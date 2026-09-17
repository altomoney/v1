// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {
    IProtocolFeeCollectorErrors,
    IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {ProtocolFeeCollectorCommon} from "./ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_WithdrawLiquidationFees_Test is ProtocolFeeCollectorCommon {
    function test_RevertWhen_Paused() public {
        _pause();
        (address[] memory markets, uint256[] memory amounts) = _singleMarket(address(borrowMarket), 1);

        vm.prank(COLLATERAL_OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        collector.withdrawLiquidationFees(markets, amounts);
    }

    function test_RevertWhen_CallerIsNotCollateralOperator() public {
        (address[] memory markets, uint256[] memory amounts) = _singleMarket(address(borrowMarket), 1);

        vm.prank(USER);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorUnauthorized.selector);
        collector.withdrawLiquidationFees(markets, amounts);
    }

    function test_RevertWhen_ArrayLengthsDoNotMatch() public {
        address[] memory markets = new address[](1);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(COLLATERAL_OPERATOR);
        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorLengthMismatch.selector);
        collector.withdrawLiquidationFees(markets, amounts);
    }

    function test_EmptyArraysCompleteWithoutWithdrawalEvent() public {
        address[] memory markets = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.recordLogs();
        vm.prank(COLLATERAL_OPERATOR);
        collector.withdrawLiquidationFees(markets, amounts);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.LiquidationFeesWithdrawn.selector, address(collector)), 0);
    }

    function test_RevertWhen_MarketIsNeitherBorrowNorMintMarket() public {
        (address[] memory markets, uint256[] memory amounts) = _singleMarket(address(borrowMarket), 1);

        vm.prank(COLLATERAL_OPERATOR);
        _expectInvalidSource(address(borrowMarket));
        collector.withdrawLiquidationFees(markets, amounts);
    }

    function test_RevertWhen_AllowlistedMarketBorrowTokenIsNotDusd() public {
        _allowBorrowMarket(address(wrongTokenBorrowMarket));
        (address[] memory markets, uint256[] memory amounts) = _singleMarket(address(wrongTokenBorrowMarket), 1);

        vm.prank(COLLATERAL_OPERATOR);
        _expectInvalidSource(address(wrongTokenBorrowMarket));
        collector.withdrawLiquidationFees(markets, amounts);
    }

    function test_WithdrawsFromBorrowMarketWithFixedArgumentsAndEmitsEvent() public {
        uint256 amount = 25 ether;
        _allowBorrowMarket(address(borrowMarket));
        _addCollectorCollateral(borrowMarket, amount);
        (address[] memory markets, uint256[] memory amounts) = _singleMarket(address(borrowMarket), amount);
        vm.expectCall(
            address(borrowMarket),
            abi.encodeCall(IMarketBase.removeCollateral, (amount, address(collector), MANUAL_SWAP_RECEIVER, bytes("")))
        );

        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.LiquidationFeesWithdrawn(address(borrowMarket), MANUAL_SWAP_RECEIVER, amount);

        vm.prank(COLLATERAL_OPERATOR);
        collector.withdrawLiquidationFees(markets, amounts);

        Position memory collectorPosition = borrowMarket.position(address(collector));
        assertEq(collectorPosition.collateralAssets, 0);
        assertEq(collateralToken.balanceOf(MANUAL_SWAP_RECEIVER), amount);
    }

    function test_WithdrawsFromMintMarketWithFixedArgumentsAndEmitsEvent() public {
        uint256 amount = 30 ether;
        _allowMintMarket(address(mintMarket));
        _addCollectorCollateral(mintMarket, amount);
        (address[] memory markets, uint256[] memory amounts) = _singleMarket(address(mintMarket), amount);
        vm.expectCall(
            address(mintMarket),
            abi.encodeCall(IMarketBase.removeCollateral, (amount, address(collector), MANUAL_SWAP_RECEIVER, bytes("")))
        );

        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.LiquidationFeesWithdrawn(address(mintMarket), MANUAL_SWAP_RECEIVER, amount);

        vm.prank(COLLATERAL_OPERATOR);
        collector.withdrawLiquidationFees(markets, amounts);

        Position memory collectorPosition = mintMarket.position(address(collector));
        assertEq(collectorPosition.collateralAssets, 0);
        assertEq(collateralToken.balanceOf(MANUAL_SWAP_RECEIVER), amount);
    }

    function test_WithdrawsMultipleMarketsInOrderToFixedReceiverAndEmitsForEach() public {
        uint256 borrowAmount = 10 ether;
        uint256 mintAmount = 20 ether;
        _allowBorrowMarket(address(borrowMarket));
        _allowMintMarket(address(mintMarket));
        _addCollectorCollateral(borrowMarket, borrowAmount);
        _addCollectorCollateral(mintMarket, mintAmount);

        address[] memory markets = new address[](2);
        markets[0] = address(borrowMarket);
        markets[1] = address(mintMarket);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = borrowAmount;
        amounts[1] = mintAmount;

        vm.recordLogs();
        vm.prank(COLLATERAL_OPERATOR);
        collector.withdrawLiquidationFees(markets, amounts);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 withdrawalIndex;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(collector) && logs[i].topics.length != 0
                    && logs[i].topics[0] == IProtocolFeeCollectorEvents.LiquidationFeesWithdrawn.selector
            ) {
                address emittedMarket = address(uint160(uint256(logs[i].topics[1])));
                address emittedReceiver = address(uint160(uint256(logs[i].topics[2])));
                uint256 emittedAmount = abi.decode(logs[i].data, (uint256));
                assertEq(emittedMarket, markets[withdrawalIndex]);
                assertEq(emittedReceiver, MANUAL_SWAP_RECEIVER);
                assertEq(emittedAmount, amounts[withdrawalIndex]);
                withdrawalIndex++;
            }
        }

        assertEq(withdrawalIndex, 2);
        assertEq(collateralToken.balanceOf(MANUAL_SWAP_RECEIVER), borrowAmount + mintAmount);
        assertEq(borrowMarket.position(address(collector)).collateralAssets, 0);
        assertEq(mintMarket.position(address(collector)).collateralAssets, 0);
    }
}
