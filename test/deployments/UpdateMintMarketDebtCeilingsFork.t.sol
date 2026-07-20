// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {
    UpdateMintMarketDebtCeilingsScript,
    IAltoMintMarketLike,
    ILiquidationEngineLike
} from "../../script/UpdateMintMarketDebtCeilings.s.sol";

/// @dev Extra reads on the mint market not covered by the script interface.
interface IMintMarketExtra {
    function totalBorrowed() external view returns (uint128 assets, uint128 shares);
    function owner() external view returns (address);
}

/// @notice Mainnet-fork test that runs `UpdateMintMarketDebtCeilingsScript` to build the timelock
///         Safe batch calldata, executes it through the real TimelockController (schedule -> wait ->
///         execute), and asserts the resulting on-chain debt ceilings and DUSD minter ceilings.
contract UpdateMintMarketDebtCeilingsForkTest is Test {
    // --- Deployed contract addresses (ethereum-mainnet) ---
    address constant TIMELOCK = 0xfAe841679dc1A93D225ECc827E4BbF3e8d703F86;
    // Multisig holding PROPOSER_ROLE / EXECUTOR_ROLE on the timelock (from deploy config).
    address constant TIMELOCK_ADMIN = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant SUSDE_MINT_MARKET = 0x210bF54092B66443FddFec0f3F156e74B04CD2a2;
    address constant SYRUP_USDC_MINT_MARKET = 0xD2eA320713158a7b7eaE46025B8Ad4CBF3cdc87e;

    // Must mirror the constants in UpdateMintMarketDebtCeilingsScript.
    uint256 constant SUSDE_NEW_DEBT_CEILING = 35_000 ether;
    uint256 constant SYRUP_USDC_NEW_DEBT_CEILING = 54_000 ether;
    uint256 constant MINTER_CEILING_MULTIPLIER = 1.05 ether;

    string constant SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-mint-market-debt-ceiling-update-schedule.json";
    string constant EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-mint-market-debt-ceiling-update-execute.json";

    UpdateMintMarketDebtCeilingsScript internal script;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));
        script = new UpdateMintMarketDebtCeilingsScript();
    }

    /// @dev Sanity: both markets and DUSD are owned by the timelock, so the batch is the only path.
    function test_ownersAreTimelock() public view {
        assertEq(IMintMarketExtra(SUSDE_MINT_MARKET).owner(), TIMELOCK, "sUSDe market owner");
        assertEq(IMintMarketExtra(SYRUP_USDC_MINT_MARKET).owner(), TIMELOCK, "syrupUSDC market owner");
        assertEq(IMintMarketExtra(DUSD).owner(), TIMELOCK, "DUSD owner");
    }

    /// @dev A non-owner cannot call `setDebtCeiling` directly; it must go through the timelock batch.
    function test_setDebtCeiling_revertsForNonOwner() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        IAltoMintMarketLike(SUSDE_MINT_MARKET).setDebtCeiling(SUSDE_NEW_DEBT_CEILING);
    }

    function test_executeBatch_updatesDebtAndMinterCeilings() public {
        // Generate the Safe scheduleBatch/executeBatch JSONs (also exercises the script's on-chain reads).
        script.run();

        uint256 expectedSusdeMinterCeiling =
            SUSDE_NEW_DEBT_CEILING * MINTER_CEILING_MULTIPLIER / _maxLltv(SUSDE_MINT_MARKET);
        uint256 expectedSyrupMinterCeiling =
            SYRUP_USDC_NEW_DEBT_CEILING * MINTER_CEILING_MULTIPLIER / _maxLltv(SYRUP_USDC_MINT_MARKET);

        // `setDebtCeiling` reverts if current utilization exceeds the new ceiling; assert the
        // precondition up-front so a failure is legible instead of a raw timelock execute revert.
        _assertCeilingCoversUtilization(SUSDE_MINT_MARKET, SUSDE_NEW_DEBT_CEILING);
        _assertCeilingCoversUtilization(SYRUP_USDC_MINT_MARKET, SYRUP_USDC_NEW_DEBT_CEILING);

        _executeSafeTimelockBatch(SCHEDULE_JSON, EXECUTE_JSON);

        (uint128 susdeAssets,) = IAltoMintMarketLike(SUSDE_MINT_MARKET).totalSupply();
        (uint128 syrupAssets,) = IAltoMintMarketLike(SYRUP_USDC_MINT_MARKET).totalSupply();
        assertEq(uint256(susdeAssets), SUSDE_NEW_DEBT_CEILING, "sUSDe debt ceiling not set");
        assertEq(uint256(syrupAssets), SYRUP_USDC_NEW_DEBT_CEILING, "syrupUSDC debt ceiling not set");

        (, uint256 susdeMinterCeiling) = IDUSD(DUSD).minterConfig(SUSDE_MINT_MARKET);
        (, uint256 syrupMinterCeiling) = IDUSD(DUSD).minterConfig(SYRUP_USDC_MINT_MARKET);
        assertEq(susdeMinterCeiling, expectedSusdeMinterCeiling, "sUSDe minter ceiling wrong");
        assertEq(syrupMinterCeiling, expectedSyrupMinterCeiling, "syrupUSDC minter ceiling wrong");
    }

    function _maxLltv(address market) internal view returns (uint256) {
        return ILiquidationEngineLike(IAltoMintMarketLike(market).liquidationEngine()).minLltv();
    }

    function _assertCeilingCoversUtilization(address market, uint256 newCeiling) internal view {
        (uint128 borrowedAssets,) = IMintMarketExtra(market).totalBorrowed();
        assertGe(newCeiling, uint256(borrowedAssets), "new debt ceiling below current borrowed assets");
    }

    /// @dev Executes a Safe timelock batch: read schedule/execute calldata from the generated JSON,
    ///      submit as the timelock proposer/executor, warp past the delay, then execute.
    function _executeSafeTimelockBatch(string memory schedulePath, string memory executePath) internal {
        TimelockController timelock = TimelockController(payable(TIMELOCK));
        uint256 minDelay = timelock.getMinDelay();

        bytes memory scheduleData = _readSafeTxData(schedulePath);
        bytes memory executeData = _readSafeTxData(executePath);

        vm.prank(TIMELOCK_ADMIN);
        (bool scheduled,) = TIMELOCK.call(scheduleData);
        assertTrue(scheduled, "timelock schedule failed");

        vm.warp(block.timestamp + minDelay + 1);

        vm.prank(TIMELOCK_ADMIN);
        (bool executed,) = TIMELOCK.call(executeData);
        assertTrue(executed, "timelock execute failed");
    }

    function _readSafeTxData(string memory path) internal view returns (bytes memory) {
        string memory json = vm.readFile(path);
        return vm.parseJsonBytes(json, ".transactions[0].data");
    }
}
