// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {BorrowMarketOffboarding} from "../BorrowMarketOffboarding.sol";
import {
    BorrowMarketOffboardingInput,
    BorrowMarketOffboardingParams,
    BorrowMarketOffboardingPhase
} from "../IBorrowMarketOffboarding.sol";
import {BorrowMarketOffboardingScript} from "../scripts/BorrowMarketOffboarding.s.sol";

import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {IAltoVault, IAltoVaultBase, IAltoVaultErrors, MarketAllocation} from "@alto/lending/interfaces/IAltoVault.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {Balance, IMarket, IMarketBase, Position} from "@alto/lending/interfaces/IMarket.sol";
import {AltoLeverage} from "@alto/lending/leverage/AltoLeverage.sol";
import {IAltoLeverageSwapper} from "@alto/lending/leverage/interfaces/IAltoLeverageSwapper.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {MarketConfig, PendingUint192} from "@alto/lending/libraries/PendingLib.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AdapterContractApproval} from "@alto/utils/AdapterContractApproval.sol";
import {AltoTimelockController} from "@alto/utils/AltoTimelockController.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BorrowMarketOffboardingTestHarness is BorrowMarketOffboardingScript {
    function loadInput() external view returns (BorrowMarketOffboardingInput memory) {
        return _loadCurrentChainInput();
    }

    function runPhase(BorrowMarketOffboardingPhase phase, BorrowMarketOffboardingInput memory input)
        external
        returns (BorrowMarketOffboardingInput memory)
    {
        return _runPhase(phase, input);
    }
}

abstract contract BorrowMarketOffboardingTestBase is Test {
    using AltoBalancesLib for address;

    string internal constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";
    string internal constant OUTPUT_DIRECTORY = "ERP/ERP-OFFBOARD-02/output/";
    string internal constant FREEZE_FILE = "batch-a-freeze-safe.json";
    string internal constant CURATOR_FILE = "batch-a-vault-curator-safe.json";
    string internal constant FIXED_IRM_SCHEDULE_FILE = "batch-b-fixed-rate-irm-schedule.json";
    string internal constant FIXED_IRM_EXECUTE_FILE = "batch-b-fixed-rate-irm-execute.json";
    string internal constant REDUCE_LTV_SCHEDULE_FILE = "batch-b-irm-and-ltv-update-schedule.json";
    string internal constant REDUCE_LTV_EXECUTE_FILE = "batch-b-irm-and-ltv-update-execute.json";
    string internal constant RECOVER_SCHEDULE_FILE = "batch-c-final-removal-schedule.json";
    string internal constant RECOVER_EXECUTE_FILE = "batch-c-final-removal-execute.json";

    address internal constant FREEZER_SAFE = 0x1c11d2d42929bd17aB7212b79c91862Adfa8bbe4;
    address internal constant TIMELOCK_SAFE = 0xc49bf619CC9A68F84A6C9aB88506F2627565a4D0;
    address internal constant VAULT_ALLOCATOR = 0x7db7C14533a4186EcC07950F78835859320835Be;
    uint256 internal constant ADDRESS_SNAPSHOT_BLOCK = 25_833_639;
    uint256 internal constant FIXED_RATE_SPY = 0.1 ether / uint256(365 days);

    struct MarketFixture {
        address supplier;
        address exitBorrower;
        address liquidationBorrower;
        address liquidator;
        uint256 livePrice;
    }

    BorrowMarketOffboardingTestHarness internal scriptHarness;
    BorrowMarketOffboardingInput internal input;
    TimelockController internal timelock;
    IAltoVault internal vault;
    IERC4626 internal vaultToken;
    IMarketRegistry internal marketRegistry;
    AdapterContractApproval internal altoAdapter;
    address internal liquidationPeriphery;
    address[] internal borrowMarkets;
    address[] internal leverages;
    address[] internal leverageSwappers;
    MarketFixture[] internal fixtures;
    bool internal marketAlreadyFrozen;

    function _selectFork() internal {
        vm.createSelectFork(vm.rpcUrl("ethereum"), ADDRESS_SNAPSHOT_BLOCK);
    }

    function _setUpManifest() internal {
        _selectFork();
        scriptHarness = new BorrowMarketOffboardingTestHarness();
        input = scriptHarness.loadInput();
        timelock = TimelockController(payable(input.contracts.timelock));
        vault = IAltoVault(input.contracts.dusdVault);
        vaultToken = IERC4626(input.contracts.dusdVault);
        marketRegistry = IMarketRegistry(input.contracts.marketRegistry);
        altoAdapter = AdapterContractApproval(input.contracts.altoAdapter);
        liquidationPeriphery = input.contracts.liquidationPeriphery;
        _loadManifestArrays();

        for (uint256 i; i < borrowMarkets.length; ++i) {
            if (IMarketBase(borrowMarkets[i]).paused(FROZEN_TYPE)) {
                marketAlreadyFrozen = true;
                return;
            }
        }
    }

    function _loadManifestArrays() private {
        borrowMarkets.push(input.contracts.wbtcBorrowMarket);
        borrowMarkets.push(input.contracts.cbbtcBorrowMarket);
        borrowMarkets.push(input.contracts.susdeBorrowMarket);
        borrowMarkets.push(input.contracts.syrupUsdcBorrowMarket);
        borrowMarkets.push(input.contracts.paxgBorrowMarket);

        leverages.push(input.contracts.wbtcBorrowLeverage);
        leverages.push(input.contracts.cbbtcBorrowLeverage);
        leverages.push(input.contracts.susdeBorrowLeverage);
        leverages.push(input.contracts.syrupUsdcBorrowLeverage);
        leverages.push(input.contracts.paxgBorrowLeverage);

        for (uint256 i; i < leverages.length; ++i) {
            leverageSwappers.push(address(AltoLeverage(leverages[i]).swapper()));
        }
    }

    function _seedStandardPositions() internal {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _seedStandardPosition(i);
        }
    }

    function _seedStandardPosition(uint256 marketIndex) private {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        assertFalse(market.paused(PAUSE_TYPE), "market paused before Batch A");

        MarketFixture memory fixture = MarketFixture({
            supplier: makeAddr(string.concat("supplier-", vm.toString(marketIndex))),
            exitBorrower: makeAddr(string.concat("exit-borrower-", vm.toString(marketIndex))),
            liquidationBorrower: makeAddr(string.concat("liquidation-borrower-", vm.toString(marketIndex))),
            liquidator: makeAddr(string.concat("liquidator-", vm.toString(marketIndex))),
            livePrice: IOracle(market.oracle()).getPrice()
        });

        IERC20 borrowToken = IERC20(market.borrowToken());
        uint256 collateralAssets = 10 ** uint256(IERC20Metadata(market.collateralToken()).decimals()) / 100;
        uint256 collateralValue = Math.mulDiv(collateralAssets, fixture.livePrice, LENDING_ORACLE_PRICE_PRECISION);
        uint256 maximumBorrow = Math.mulDiv(collateralValue, market.maxLtv(), 1 ether);

        deal(address(borrowToken), fixture.supplier, 1 ether);
        vm.startPrank(fixture.supplier);
        borrowToken.approve(address(market), 1 ether);
        market.addSupply(1 ether, 0, fixture.supplier);
        vm.stopPrank();

        _openBorrowPosition(market, fixture.exitBorrower, collateralAssets, maximumBorrow / 10);
        _openBorrowPosition(market, fixture.liquidationBorrower, collateralAssets, maximumBorrow / 2);
        fixtures.push(fixture);
    }

    function _openBorrowPosition(IMarket market, address borrower, uint256 collateralAssets, uint256 borrowAssets)
        internal
    {
        IERC20 collateralToken = IERC20(market.collateralToken());
        deal(address(collateralToken), borrower, collateralAssets);

        vm.startPrank(borrower);
        collateralToken.approve(address(market), collateralAssets);
        market.addCollateral(collateralAssets, borrower);
        market.borrow(borrowAssets, 0, borrower, borrower, "");
        vm.stopPrank();
    }

    function _exerciseExitAndLiquidationRoutes(IMarket market, MarketFixture memory fixture) internal {
        vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(fixture.livePrice));

        Position memory supplyPosition = market.position(fixture.supplier);
        Position memory exitPosition = market.position(fixture.exitBorrower);
        IERC20 borrowToken = IERC20(market.borrowToken());

        deal(address(borrowToken), fixture.exitBorrower, 1_000_000 ether);
        vm.startPrank(fixture.exitBorrower);
        borrowToken.approve(address(market), type(uint256).max);
        market.repay(0, exitPosition.borrowShares, fixture.exitBorrower);
        market.removeCollateral(exitPosition.collateralAssets, fixture.exitBorrower, fixture.exitBorrower, "");
        vm.stopPrank();

        vm.prank(fixture.supplier);
        (uint256 withdrawnAssets,) =
            market.removeSupply(0, supplyPosition.supplyShares, fixture.supplier, fixture.supplier);

        assertGt(withdrawnAssets, 0, "removeSupply returned no assets");
        assertEq(market.position(fixture.supplier).supplyShares, 0, "removeSupply failed");
        assertEq(market.position(fixture.exitBorrower).borrowShares, 0, "repay failed");
        assertEq(market.position(fixture.exitBorrower).collateralAssets, 0, "removeCollateral failed");

        vm.mockCall(market.oracle(), abi.encodeCall(IOracle.getPrice, ()), abi.encode(fixture.livePrice / 4));
        Position memory liquidationPosition = market.position(fixture.liquidationBorrower);
        deal(address(borrowToken), fixture.liquidator, 1_000_000 ether);

        vm.startPrank(fixture.liquidator);
        borrowToken.approve(address(market), type(uint256).max);
        (uint256 seizedCollateral, uint256 repaidBorrow,) = market.liquidate(fixture.liquidationBorrower, "", "");
        vm.stopPrank();

        Position memory positionAfter = market.position(fixture.liquidationBorrower);
        assertGt(seizedCollateral, 0, "liquidation seized no collateral");
        assertGt(repaidBorrow, 0, "liquidation repaid no debt");
        assertLt(positionAfter.borrowShares, liquidationPosition.borrowShares, "liquidation did not reduce debt");
        assertLt(positionAfter.collateralAssets, liquidationPosition.collateralAssets, "liquidation seized no position");
    }

    function _ensureFactory() internal returns (OwnerFixedRateIrmFactory factory) {
        factory = OwnerFixedRateIrmFactory(input.contracts.ownerFixedRateIrmFactory);
        if (address(factory) == address(0)) {
            input = scriptHarness.runPhase(BorrowMarketOffboardingPhase.DEPLOY_OWNER_FIXED_RATE_IRM_FACTORY, input);
            factory = OwnerFixedRateIrmFactory(input.contracts.ownerFixedRateIrmFactory);
        }
        assertEq(factory.owner(), address(timelock), "Timelock does not own factory");
    }

    function _executeContainmentPrerequisite() internal {
        input = scriptHarness.runPhase(BorrowMarketOffboardingPhase.BATCH_A_CONTAIN, input);
        _executeSafeBatch(FREEZE_FILE, FREEZER_SAFE);
        _executeSafeBatch(CURATOR_FILE, vault.curator());
    }

    function _executeTimelockPhase(
        BorrowMarketOffboardingPhase phase,
        string memory scheduleFile,
        string memory executeFile
    ) internal {
        input = scriptHarness.runPhase(phase, input);
        _executeSafeBatch(scheduleFile, TIMELOCK_SAFE);
        vm.warp(block.timestamp + timelock.getMinDelay());
        _executeSafeBatch(executeFile, TIMELOCK_SAFE);
    }

    function _executeSafeBatch(string memory fileName, address safe) internal {
        string memory json = vm.readFile(string.concat(OUTPUT_DIRECTORY, fileName));
        assertEq(vm.parseJsonAddress(json, ".meta.createdFromSafeAddress"), safe, "wrong transaction Safe");

        uint256 transactionIndex;
        while (_jsonTransactionExists(json, transactionIndex)) {
            (address target, bytes memory data) = _jsonTransaction(json, transactionIndex);
            _callFrom(safe, target, data);
            ++transactionIndex;
        }
        assertGt(transactionIndex, 0, "empty Safe batch");
    }

    function _jsonTransaction(string memory json, uint256 index)
        internal
        pure
        returns (address target, bytes memory data)
    {
        string memory prefix = string.concat(".transactions[", vm.toString(index), "]");
        target = vm.parseJsonAddress(json, string.concat(prefix, ".to"));
        data = vm.parseJsonBytes(json, string.concat(prefix, ".data"));
        assertEq(vm.parseJsonString(json, string.concat(prefix, ".value")), "0", "non-zero Safe value");
    }

    function _jsonTransactionExists(string memory json, uint256 index) internal view returns (bool) {
        return vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(index), "]"));
    }

    function _callFrom(address caller, address target, bytes memory data) internal {
        vm.prank(caller);
        (bool success, bytes memory returnData) = target.call(data);
        assertTrue(success, string(returnData));
    }

    function _assertFrozenAndUnpaused(IMarketBase market) internal view {
        assertTrue(market.paused(FROZEN_TYPE), "market not frozen");
        assertFalse(market.paused(PAUSE_TYPE), "market paused");
    }

    function _assertAllFrozenAndUnpaused() internal view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertFrozenAndUnpaused(IMarketBase(borrowMarkets[i]));
        }
    }

    function _assertRequiredExitIntegrationsActive(uint256 marketIndex) internal view {
        address market = borrowMarkets[marketIndex];
        address leverage = leverages[marketIndex];

        assertTrue(marketRegistry.isBorrowMarket(market), "market removed from MarketRegistry");
        assertTrue(altoAdapter.isApprovedContract(market), "market removed from AltoAdapter");
        assertTrue(AltoLeverage(leverage).supportedMarkets(market), "leverage market support removed");
        assertTrue(IMarket(market).authorizedCallbacks(leverage), "leverage callback removed");
        assertTrue(
            IAltoLeverageSwapper(leverageSwappers[marketIndex]).isWhitelisted(leverage),
            "leverage swapper permission removed"
        );
        assertTrue(
            IMarket(market).authorizedLiquidationPeriphery(liquidationPeriphery),
            "liquidation periphery permission removed"
        );
    }

    function _assertAllRequiredExitIntegrationsActive() internal view {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _assertRequiredExitIntegrationsActive(i);
        }
    }

    function _isAffectedMarket(address market) internal view returns (bool) {
        for (uint256 i; i < borrowMarkets.length; ++i) {
            if (borrowMarkets[i] == market) return true;
        }
        return false;
    }

    function _isInSupplyQueue(address market) internal view returns (bool) {
        for (uint256 i; i < vault.supplyQueueLength(); ++i) {
            if (vault.supplyQueue(i) == market) return true;
        }
        return false;
    }

    function _isInWithdrawQueue(address market) internal view returns (bool) {
        for (uint256 i; i < vault.withdrawQueueLength(); ++i) {
            if (vault.withdrawQueue(i) == market) return true;
        }
        return false;
    }

    function _assertBorrowerInventoryComplete(uint256 marketIndex) internal view {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        address[] memory borrowers = _borrowers(marketIndex);
        uint256 listedBorrowShares;
        for (uint256 i; i < borrowers.length; ++i) {
            listedBorrowShares += market.position(borrowers[i]).borrowShares;
        }
        assertEq(
            listedBorrowShares,
            market.totalBorrowed().shares,
            string.concat("stale borrower list for market ", vm.toString(marketIndex))
        );
    }

    function _repayAllBorrowersForMarket(uint256 marketIndex) internal {
        IMarket market = IMarket(borrowMarkets[marketIndex]);
        address[] memory borrowers = _borrowers(marketIndex);
        IERC20 borrowToken = IERC20(market.borrowToken());
        uint256 marketDebtAssets = market.totalBorrowed().assets;

        for (uint256 i; i < borrowers.length; ++i) {
            address borrower = borrowers[i];
            uint256 borrowShares = market.position(borrower).borrowShares;
            assertGt(borrowShares, 0, "listed borrower has no debt");

            deal(address(borrowToken), borrower, marketDebtAssets + 1);
            vm.startPrank(borrower);
            borrowToken.approve(address(market), type(uint256).max);
            market.repay(0, borrowShares, borrower);
            vm.stopPrank();
            assertEq(market.position(borrower).borrowShares, 0, "borrower debt remains");
        }

        Balance memory debtAfter = market.totalBorrowed();
        assertEq(debtAfter.assets, 0, "market borrowed assets remain");
        assertEq(debtAfter.shares, 0, "market borrowed shares remain");
    }
    /// @dev Current non-zero borrowers, sourced from Borrow events and verified at ADDRESS_SNAPSHOT_BLOCK.

    function _borrowers(uint256 marketIndex) internal pure returns (address[] memory borrowers) {
        if (marketIndex == 0) return _wbtcBorrowers();
        if (marketIndex == 1) return _cbbtcBorrowers();
        if (marketIndex == 2) return _susdeBorrowers();
        if (marketIndex == 3) return _syrupUsdcBorrowers();
        if (marketIndex == 4) return _paxgBorrowers();
        revert("invalid market index");
    }

    function _wbtcBorrowers() internal pure returns (address[] memory borrowers) {
        borrowers = new address[](12);
        borrowers[0] = 0x023c1dE9cdeB3BF789F1B9594b80a6E6F7e03aE0;
        borrowers[1] = 0x43E47A90990B0357c5988fF416E77C253F618274;
        borrowers[2] = 0x4e90Da1dDCD5B0Fb295b6A69251b5D04D5bCCA7a;
        borrowers[3] = 0x5451C3C1e156B7e8e3004727577485d4ff1152e0;
        borrowers[4] = 0x6644394eec6782a2f4D146Bb1f8896C50d7f2990;
        borrowers[5] = 0x6ACe206b3d969C8D17070f835518333f8A454Fb4;
        borrowers[6] = 0x71f0F9669ACa235Cd39307Aa931e1179A0C0DD48;
        borrowers[7] = 0x862d949F1A9617DBd18CC7B832E8f9E98bE2D535;
        borrowers[8] = 0x93FC1F35f53a9553534979233caF273214C51Fd7;
        borrowers[9] = 0xAb56934ec90B1C2fC76eF2B03c1dE282A66799BF;
        borrowers[10] = 0xC52dDBF8B6d3A5b68bf4cEbbc7240834A3CBA73B;
        borrowers[11] = 0xEa1b93cdB67a92Fd961FFE82d15eFE414AD08F92;
    }

    function _cbbtcBorrowers() internal pure returns (address[] memory borrowers) {
        borrowers = new address[](9);
        borrowers[0] = 0x06216ab9D28d989d31320D24A7C382aBE63FbA47;
        borrowers[1] = 0x1b35fcb58F5E1e2a42fF8E66ddf5646966aBf08C;
        borrowers[2] = 0x2A3641aFd2bB54cE729198295b80FEfFaa8b14C5;
        borrowers[3] = 0x3482e460D7E8108ef7d24a5d7C60133dc5697597;
        borrowers[4] = 0x68d3431bd22779b08113B50B3CF6a0ba265fc9E0;
        borrowers[5] = 0xbcb4c8386c097589e7825aAeb9E7C6295835F1d6;
        borrowers[6] = 0xC3453f9ba9974D956f686Ba7F236BbFF5DE6aFF6;
        borrowers[7] = 0xd65370c5565F2bEa121F3C22823233F98A4Be793;
        borrowers[8] = 0xD6E8222b207EbDB33dfDd0a6299b9424F2BDf35a;
    }

    function _susdeBorrowers() internal pure returns (address[] memory borrowers) {
        borrowers = new address[](30);
        borrowers[0] = 0x023c1dE9cdeB3BF789F1B9594b80a6E6F7e03aE0;
        borrowers[1] = 0x04FAD3020d3fcFedAA2B548143bFb6127E8Ea581;
        borrowers[2] = 0x0ba164C161a8bDfCE9a295e6b1e3067498fc5D97;
        borrowers[3] = 0x0cd7E1660D63a6aEbDA782a2Eb7f2875716aC3E8;
        borrowers[4] = 0x1b35fcb58F5E1e2a42fF8E66ddf5646966aBf08C;
        borrowers[5] = 0x2A3641aFd2bB54cE729198295b80FEfFaa8b14C5;
        borrowers[6] = 0x3E88681De2E12d1AC4116a7A6fb964A2C4C102AE;
        borrowers[7] = 0x4096D69deE9EBDbE23C939a241660F7861e0A223;
        borrowers[8] = 0x513AeDacE44cc9a0724CA276a8CeeeE950903576;
        borrowers[9] = 0x5D50cA0a21F434E9F3f8110e1980005111D1B93b;
        borrowers[10] = 0x6e3880c88695CeBdE3e7baa95662050F7126795b;
        borrowers[11] = 0x7F8ddA85d44A6F225257375546fec2f96C3b95EE;
        borrowers[12] = 0x817758aaA3c3430F764De6630EAbE218e1282BF0;
        borrowers[13] = 0x82F5604D78ea962A018049732f81Bf74851A77ad;
        borrowers[14] = 0x862d949F1A9617DBd18CC7B832E8f9E98bE2D535;
        borrowers[15] = 0x88de30CDB91DE2B66b801512bB8073169035bdFB;
        borrowers[16] = 0x8B16e97ae8A322d56d619022443492dF4aeAa7Cd;
        borrowers[17] = 0x8ce4fe19ac5ea0df14200FADd5450c3cF40CF0D0;
        borrowers[18] = 0x91FC012D62AF22390B55B0B3d489ca26473612BB;
        borrowers[19] = 0x9E1b45A473B8B004A40ddC6Ea2730b36d16a1796;
        borrowers[20] = 0xA5acf1B71B653662FCf881EDbf8c92460b1C387D;
        borrowers[21] = 0xAaF92Ac96A7cfc79Cc539155FFA068e061D9adda;
        borrowers[22] = 0xb0FabE3bCAC50F065DBF68C0B271118DDC005402;
        borrowers[23] = 0xbcb4c8386c097589e7825aAeb9E7C6295835F1d6;
        borrowers[24] = 0xCc58AccACd0db8010e4c8A20BA49D2DC9d4D7f59;
        borrowers[25] = 0xd65370c5565F2bEa121F3C22823233F98A4Be793;
        borrowers[26] = 0xe12f8e5309682cDEa4A3F7160fbB25D0d111d9b7;
        borrowers[27] = 0xEa1b93cdB67a92Fd961FFE82d15eFE414AD08F92;
        borrowers[28] = 0xF9245808dAc44f7365189d30bD981a3B8dc83Bef;
        borrowers[29] = 0xfe8D5Dea7987d101247243D5BbAF7804a1Ff187a;
    }

    function _syrupUsdcBorrowers() internal pure returns (address[] memory borrowers) {
        borrowers = new address[](14);
        borrowers[0] = 0x04FAD3020d3fcFedAA2B548143bFb6127E8Ea581;
        borrowers[1] = 0x0cd7E1660D63a6aEbDA782a2Eb7f2875716aC3E8;
        borrowers[2] = 0x0fD90B9D61af052C4328BC2Fa9A1529627af0a7d;
        borrowers[3] = 0x4096D69deE9EBDbE23C939a241660F7861e0A223;
        borrowers[4] = 0x4e90Da1dDCD5B0Fb295b6A69251b5D04D5bCCA7a;
        borrowers[5] = 0x513AeDacE44cc9a0724CA276a8CeeeE950903576;
        borrowers[6] = 0x82F5604D78ea962A018049732f81Bf74851A77ad;
        borrowers[7] = 0x91FC012D62AF22390B55B0B3d489ca26473612BB;
        borrowers[8] = 0x9E1b45A473B8B004A40ddC6Ea2730b36d16a1796;
        borrowers[9] = 0xA5acf1B71B653662FCf881EDbf8c92460b1C387D;
        borrowers[10] = 0xb401300129437757A22d8ca3AaCeD4fBe6C4BB82;
        borrowers[11] = 0xb82bE987cF6f25d0F040Ca4567e3dacb4b92Aa91;
        borrowers[12] = 0xBB5311aF8D1982D690050F05AecAc08F0Ac65f19;
        borrowers[13] = 0xD6E8222b207EbDB33dfDd0a6299b9424F2BDf35a;
    }

    function _paxgBorrowers() internal pure returns (address[] memory borrowers) {
        borrowers = new address[](11);
        borrowers[0] = 0x04FAD3020d3fcFedAA2B548143bFb6127E8Ea581;
        borrowers[1] = 0x1DCb82280f423f475F7DC3A76Ed53f3C38578fA7;
        borrowers[2] = 0x22076fba2ea9650a028Aa499d0444c4Aa9aF1Bf8;
        borrowers[3] = 0x4096D69deE9EBDbE23C939a241660F7861e0A223;
        borrowers[4] = 0x43E47A90990B0357c5988fF416E77C253F618274;
        borrowers[5] = 0x5275817b74021E97c980E95EdE6bbAc0D0d6f3a2;
        borrowers[6] = 0x5451C3C1e156B7e8e3004727577485d4ff1152e0;
        borrowers[7] = 0x5EeDe1C45E4401d7D95E55446dAd71B511328534;
        borrowers[8] = 0x862d949F1A9617DBd18CC7B832E8f9E98bE2D535;
        borrowers[9] = 0xb401300129437757A22d8ca3AaCeD4fBe6C4BB82;
        borrowers[10] = 0xBB5311aF8D1982D690050F05AecAc08F0Ac65f19;
    }

    /// @dev Current non-zero DUSD Vault holders, sourced from Transfer events at ADDRESS_SNAPSHOT_BLOCK.
    function _vaultHolders() internal pure returns (address[] memory holders) {
        holders = new address[](10);
        holders[0] = 0x04FAD3020d3fcFedAA2B548143bFb6127E8Ea581;
        holders[1] = 0x5451C3C1e156B7e8e3004727577485d4ff1152e0;
        holders[2] = 0x68d3431bd22779b08113B50B3CF6a0ba265fc9E0;
        holders[3] = 0x862d949F1A9617DBd18CC7B832E8f9E98bE2D535;
        holders[4] = 0x8E599E2F24eF8E3eef45Eb91210B70bc96eEb08C;
        holders[5] = 0x94FfD866Ad6514a478641D955667c70cb5a08E90;
        holders[6] = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
        holders[7] = 0xA5acf1B71B653662FCf881EDbf8c92460b1C387D;
        holders[8] = 0xb0FabE3bCAC50F065DBF68C0B271118DDC005402;
        holders[9] = 0xd65370c5565F2bEa121F3C22823233F98A4Be793;
    }
}
// -----------------------------------------------------------------------------
// OwnerFixedRateIrmFactory deployment phase
