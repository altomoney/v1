// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {
    FeeSourceType,
    IProtocolFeeCollectorErrors,
    IProtocolFeeCollectorEvents
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {IMarket, IMarketBase, IMarketEvents, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IStableTokenFacilitator} from "@alto/usm/interfaces/IStableTokenFacilitator.sol";
import {ProtocolFeeCollectorCommon} from "./ProtocolFeeCollectorCommon.t.sol";

contract ProtocolFeeCollector_Harvest_Test is ProtocolFeeCollectorCommon {
    uint256 internal constant SUPPLY_ASSETS = 100 ether;
    uint256 internal constant BORROW_RATE = 0.04 ether / uint256(365 days);

    function test_RevertWhen_Paused() public {
        _pause();
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));

        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        collector.harvest(sourceTypes, sources);
    }

    function test_RevertWhen_ArrayLengthsDoNotMatch() public {
        FeeSourceType[] memory sourceTypes = new FeeSourceType[](1);
        address[] memory sources = new address[](0);

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorLengthMismatch.selector);
        collector.harvest(sourceTypes, sources);
    }

    function test_EmptyArraysCompleteWithoutHarvestedEvent() public {
        FeeSourceType[] memory sourceTypes = new FeeSourceType[](0);
        address[] memory sources = new address[](0);

        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Harvested.selector, address(collector)), 0);
    }

    function test_RevertWhen_BorrowMarketIsNotAllowlisted() public {
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidSource.selector);
        collector.harvest(sourceTypes, sources);
    }

    function test_RevertWhen_BorrowMarketTokenIsNotDusd() public {
        _allowBorrowMarket(address(wrongTokenBorrowMarket));
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(wrongTokenBorrowMarket));

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidSource.selector);
        collector.harvest(sourceTypes, sources);
    }

    function test_BorrowMarketWithZeroSharesSkipsRemovalAfterAccrual() public {
        _allowBorrowMarket(address(borrowMarket));
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        vm.expectCall(address(borrowMarket), abi.encodeWithSelector(IMarketBase.accrueInterest.selector));
        _expectHarvested(FeeSourceType.BORROW_MARKET, address(borrowMarket), 0);

        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IMarketEvents.RemoveSupply.selector, address(borrowMarket)), 0);
        Position memory position = borrowMarket.position(address(collector));
        assertEq(position.supplyShares, 0);
    }

    function test_BorrowMarketHarvestIncludesFeeSharesCreatedByAccrual() public {
        uint256 borrowAssets = SUPPLY_ASSETS / 2;
        _allowBorrowMarket(address(borrowMarket));

        dusd.mint(address(this), SUPPLY_ASSETS);
        dusd.approve(address(borrowMarket), SUPPLY_ASSETS);
        borrowMarket.addSupply(SUPPLY_ASSETS, 0, USER);
        _borrowFromMarket(borrowMarket, borrowAssets);

        FixedRateIrm irm = new FixedRateIrm(BORROW_RATE, ADMIN);
        vm.startPrank(ADMIN);
        AltoBorrowMarket(address(borrowMarket)).setInterestFee(0.1 ether, true);
        borrowMarket.setIrm(address(irm), false);
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days);

        assertEq(borrowMarket.position(address(collector)).supplyShares, 0);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        vm.expectCall(address(borrowMarket), abi.encodeCall(IMarketBase.accrueInterest, ()));

        collector.harvest(sourceTypes, sources);

        assertGt(dusd.balanceOf(address(collector)), 0, "newly accrued fee shares were not harvested");
        assertEq(borrowMarket.position(address(collector)).supplyShares, 0);
    }

    function test_BorrowMarketSkipsSupplySharesThatConvertToZeroAssets() public {
        _allowBorrowMarket(address(borrowMarket));
        _supplyBorrowMarketShares(1);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        _expectHarvested(FeeSourceType.BORROW_MARKET, address(borrowMarket), 0);

        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IMarketEvents.RemoveSupply.selector, address(borrowMarket)), 0);
        Position memory position = borrowMarket.position(address(collector));
        assertEq(position.supplyShares, 1);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_BorrowMarketSkipsRemovalWhenAvailableLiquidityIsZero() public {
        _allowBorrowMarket(address(borrowMarket));
        uint256 supplyShares = _supplyBorrowMarket(SUPPLY_ASSETS);
        _borrowFromMarket(borrowMarket, SUPPLY_ASSETS);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        _expectHarvested(FeeSourceType.BORROW_MARKET, address(borrowMarket), 0);

        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IMarketEvents.RemoveSupply.selector, address(borrowMarket)), 0);
        Position memory position = borrowMarket.position(address(collector));
        assertEq(position.supplyShares, supplyShares);
        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_BorrowMarketCapsAvailableLiquidityToTokenBalance() public {
        uint256 marketBalance = 40 ether;
        _allowBorrowMarket(address(borrowMarket));
        _supplyBorrowMarket(SUPPLY_ASSETS);
        vm.prank(address(borrowMarket));
        dusd.transfer(makeAddr("LiquiditySink"), SUPPLY_ASSETS - marketBalance);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        vm.expectCall(
            address(borrowMarket),
            abi.encodeCall(IMarketBase.removeSupply, (marketBalance, 0, address(collector), address(collector)))
        );
        _expectHarvested(FeeSourceType.BORROW_MARKET, address(borrowMarket), marketBalance);

        collector.harvest(sourceTypes, sources);

        assertEq(dusd.balanceOf(address(collector)), marketBalance);
        assertEq(dusd.balanceOf(address(borrowMarket)), 0);
    }

    function test_BorrowMarketRemovesFullShareBalanceWhenLiquidityIsSufficient() public {
        _allowBorrowMarket(address(borrowMarket));
        uint256 supplyShares = _supplyBorrowMarket(SUPPLY_ASSETS);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        vm.expectCall(
            address(borrowMarket),
            abi.encodeCall(IMarketBase.removeSupply, (0, supplyShares, address(collector), address(collector)))
        );
        _expectHarvested(FeeSourceType.BORROW_MARKET, address(borrowMarket), SUPPLY_ASSETS);

        collector.harvest(sourceTypes, sources);

        Position memory position = borrowMarket.position(address(collector));
        assertEq(position.supplyShares, 0);
        assertEq(dusd.balanceOf(address(collector)), SUPPLY_ASSETS);
        assertEq(dusd.balanceOf(address(borrowMarket)), 0);
    }

    function test_BorrowMarketRemovesOnlyAvailableAssetsWhenLiquidityIsConstrained() public {
        uint256 availableLiquidity = 50 ether;
        _allowBorrowMarket(address(borrowMarket));
        uint256 initialShares = _supplyBorrowMarket(SUPPLY_ASSETS);
        _borrowFromMarket(borrowMarket, SUPPLY_ASSETS - availableLiquidity);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        vm.expectCall(
            address(borrowMarket),
            abi.encodeCall(IMarketBase.removeSupply, (availableLiquidity, 0, address(collector), address(collector)))
        );
        _expectHarvested(FeeSourceType.BORROW_MARKET, address(borrowMarket), availableLiquidity);

        collector.harvest(sourceTypes, sources);

        Position memory position = borrowMarket.position(address(collector));
        assertLt(position.supplyShares, initialShares);
        assertGt(position.supplyShares, 0);
        assertEq(dusd.balanceOf(address(collector)), availableLiquidity);
        assertEq(dusd.balanceOf(address(borrowMarket)), 0);
    }

    function test_RevertWhen_MintMarketIsNotAllowlisted() public {
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.MINT_MARKET, address(mintMarket));

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidSource.selector);
        collector.harvest(sourceTypes, sources);
    }

    function test_RevertWhen_MintMarketTokenIsNotDusd() public {
        _allowMintMarket(address(wrongTokenMintMarket));
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.MINT_MARKET, address(wrongTokenMintMarket));

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidSource.selector);
        collector.harvest(sourceTypes, sources);
    }

    function test_ValidMintMarketAccruesThenClaimsAllInterestAndEmitsReceivedAmount() public {
        _allowMintMarket(address(mintMarket));
        uint256 existingFees = _generateMintMarketFees(100 ether);
        FixedRateIrm irm = new FixedRateIrm(BORROW_RATE, ADMIN);
        vm.prank(ADMIN);
        mintMarket.setIrm(address(irm), false);
        vm.warp(block.timestamp + 365 days);

        (uint256 expectedInterest,) =
            irm.updateInterestRateView(mintMarket.totalSupply().assets, mintMarket.totalBorrowed().assets);
        uint256 expectedFees = existingFees + expectedInterest;
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.MINT_MARKET, address(mintMarket));
        vm.expectCall(address(mintMarket), abi.encodeCall(IMarketBase.accrueInterest, ()));
        vm.expectCall(address(mintMarket), abi.encodeCall(AltoMintMarket.claimInterest, (0)));
        _expectHarvested(FeeSourceType.MINT_MARKET, address(mintMarket), expectedFees);

        collector.harvest(sourceTypes, sources);

        assertEq(AltoMintMarket(address(mintMarket)).claimableFeesAssets(), 0);
        assertEq(dusd.balanceOf(address(collector)), expectedFees);
    }

    function test_RevertWhen_UsmIsNotAllowlisted() public {
        (FeeSourceType[] memory sourceTypes, address[] memory sources) = _singleSource(FeeSourceType.USM, address(usm));

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidSource.selector);
        collector.harvest(sourceTypes, sources);
    }

    function test_RevertWhen_UsmStableTokenIsNotDusd() public {
        _allowUsm(address(wrongTokenUsm));
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.USM, address(wrongTokenUsm));

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidSource.selector);
        collector.harvest(sourceTypes, sources);
    }

    function test_ValidUsmDistributesFeesAndEmitsReceivedAmount() public {
        _allowUsm(address(usm));
        uint256 feeAmount = _generateUsmFees(100e6);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) = _singleSource(FeeSourceType.USM, address(usm));
        vm.expectCall(
            address(usm), abi.encodeWithSelector(IStableTokenFacilitator.distributeFeesToFeeRecipient.selector)
        );
        _expectHarvested(FeeSourceType.USM, address(usm), feeAmount);

        collector.harvest(sourceTypes, sources);

        assertEq(usm.getAccruedFees(), 0);
        assertEq(dusd.balanceOf(address(collector)), feeAmount);
    }

    function test_RevertWhen_FlashMinterIsNotConfiguredSource() public {
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.FLASH_MINTER, address(wrongTokenFlashMinter));

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidSource.selector);
        collector.harvest(sourceTypes, sources);
    }

    function test_RevertWhen_FlashMinterDusdDoesNotMatchConfiguredDusd() public {
        vm.prank(ADMIN);
        collector.setFlashMinter(address(wrongTokenFlashMinter));
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.FLASH_MINTER, address(wrongTokenFlashMinter));

        vm.expectRevert(IProtocolFeeCollectorErrors.ProtocolFeeCollectorInvalidSource.selector);
        collector.harvest(sourceTypes, sources);
    }

    function test_ValidFlashMinterDistributesFeesAndEmitsReceivedAmount() public {
        uint256 feeAmount = _generateFlashFees(100 ether);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.FLASH_MINTER, address(flashMinter));
        vm.expectCall(
            address(flashMinter), abi.encodeWithSelector(IStableTokenFacilitator.distributeFeesToFeeRecipient.selector)
        );
        _expectHarvested(FeeSourceType.FLASH_MINTER, address(flashMinter), feeAmount);

        collector.harvest(sourceTypes, sources);

        assertEq(dusd.balanceOf(address(flashMinter)), 0);
        assertEq(dusd.balanceOf(address(collector)), feeAmount);
    }

    function test_AnyCallerHarvestsMultipleSourcesInArrayOrderAndEmitsForEach() public {
        _allowMintMarket(address(mintMarket));
        _allowUsm(address(usm));
        uint256 mintFee = _generateMintMarketFees(100 ether);
        uint256 usmFee = _generateUsmFees(100e6);

        FeeSourceType[] memory sourceTypes = new FeeSourceType[](2);
        sourceTypes[0] = FeeSourceType.MINT_MARKET;
        sourceTypes[1] = FeeSourceType.USM;
        address[] memory sources = new address[](2);
        sources[0] = address(mintMarket);
        sources[1] = address(usm);

        vm.recordLogs();
        vm.prank(USER);
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 harvestedIndex;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(collector) && logs[i].topics.length != 0
                    && logs[i].topics[0] == IProtocolFeeCollectorEvents.Harvested.selector
            ) {
                address emittedSource = address(uint160(uint256(logs[i].topics[2])));
                assertEq(emittedSource, sources[harvestedIndex]);
                harvestedIndex++;
            }
        }
        assertEq(harvestedIndex, 2);
        assertEq(dusd.balanceOf(address(collector)), mintFee + usmFee);
    }
}
