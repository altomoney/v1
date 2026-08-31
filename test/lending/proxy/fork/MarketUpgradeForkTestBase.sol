// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DeployAltoEthereumMainnetTestBase} from "@alto-test/deployments/DeployAltoEthereumMainnet.t.sol";
import {
    DeployAltoEthereumMainnet,
    DeploymentPhase,
    MarketContracts
} from "@alto/deployments/ethereum-mainnet/DeployAltoEthereumMainnet.sol";
import {IMarket, Balance, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IMarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Upgrades, UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

abstract contract MarketUpgradeForkTestBase is DeployAltoEthereumMainnetTestBase {
    string internal constant UPGRADE_SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-market-upgrade-liquidation-periphery-schedule.json";
    string internal constant UPGRADE_EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-market-upgrade-liquidation-periphery-execute.json";
    string internal constant AUTHORIZE_SCHEDULE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-market-authorize-liquidation-periphery-schedule.json";
    string internal constant AUTHORIZE_EXECUTE_JSON =
        "contracts/deployments/ethereum-mainnet/output/safe-tx-market-authorize-liquidation-periphery-execute.json";

    struct MarketData {
        address borrowToken;
        address collateralToken;
        Balance totalSupply;
        Balance totalBorrowed;
        address irm;
        address owner;
        address oracle;
        uint256 maxLtv;
        uint256 borrowOpeningFee;
        address feeRecipient;
        LiquidationConfiguration liquidationConfiguration;
        address authorizedPeriphery;
    }

    function setUp() public virtual override {
        super.setUp();
        _runLiquidationPeripheryAndMarketUpgradePhases();
    }

    function upgradeProxyExternal(address proxy, string memory contractName, bytes memory data) external {
        Upgrades.upgradeProxy(proxy, contractName, data);
    }

    function upgradeProxyExternalUnsafe(address proxy, address newImpl, bytes memory data) external {
        UnsafeUpgrades.upgradeProxy(proxy, newImpl, data);
    }

    function _shouldUseSafeProxy() internal view returns (bool) {
        return vm.envOr("VERIFY_PROXY", false);
    }

    function _upgradeProxy(address proxy, string memory contractName, address unsafeImpl, bytes memory data) internal {
        if (_shouldUseSafeProxy()) {
            Upgrades.upgradeProxy(proxy, contractName, data);
        } else {
            UnsafeUpgrades.upgradeProxy(proxy, unsafeImpl, data);
        }
    }

    function _allBorrowMarkets() internal view returns (IMarket[] memory markets) {
        markets = new IMarket[](5);
        markets[0] = IMarket(input.contracts.wbtcBorrowMarket.market);
        markets[1] = IMarket(input.contracts.cbbtcBorrowMarket.market);
        markets[2] = IMarket(input.contracts.susdeBorrowMarket.market);
        markets[3] = IMarket(input.contracts.syrupUsdcBorrowMarket.market);
        markets[4] = IMarket(input.contracts.paxgBorrowMarket.market);
    }

    function _allMintMarkets() internal view returns (IMarket[] memory markets) {
        markets = new IMarket[](7);
        markets[0] = IMarket(input.contracts.wethMarket.market);
        markets[1] = IMarket(input.contracts.wstethMarket.market);
        markets[2] = IMarket(input.contracts.rethMarket.market);
        markets[3] = IMarket(input.contracts.methMarket.market);
        markets[4] = IMarket(input.contracts.tbtcMarket.market);
        markets[5] = IMarket(input.contracts.susdeMintMarket.market);
        markets[6] = IMarket(input.contracts.syrupUsdcMintMarket.market);
    }

    function _runLiquidationPeripheryAndMarketUpgradePhases() internal {
        assertTrue(input.contracts.timelock != address(0), "need timelock from addresses.json");

        MarketContracts[12] memory marketsBefore = _allMarkets();
        for (uint256 i; i < marketsBefore.length; ++i) {
            assertTrue(marketsBefore[i].market != address(0), "market should be deployed");
            assertTrue(marketsBefore[i].marketImplementation != address(0), "market impl should be set");
        }

        if (input.contracts.liquidationPeriphery == address(0)) {
            params.phase = DeploymentPhase.LIQUIDATION_PERIPHERY;
            input = DeployAltoEthereumMainnet.deploy(params, input);
        }
        assertTrue(input.contracts.liquidationPeriphery != address(0), "need liquidation periphery");

        params.phase = DeploymentPhase.UPGRADE_MARKETS_LIQUIDATION_PERIPHERY;
        input = DeployAltoEthereumMainnet.deploy(params, input);

        address[] memory registryMarkets = _allRegistryMarkets();
        MarketContracts[12] memory marketsAfter = _allMarkets();

        for (uint256 i; i < registryMarkets.length; ++i) {
            address market = registryMarkets[i];
            address oldImpl = _marketImplementationFromInput(marketsBefore, market);
            assertEq(UnsafeUpgrades.getImplementationAddress(market), oldImpl, "pre-upgrade on-chain impl");
        }

        _executeSafeTimelockBatch(UPGRADE_SCHEDULE_JSON, UPGRADE_EXECUTE_JSON);

        for (uint256 i; i < registryMarkets.length; ++i) {
            address market = registryMarkets[i];
            address expectedImpl = _marketImplementationFromInput(marketsAfter, market);
            assertEq(UnsafeUpgrades.getImplementationAddress(market), expectedImpl, "post-upgrade on-chain impl");
        }

        _executeSafeTimelockBatch(AUTHORIZE_SCHEDULE_JSON, AUTHORIZE_EXECUTE_JSON);

        address periphery = input.contracts.liquidationPeriphery;
        for (uint256 i; i < registryMarkets.length; ++i) {
            assertTrue(
                IMarket(registryMarkets[i]).authorizedLiquidationPeriphery(periphery),
                "periphery should be authorized on market"
            );
        }
    }

    function _getMarketData(IMarket market) internal view returns (MarketData memory marketData) {
        marketData = MarketData({
            borrowToken: market.borrowToken(),
            collateralToken: market.collateralToken(),
            totalSupply: market.totalSupply(),
            totalBorrowed: market.totalBorrowed(),
            irm: market.irm(),
            owner: Ownable(address(market)).owner(),
            oracle: market.oracle(),
            maxLtv: market.maxLtv(),
            borrowOpeningFee: market.borrowOpeningFee(),
            feeRecipient: market.feeRecipient(),
            liquidationConfiguration: IDcfDlbPriorityLiquidationEngine(market.liquidationEngine())
                .liquidationConfiguration(),
            authorizedPeriphery: market.authorizedLiquidationPeriphery(input.contracts.liquidationPeriphery)
                ? input.contracts.liquidationPeriphery
                : address(0)
        });
    }

    function _assertPeripheryAuthorized(MarketData memory marketData, string memory err) internal view {
        assertEq(marketData.authorizedPeriphery, input.contracts.liquidationPeriphery, err);
    }

    function _assertMarketNotEmpty(IMarket market, MarketData memory marketData) internal view {
        assertNotEq(marketData.totalSupply.assets, 0);
        assertNotEq(marketData.totalBorrowed.assets, 0);
        assertNotEq(marketData.totalBorrowed.shares, 0);
        if (market.MARKET_TYPE() == MarketType.BORROW) {
            assertNotEq(marketData.totalSupply.shares, 0);
        }
    }

    function _assertMarketDataEqual(MarketData memory before, MarketData memory afterUpgrade) internal pure {
        _assertMarketDataEqual(before, afterUpgrade, false);
    }

    function _assertMarketDataEqual(
        MarketData memory before,
        MarketData memory afterUpgrade,
        bool skipBorrowOpeningFeeCheck
    ) internal pure {
        assertEq(before.borrowToken, afterUpgrade.borrowToken);
        assertEq(before.collateralToken, afterUpgrade.collateralToken);
        assertEq(before.totalSupply.assets, afterUpgrade.totalSupply.assets);
        assertEq(before.totalSupply.shares, afterUpgrade.totalSupply.shares);
        assertEq(before.totalBorrowed.assets, afterUpgrade.totalBorrowed.assets);
        assertEq(before.totalBorrowed.shares, afterUpgrade.totalBorrowed.shares);
        assertEq(before.irm, afterUpgrade.irm);
        assertEq(before.owner, afterUpgrade.owner);
        assertEq(before.oracle, afterUpgrade.oracle);
        assertEq(before.maxLtv, afterUpgrade.maxLtv);
        if (!skipBorrowOpeningFeeCheck) {
            assertEq(before.borrowOpeningFee, afterUpgrade.borrowOpeningFee);
        }
        assertEq(before.feeRecipient, afterUpgrade.feeRecipient);
        assertEq(before.authorizedPeriphery, afterUpgrade.authorizedPeriphery);
        assertEq(
            before.liquidationConfiguration.maxLiquidationLtv, afterUpgrade.liquidationConfiguration.maxLiquidationLtv
        );
        assertEq(
            before.liquidationConfiguration.dynamicBonusFeeStart,
            afterUpgrade.liquidationConfiguration.dynamicBonusFeeStart
        );
        assertEq(
            before.liquidationConfiguration.ltvForCompleteLiquidation,
            afterUpgrade.liquidationConfiguration.ltvForCompleteLiquidation
        );
        assertEq(
            before.liquidationConfiguration.dynamicBonusFeeDecaySteepness,
            afterUpgrade.liquidationConfiguration.dynamicBonusFeeDecaySteepness
        );
        assertEq(
            before.liquidationConfiguration.liquidationBaseFee, afterUpgrade.liquidationConfiguration.liquidationBaseFee
        );
        assertEq(
            before.liquidationConfiguration.minPenaltyPercentage,
            afterUpgrade.liquidationConfiguration.minPenaltyPercentage
        );
        assertEq(
            before.liquidationConfiguration.isEnabledPriorityLiquidation,
            afterUpgrade.liquidationConfiguration.isEnabledPriorityLiquidation
        );
        assertEq(
            before.liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv,
            afterUpgrade.liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv
        );
        assertEq(
            before.liquidationConfiguration.priorityLiquidationGracePeriod,
            afterUpgrade.liquidationConfiguration.priorityLiquidationGracePeriod
        );
        assertEq(
            before.liquidationConfiguration.taggerLiquidationGracePeriod,
            afterUpgrade.liquidationConfiguration.taggerLiquidationGracePeriod
        );
        assertEq(
            before.liquidationConfiguration.liquidationWindowTag,
            afterUpgrade.liquidationConfiguration.liquidationWindowTag
        );
    }

    function _allRegistryMarkets() internal view returns (address[] memory markets) {
        IMarketRegistry registry = IMarketRegistry(input.contracts.marketRegistry);
        address[] memory mintMarkets = registry.getMintMarkets();
        address[] memory borrowMarkets = registry.getBorrowMarkets();
        markets = new address[](mintMarkets.length + borrowMarkets.length);
        for (uint256 i; i < mintMarkets.length; ++i) {
            markets[i] = mintMarkets[i];
        }
        for (uint256 i; i < borrowMarkets.length; ++i) {
            markets[mintMarkets.length + i] = borrowMarkets[i];
        }
    }

    function _marketImplementationFromInput(MarketContracts[12] memory markets, address market)
        internal
        pure
        returns (address implementation)
    {
        for (uint256 i; i < markets.length; ++i) {
            if (markets[i].market == market) return markets[i].marketImplementation;
        }
        revert("market not found in input");
    }

    function _allMarkets() internal view returns (MarketContracts[12] memory markets) {
        markets = [
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
            input.contracts.syrupUsdcMintMarket
        ];
    }
}
