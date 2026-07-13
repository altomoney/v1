// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {IAltoVault} from "@alto/lending/interfaces/IAltoVault.sol";
import {MarketConfig} from "@alto/lending/libraries/PendingLib.sol";
import {
    ScheduleUpdateMethRethMintCeilingsScript,
    MarketCeilingUpdate,
    VaultCapUpdate,
    TreasurySafeTx
} from "../../script/ScheduleUpdateMethRethMintCeilings.s.sol";

contract ScheduleUpdateMethRethMintCeilingsTest is Test {
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    address constant TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant DUSD_VAULT = 0x6954785783c6EE90400fA715E591fBbA0D0Bd749;
    address constant METH_MARKET = 0xF897188DCd300Fa80a2f7f0f0290F9eF64F2D47b;
    address constant RETH_MARKET = 0xc0E2DdB06bB034c1F980531EC5CAd944D71AfFbf;

    address constant SYRUP_USDC_BORROW_MARKET = 0x33B24510233281350bF8679A7c427d04db0ed208;
    address constant SUSDE_BORROW_MARKET = 0x133cf03d2A7a87B9239b1a3a8Dd62f3f27c46788;
    address constant PAXG_BORROW_MARKET = 0x99f538Ec7c840197DcAf30A25B635482ba9e8817;
    address constant WBTC_BORROW_MARKET = 0xefd78a5970a43e25b30426C3952065217c55e5E4;
    address constant CBBTC_BORROW_MARKET = 0xaE4f2B998783e2041E87E08Da73985e4E0420159;

    uint256 constant NEW_VAULT_SUPPLY_CAP = 40_000 ether;
    uint256 constant EXPECTED_CURRENT_VAULT_SUPPLY_CAP = 80_000 ether;

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

    function test_computeVaultCapUpdates_expectsEightyKToFortyK() public view {
        VaultCapUpdate[] memory updates = script.computeVaultCapUpdates();

        assertEq(updates.length, 5);
        assertEq(updates[0].market, SYRUP_USDC_BORROW_MARKET);
        assertEq(updates[1].market, SUSDE_BORROW_MARKET);
        assertEq(updates[2].market, PAXG_BORROW_MARKET);
        assertEq(updates[3].market, WBTC_BORROW_MARKET);
        assertEq(updates[4].market, CBBTC_BORROW_MARKET);

        for (uint256 i = 0; i < updates.length; ++i) {
            assertEq(updates[i].currentCap, EXPECTED_CURRENT_VAULT_SUPPLY_CAP);
            assertEq(updates[i].newCap, NEW_VAULT_SUPPLY_CAP);
        }
    }

    function test_submitVaultSupplyCaps() public {
        VaultCapUpdate[] memory updates = script.computeVaultCapUpdates();
        TreasurySafeTx[] memory txs = script.getVaultCapSafeTransactions(updates);

        assertEq(txs.length, 5);
        assertEq(IAltoVault(DUSD_VAULT).curator(), TIMELOCK_ADMIN);

        vm.startPrank(TIMELOCK_ADMIN);
        for (uint256 i = 0; i < txs.length; ++i) {
            assertEq(txs[i].to, DUSD_VAULT);
            (bool success,) = txs[i].to.call(txs[i].data);
            assertTrue(success, "submitCap failed");
        }
        vm.stopPrank();

        for (uint256 i = 0; i < updates.length; ++i) {
            MarketConfig memory config = IAltoVault(DUSD_VAULT).config(updates[i].market);
            assertEq(uint256(config.cap), NEW_VAULT_SUPPLY_CAP, "vault supply cap should be 40k");
            assertTrue(config.enabled, "market should remain enabled");
        }
    }

    function _assertUpdate(address market, MarketCeilingUpdate memory update) internal view {
        uint256 borrowed = IMarket(market).totalBorrowed().assets;
        uint256 expectedCeiling = borrowed + (borrowed * 500 / 10_000);

        assertEq(update.market, market);
        assertEq(update.borrowedAssets, borrowed);
        assertEq(update.newCeiling, expectedCeiling);
    }
}
