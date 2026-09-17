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

    function test_EmptyArraysCompleteWithoutHarvestEvents() public {
        FeeSourceType[] memory sourceTypes = new FeeSourceType[](0);
        address[] memory sources = new address[](0);

        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Harvested.selector, address(collector)), 0);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.HarvestingFailed.selector, address(collector)), 0);
    }

    function test_UnregisteredBorrowMarketEmitsHarvestingFailedAndSkips() public {
        _assertHarvestSkipped(FeeSourceType.BORROW_MARKET, address(borrowMarket));
    }

    function test_BorrowMarketWithWrongTokenEmitsHarvestingFailedAndSkips() public {
        _allowBorrowMarket(address(wrongTokenBorrowMarket));
        _assertHarvestSkipped(FeeSourceType.BORROW_MARKET, address(wrongTokenBorrowMarket));
    }

    function test_PausedBorrowMarketEmitsHarvestingFailedAndSkips() public {
        _allowBorrowMarket(address(borrowMarket));
        vm.prank(PAUSER);
        borrowMarket.pause(PAUSE_TYPE, true);
        vm.mockCallRevert(
            address(borrowMarket),
            abi.encodeWithSelector(IMarketBase.accrueInterest.selector),
            abi.encodeWithSignature("Error(string)", "should not accrue")
        );

        _assertHarvestSkipped(FeeSourceType.BORROW_MARKET, address(borrowMarket));
    }

    function test_BorrowMarketWrongFeeRecipientWithNoPositionEmitsHarvestingFailedAndSkipsRemoval() public {
        _allowBorrowMarket(address(borrowMarket));
        vm.prank(ADMIN);
        borrowMarket.setFeeRecipient(TREASURY);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));

        vm.expectCall(address(borrowMarket), abi.encodeWithSelector(IMarketBase.accrueInterest.selector));
        _expectHarvestingFailed(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Harvested.selector, address(collector)), 0);
        assertEq(_countLogs(logs, IMarketEvents.RemoveSupply.selector, address(borrowMarket)), 0);
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

    function test_BorrowMarketHarvestsExistingPositionAfterFeeRecipientChanges() public {
        _allowBorrowMarket(address(borrowMarket));
        uint256 supplyShares = _supplyBorrowMarket(SUPPLY_ASSETS);
        assertEq(borrowMarket.position(address(collector)).supplyShares, supplyShares);
        vm.prank(ADMIN);
        borrowMarket.setFeeRecipient(TREASURY);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        _expectHarvested(FeeSourceType.BORROW_MARKET, address(borrowMarket), SUPPLY_ASSETS);

        collector.harvest(sourceTypes, sources);

        assertEq(borrowMarket.position(address(collector)).supplyShares, 0);
        assertEq(dusd.balanceOf(address(collector)), SUPPLY_ASSETS);
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

    function test_UnregisteredMintMarketEmitsHarvestingFailedAndSkips() public {
        _assertHarvestSkipped(FeeSourceType.MINT_MARKET, address(mintMarket));
    }

    function test_MintMarketWithWrongTokenEmitsHarvestingFailedAndSkips() public {
        _allowMintMarket(address(wrongTokenMintMarket));
        _assertHarvestSkipped(FeeSourceType.MINT_MARKET, address(wrongTokenMintMarket));
    }

    function test_MintMarketWrongFeeRecipientEmitsHarvestingFailedWithoutClaiming() public {
        _allowMintMarket(address(mintMarket));
        uint256 claimableFees = _generateMintMarketFees(100 ether);
        vm.prank(ADMIN);
        mintMarket.setFeeRecipient(TREASURY);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.MINT_MARKET, address(mintMarket));
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);

        _expectHarvestingFailed(FeeSourceType.MINT_MARKET, address(mintMarket));
        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(AltoMintMarket(address(mintMarket)).claimableFeesAssets(), claimableFees);
        assertEq(dusd.balanceOf(TREASURY), treasuryBalanceBefore);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Harvested.selector, address(collector)), 0);
    }

    function test_PausedMintMarketEmitsHarvestingFailedWithoutClaiming() public {
        _allowMintMarket(address(mintMarket));
        uint256 claimableFees = _generateMintMarketFees(100 ether);
        vm.prank(PAUSER);
        mintMarket.pause(PAUSE_TYPE, true);
        vm.mockCallRevert(
            address(mintMarket),
            abi.encodeWithSelector(IMarketBase.accrueInterest.selector),
            abi.encodeWithSignature("Error(string)", "should not accrue")
        );

        _assertHarvestSkipped(FeeSourceType.MINT_MARKET, address(mintMarket));

        assertEq(AltoMintMarket(address(mintMarket)).claimableFeesAssets(), claimableFees);
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

    function test_UnregisteredUsmEmitsHarvestingFailedAndSkips() public {
        _assertHarvestSkipped(FeeSourceType.USM, address(usm));
    }

    function test_UsmWithWrongStableTokenEmitsHarvestingFailedAndSkips() public {
        _allowUsm(address(wrongTokenUsm));
        _assertHarvestSkipped(FeeSourceType.USM, address(wrongTokenUsm));
    }

    function test_UsmWrongFeeRecipientEmitsHarvestingFailedWithoutDistributing() public {
        _allowUsm(address(usm));
        uint256 accruedFees = _generateUsmFees(100e6);
        vm.prank(ADMIN);
        usm.updateFeeRecipient(TREASURY);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) = _singleSource(FeeSourceType.USM, address(usm));
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);

        _expectHarvestingFailed(FeeSourceType.USM, address(usm));
        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(usm.getAccruedFees(), accruedFees);
        assertEq(dusd.balanceOf(TREASURY), treasuryBalanceBefore);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Harvested.selector, address(collector)), 0);
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

    function test_FrozenUsmStillDistributesFeesAndEmitsReceivedAmount() public {
        _allowUsm(address(usm));
        uint256 feeAmount = _generateUsmFees(100e6);
        vm.startPrank(ADMIN);
        usm.grantRole(usm.SWAP_FREEZER_ROLE(), ADMIN);
        usm.setSwapFreeze(true);
        vm.stopPrank();
        (FeeSourceType[] memory sourceTypes, address[] memory sources) = _singleSource(FeeSourceType.USM, address(usm));

        vm.expectCall(
            address(usm), abi.encodeWithSelector(IStableTokenFacilitator.distributeFeesToFeeRecipient.selector)
        );
        _expectHarvested(FeeSourceType.USM, address(usm), feeAmount);
        collector.harvest(sourceTypes, sources);

        assertEq(usm.getAccruedFees(), 0);
        assertEq(dusd.balanceOf(address(collector)), feeAmount);
    }

    function test_SeizedUsmStillCallsFeeDistributionAndEmitsHarvested() public {
        _allowUsm(address(usm));
        vm.startPrank(ADMIN);
        usm.grantRole(usm.LIQUIDATOR_ROLE(), ADMIN);
        usm.seize();
        vm.stopPrank();
        (FeeSourceType[] memory sourceTypes, address[] memory sources) = _singleSource(FeeSourceType.USM, address(usm));

        vm.expectCall(
            address(usm), abi.encodeWithSelector(IStableTokenFacilitator.distributeFeesToFeeRecipient.selector)
        );
        _expectHarvested(FeeSourceType.USM, address(usm), 0);
        collector.harvest(sourceTypes, sources);

        assertEq(dusd.balanceOf(address(collector)), 0);
    }

    function test_UnconfiguredFlashMinterEmitsHarvestingFailedAndSkips() public {
        _assertHarvestSkipped(FeeSourceType.FLASH_MINTER, address(wrongTokenFlashMinter));
    }

    function test_FlashMinterWithWrongDusdEmitsHarvestingFailedAndSkips() public {
        vm.prank(ADMIN);
        collector.setFlashMinter(address(wrongTokenFlashMinter));
        _assertHarvestSkipped(FeeSourceType.FLASH_MINTER, address(wrongTokenFlashMinter));
    }

    function test_FlashMinterWrongFeeRecipientEmitsHarvestingFailedWithoutDistributing() public {
        uint256 accruedFees = _generateFlashFees(100 ether);
        vm.prank(ADMIN);
        flashMinter.updateFeeRecipient(TREASURY);
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.FLASH_MINTER, address(flashMinter));
        uint256 treasuryBalanceBefore = dusd.balanceOf(TREASURY);

        _expectHarvestingFailed(FeeSourceType.FLASH_MINTER, address(flashMinter));
        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(dusd.balanceOf(address(flashMinter)), accruedFees);
        assertEq(dusd.balanceOf(TREASURY), treasuryBalanceBefore);
        assertEq(dusd.balanceOf(address(collector)), 0);
        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Harvested.selector, address(collector)), 0);
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

    function test_MultipleSourcesContinueAfterValidationFailureAndEmitInArrayOrder() public {
        _allowUsm(address(usm));
        uint256 usmFee = _generateUsmFees(100e6);

        FeeSourceType[] memory sourceTypes = new FeeSourceType[](2);
        sourceTypes[0] = FeeSourceType.MINT_MARKET;
        sourceTypes[1] = FeeSourceType.USM;
        address[] memory sources = new address[](2);
        sources[0] = address(mintMarket);
        sources[1] = address(usm);

        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 eventIndex;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(collector) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == IProtocolFeeCollectorEvents.HarvestingFailed.selector) {
                assertEq(eventIndex++, 0);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), address(mintMarket));
            } else if (logs[i].topics[0] == IProtocolFeeCollectorEvents.Harvested.selector) {
                assertEq(eventIndex++, 1);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), address(usm));
            }
        }
        assertEq(eventIndex, 2);
        assertEq(dusd.balanceOf(address(collector)), usmFee);
    }

    function test_RevertWhen_ValidSourceExecutionReverts() public {
        _allowBorrowMarket(address(borrowMarket));
        (FeeSourceType[] memory sourceTypes, address[] memory sources) =
            _singleSource(FeeSourceType.BORROW_MARKET, address(borrowMarket));
        bytes memory reason = abi.encodeWithSignature("Error(string)", "accrual failed");
        vm.mockCallRevert(address(borrowMarket), abi.encodeCall(IMarketBase.accrueInterest, ()), reason);

        vm.expectRevert(reason);
        collector.harvest(sourceTypes, sources);
    }

    function _assertHarvestSkipped(FeeSourceType sourceType, address source) internal {
        (FeeSourceType[] memory sourceTypes, address[] memory sources) = _singleSource(sourceType, source);
        _expectHarvestingFailed(sourceType, source);
        vm.recordLogs();
        collector.harvest(sourceTypes, sources);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_countLogs(logs, IProtocolFeeCollectorEvents.Harvested.selector, address(collector)), 0);
    }
}
