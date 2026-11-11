// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {
    FeeSourceType,
    IProtocolFeeCollectorEvents,
    ProtocolFeeCollectorInitParams
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {DUSDFlashMinter} from "@alto/usm/DUSDFlashMinter.sol";
import {FlashFee} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketProtocolFeeCollectorTest is ConvexCreditLineCommon {
    ProtocolFeeCollector internal collector;

    function setUp() public override {
        super.setUp();
        MarketRegistry registry = new MarketRegistry(OWNER);
        UsmRegistry usmRegistry = new UsmRegistry(OWNER);
        DUSDFlashMinter flashMinter =
            new DUSDFlashMinter(address(borrowToken), FEE_RECIPIENT, FlashFee({minFlashFee: 0, maxFlashFee: 0}), OWNER);
        ProtocolFeeCollectorInitParams memory params = ProtocolFeeCollectorInitParams({
            admin: OWNER,
            collateralOperator: OWNER,
            pauser: OWNER,
            dusd: address(borrowToken),
            marketRegistry: address(registry),
            usmRegistry: address(usmRegistry),
            flashMinter: address(flashMinter),
            treasury: RECEIVER,
            manualSwapReceiver: RECEIVER,
            rewardsBps: 0,
            minimumRewardAmount: 1
        });
        collector = ProtocolFeeCollector(
            address(
                new ERC1967Proxy(
                    address(new ProtocolFeeCollector()), abi.encodeCall(ProtocolFeeCollector.initialize, (params))
                )
            )
        );
        vm.startPrank(OWNER);
        registry.addMintMarket(address(market));
        market.setFeeRecipient(address(collector));
        flashMinter.updateFeeRecipient(address(collector));
        vm.stopPrank();
        _setOpeningFee(0.1 ether);
        _openPosition(1_000 ether, 100 ether);
    }

    function test_HarvestRecordsOnlyReceivedShareDespiteGrossClaimReturnValue() external {
        assertEq(market.claimInterest(4 ether), 4 ether);
        assertEq(borrowToken.balanceOf(address(collector)), 2.8 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 1.2 ether);

        vm.expectEmit(address(collector));
        emit IProtocolFeeCollectorEvents.Harvested(FeeSourceType.MINT_MARKET, address(market), 4.2 ether);
        _harvest();

        assertEq(borrowToken.balanceOf(address(collector)), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
        assertEq(market.claimableFeesAssets(), 0);
    }

    function test_FullTreasuryShareHarvestSucceedsWithZeroReceived() external {
        vm.prank(OWNER);
        market.setTreasuryInterestBps(10_000);

        vm.expectEmit(address(collector));
        emit IProtocolFeeCollectorEvents.Harvested(FeeSourceType.MINT_MARKET, address(market), 0);
        _harvest();

        assertEq(borrowToken.balanceOf(address(collector)), 0);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 10 ether);
        assertEq(market.claimableFeesAssets(), 0);
    }

    function test_DistributeUsesOnlyCollectorBalanceAfterAutomaticHarvest() external {
        vm.expectEmit(address(collector));
        emit IProtocolFeeCollectorEvents.Harvested(FeeSourceType.MINT_MARKET, address(market), 7 ether);
        vm.expectEmit(address(collector));
        emit IProtocolFeeCollectorEvents.Distributed(7 ether, 7 ether, 0);
        collector.distribute();

        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
        assertEq(borrowToken.balanceOf(RECEIVER), 7 ether);
        assertEq(borrowToken.balanceOf(address(collector)), 0);
        assertEq(market.claimableFeesAssets(), 0);
    }

    function test_SecondMintFailureRollsBackHarvestAndAccrualAndAllowsRetry() external {
        AccountingState memory beforeState = _state();
        uint256 supplyBefore = borrowToken.totalSupply();
        (uint256 mintedBefore,) = borrowToken.minterConfig(address(market));
        _mockAccrual(5 ether, 1);
        vm.mockCallRevert(
            address(borrowToken), abi.encodeCall(borrowToken.mint, (REWARD_RECIPIENT, 4.5 ether)), "MINT_REVERTED"
        );
        vm.expectCall(address(borrowToken), abi.encodeCall(borrowToken.mint, (address(collector), 10.5 ether)));

        vm.expectEmit(address(collector));
        emit IProtocolFeeCollectorEvents.HarvestingFailed(FeeSourceType.MINT_MARKET, address(market));
        _harvest();

        _assertUnchanged(beforeState);
        assertEq(borrowToken.balanceOf(address(collector)), 0);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 0);
        assertEq(borrowToken.totalSupply(), supplyBefore);
        (uint256 mintedAfter,) = borrowToken.minterConfig(address(market));
        assertEq(mintedAfter, mintedBefore);

        vm.clearMockedCalls();
        _mockAccrual(5 ether, 1);
        vm.expectEmit(address(collector));
        emit IProtocolFeeCollectorEvents.Harvested(FeeSourceType.MINT_MARKET, address(market), 10.5 ether);
        _harvest();
        assertEq(borrowToken.balanceOf(address(collector)), 10.5 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 4.5 ether);
        assertEq(market.claimableFeesAssets(), 0);
    }

    function _harvest() private {
        FeeSourceType[] memory sourceTypes = new FeeSourceType[](1);
        sourceTypes[0] = FeeSourceType.MINT_MARKET;
        address[] memory sources = new address[](1);
        sources[0] = address(market);
        collector.harvest(sourceTypes, sources);
    }
}
