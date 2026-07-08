// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {
    ScheduleUpdateMethRethMintCeilingsScript,
    MarketCeilingUpdate
} from "../../script/ScheduleUpdateMethRethMintCeilings.s.sol";

contract ScheduleUpdateMethRethMintCeilingsTest is Test {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant METH_MARKET = 0xF897188DCd300Fa80a2f7f0f0290F9eF64F2D47b;
    address constant RETH_MARKET = 0xc0E2DdB06bB034c1F980531EC5CAd944D71AfFbf;

    ScheduleUpdateMethRethMintCeilingsScript internal script;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));
        script = new ScheduleUpdateMethRethMintCeilingsScript();
    }

    function test_updateMethRethMintCeilings() public {
        MarketCeilingUpdate[] memory updates = script.computeUpdates();
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = script.buildBatch(updates);
        uint256 delay = TimelockController(payable(TIMELOCK)).getMinDelay();

        assertEq(updates.length, 2);
        assertEq(targets.length, 4);

        vm.prank(TIMELOCK_ADMIN);
        TimelockController(payable(TIMELOCK)).scheduleBatch(
            targets, values, payloads, bytes32(0), bytes32(0), delay
        );

        vm.warp(block.timestamp + delay + 1);

        vm.prank(TIMELOCK_ADMIN);
        TimelockController(payable(TIMELOCK)).executeBatch(
            targets, values, payloads, bytes32(0), bytes32(0)
        );

        for (uint256 i = 0; i < updates.length; ++i) {
            address market = updates[i].market;
            uint256 expectedCeiling = updates[i].newCeiling;

            assertEq(
                IMarket(market).totalSupply().assets,
                expectedCeiling,
                "market debt ceiling should match borrowed + 5% buffer"
            );

            (, uint256 minterCeiling) = IDUSD(DUSD).minterConfig(market);
            assertEq(minterCeiling, expectedCeiling, "DUSD minter ceiling should match market debt ceiling");
        }
    }

    function test_computeUpdates_usesBorrowedPlusFivePercentBuffer() public view {
        MarketCeilingUpdate[] memory updates = script.computeUpdates();

        _assertUpdate(METH_MARKET, updates[0]);
        _assertUpdate(RETH_MARKET, updates[1]);
    }

    function _assertUpdate(address market, MarketCeilingUpdate memory update) internal view {
        uint256 borrowed = IMarket(market).totalBorrowed().assets;
        uint256 expectedCeiling = borrowed + (borrowed * 500 / 10_000);

        assertEq(update.market, market);
        assertEq(update.borrowedAssets, borrowed);
        assertEq(update.newCeiling, expectedCeiling);
    }
}
