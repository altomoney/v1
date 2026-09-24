// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DeployAltoEthereumMainnetTestBase} from "./DeployAltoEthereumMainnet.t.sol";
import {
    DeployAltoEthereumMainnet,
    DeploymentPhase,
    MarketContracts
} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnet.sol";
import {IMarket, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {IMarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract CreditMarketTypeStub {
    function MARKET_TYPE() external pure returns (MarketType) {
        return MarketType.CREDIT_MINT;
    }
}

contract UpgradeAllMintBorrowMarketsTest is DeployAltoEthereumMainnetTestBase {
    uint256 internal constant FORK_BLOCK = 26_047_473;
    string internal constant SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-all-mint-borrow-markets-upgrade-schedule.json";
    string internal constant EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-all-mint-borrow-markets-upgrade-execute.json";

    function setUp() public override {
        super.setUp();
        vm.createSelectFork(vm.rpcUrl("ethereum"), FORK_BLOCK);
        _loadCurrentChainInput();
    }

    function test_upgradeAllRegisteredMintAndBorrowMarkets() public {
        params.timelockAdmin = MAINNET_TIMELOCK_ADMIN;
        params.phase = DeploymentPhase.UPGRADE_ALL_MINT_BORROW_MARKETS;

        bool scheduleExisted = vm.exists(SCHEDULE_JSON);
        bool executeExisted = vm.exists(EXECUTE_JSON);
        string memory oldSchedule = scheduleExisted ? vm.readFile(SCHEDULE_JSON) : "";
        string memory oldExecute = executeExisted ? vm.readFile(EXECUTE_JSON) : "";

        IMarketRegistry registry = IMarketRegistry(input.contracts.marketRegistry);
        address[] memory mintMarkets = registry.getMintMarkets();
        address[] memory borrowMarkets = registry.getBorrowMarkets();
        assertEq(mintMarkets.length, 13, "mint registry count");
        assertEq(borrowMarkets.length, 7, "borrow registry count");

        address[] memory markets = new address[](mintMarkets.length + borrowMarkets.length);
        address[] memory oldImplementations = new address[](markets.length);
        bytes32[] memory oldState = new bytes32[](markets.length);
        for (uint256 i; i < markets.length; i++) {
            address market = i < mintMarkets.length ? mintMarkets[i] : borrowMarkets[i - mintMarkets.length];
            markets[i] = market;
            assertEq(
                uint256(IMarket(market).MARKET_TYPE()),
                uint256(i < mintMarkets.length ? MarketType.MINT : MarketType.BORROW),
                "ordinary market type"
            );
            oldImplementations[i] = UnsafeUpgrades.getImplementationAddress(market);
            oldState[i] = _marketState(market);
        }

        // A credit market can share the mint registry, but must not receive AltoMintMarket code.
        address creditMarket = address(new CreditMarketTypeStub());
        vm.prank(Ownable(address(registry)).owner());
        registry.addMintMarket(creditMarket);

        uint64 deploymentNonce = vm.getNonce(address(this));
        input = DeployAltoEthereumMainnet.deploy(params, input);
        assertEq(vm.getNonce(address(this)), deploymentNonce + 2, "only two implementations deployed");
        assertTrue(vm.exists(SCHEDULE_JSON), "schedule JSON");
        assertTrue(vm.exists(EXECUTE_JSON), "execute JSON");
        assertEq(bytes4(_readSafeTxData(SCHEDULE_JSON)), TimelockController.scheduleBatch.selector, "schedule call");
        assertEq(bytes4(_readSafeTxData(EXECUTE_JSON)), TimelockController.executeBatch.selector, "execute call");

        address mintImplementation = _recordedImplementation(mintMarkets[0]);
        address borrowImplementation = _recordedImplementation(borrowMarkets[0]);
        assertTrue(mintImplementation.code.length > 0, "new mint implementation");
        assertTrue(borrowImplementation.code.length > 0, "new borrow implementation");
        assertTrue(mintImplementation != borrowImplementation, "implementations differ");

        for (uint256 i; i < markets.length; i++) {
            address market = markets[i];
            address expectedImplementation = i < mintMarkets.length ? mintImplementation : borrowImplementation;
            assertEq(_recordedImplementation(market), expectedImplementation, "recorded implementation");
            assertTrue(expectedImplementation != oldImplementations[i], "new implementation address");
            assertEq(UnsafeUpgrades.getImplementationAddress(market), oldImplementations[i], "no early upgrade");
        }

        _executeSafeTimelockBatch(SCHEDULE_JSON, EXECUTE_JSON);

        for (uint256 i; i < markets.length; i++) {
            assertEq(
                UnsafeUpgrades.getImplementationAddress(markets[i]),
                _recordedImplementation(markets[i]),
                "upgraded implementation"
            );
            assertEq(_marketState(markets[i]), oldState[i], "market state preserved");
        }

        if (scheduleExisted) vm.writeFile(SCHEDULE_JSON, oldSchedule);
        else vm.removeFile(SCHEDULE_JSON);
        if (executeExisted) vm.writeFile(EXECUTE_JSON, oldExecute);
        else vm.removeFile(EXECUTE_JSON);
    }

    function _marketState(address market) private view returns (bytes32) {
        IMarket m = IMarket(market);
        return keccak256(
            abi.encode(
                m.MARKET_TYPE(),
                m.borrowToken(),
                m.collateralToken(),
                m.irm(),
                m.oracle(),
                m.maxLtv(),
                m.feeRecipient(),
                m.liquidationEngine(),
                m.totalSupply(),
                m.totalBorrowed(),
                Ownable(market).owner()
            )
        );
    }

    function _recordedImplementation(address market) private view returns (address implementation) {
        MarketContracts[21] memory records = [
            input.contracts.wethMarket,
            input.contracts.wstethMarket,
            input.contracts.rethMarket,
            input.contracts.methMarket,
            input.contracts.tbtcMarket,
            input.contracts.wbtcBorrowMarket,
            input.contracts.cbbtcBorrowMarket,
            input.contracts.susdeBorrowMarket,
            input.contracts.syrupUsdcBorrowMarket,
            input.contracts.paxgBorrowMarket,
            input.contracts.susdeMintMarket,
            input.contracts.syrupUsdcMintMarket,
            input.contracts.frxUsdMarket,
            input.contracts.refreshWethMarket,
            input.contracts.refreshWstethMarket,
            input.contracts.refreshRethMarket,
            input.contracts.refreshSusdeBorrowMarket,
            input.contracts.refreshSyrupUsdcBorrowMarket,
            input.contracts.refreshSusdeMintMarket,
            input.contracts.refreshSyrupUsdcMintMarket,
            input.contracts.refreshFrxUsdMarket
        ];
        for (uint256 i; i < records.length; i++) {
            if (records[i].market == market) return records[i].marketImplementation;
        }
        revert("Market missing from deployment record");
    }
}
