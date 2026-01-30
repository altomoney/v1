// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {IMarket, Position, Balance, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OracleTestnet} from "@alto/deployments/testnet/contracts/OracleTestnet.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    LiquidationConfiguration,
    IDcfDlbPriorityLiquidationEngine
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

string constant ADDRESSES_FILE =
    "./contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

/// @title SetupLiquidationTestEnv
/// @notice Sets up multiple liquidatable positions for any market on mainnet fork
/// @dev Run example:
///      MARKET=weth NUM_POSITIONS=5 MIN_COLLATERAL=1 MAX_COLLATERAL=100 forge script script/SetupLiquidationTestEnv.s.sol --rpc-url http://localhost:8545 --broadcast -vvv
///      MARKET=susde NUM_POSITIONS=10 MIN_COLLATERAL=1000 MAX_COLLATERAL=100000 forge script script/SetupLiquidationTestEnv.s.sol --rpc-url http://localhost:8545 --broadcast -vvv
/// @dev Environment variables:
///      - MARKET: Market name (weth, wsteth, meth, reth, tbtc, susde, wbtc, cbbtc) - required
///      - NUM_POSITIONS: Number of positions to create (default: 5)
///      - MIN_COLLATERAL: Minimum collateral in whole units (default: 1)
///      - MAX_COLLATERAL: Maximum collateral in whole units (default: 100)
contract SetupLiquidationTestEnvScript is Script, StdCheats {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    // Loaded from addresses.json
    address market;
    address dusd;
    address liquidationEngine;

    // Derived from market
    address collateralToken;
    uint256 collateralDecimals;

    // User-provided parameters
    uint256 minCollateral;
    uint256 maxCollateral;
    uint256 numPositions;

    // Calculated values
    uint256 liquidatableOraclePrice;
    uint256 initialLiquidity;

    OracleTestnet newOracle;
    address[] public users;
    uint256[] public userPrivateKeys;

    function run() public {
        string memory marketName = vm.envString("MARKET");
        numPositions = vm.envOr("NUM_POSITIONS", uint256(5));
        uint256 minCollateralUnits = vm.envOr("MIN_COLLATERAL", uint256(1));
        uint256 maxCollateralUnits = vm.envOr("MAX_COLLATERAL", uint256(100));

        console.log("=====================================");
        console.log("Liquidation Test Environment Setup");
        console.log("=====================================");
        console.log("Market:", marketName);
        console.log("Positions to create:", numPositions);
        console.log("Min collateral (units):", minCollateralUnits);
        console.log("Max collateral (units):", maxCollateralUnits);
        console.log("=====================================");

        _loadDeployment(marketName);
        _initializeMarketParams(minCollateralUnits, maxCollateralUnits);

        console.log("\nMarket address:", market);
        console.log("Collateral token:", collateralToken);
        console.log("Collateral decimals:", collateralDecimals);
        console.log("DUSD:", dusd);
        console.log("Liquidation engine:", liquidationEngine);

        _disablePriorityLiquidationIfEnabled();

        if (IMarket(market).MARKET_TYPE() == MarketType.BORROW) {
            _supplyInitialLiquidity();
        }

        _createPositions(numPositions);
        _deployOracleAndMakePositionsLiquidatable();
        _verifyPositionsAreLiquidatable();
    }

    function _loadDeployment(string memory marketName) internal {
        string memory json = vm.readFile(ADDRESSES_FILE);
        dusd = vm.parseJsonAddress(json, ".contracts.dusd");

        // Try mint market pattern first (e.g., wethMarket), then borrow market pattern (e.g., susdeBorrowMarket)
        string memory mintMarketKey = string.concat(".contracts.", marketName, "Market");
        string memory borrowMarketKey = string.concat(".contracts.", marketName, "BorrowMarket");

        // Try mint market pattern first
        try vm.parseJsonAddress(json, mintMarketKey) returns (address mintMarket) {
            if (mintMarket != address(0)) {
                market = mintMarket;
                liquidationEngine =
                    vm.parseJsonAddress(json, string.concat(".contracts.", marketName, "LiquidationEngine"));
            }
        } catch {}

        // If mint market not found, try borrow market pattern
        if (market == address(0)) {
            market = vm.parseJsonAddress(json, borrowMarketKey);
            liquidationEngine =
                vm.parseJsonAddress(json, string.concat(".contracts.", marketName, "BorrowLiquidationEngine"));
        }

        require(market != address(0), "Market not found in addresses.json");
        require(liquidationEngine != address(0), "Liquidation engine not found in addresses.json");

        // Get collateral token from market contract
        collateralToken = IMarket(market).collateralToken();
        collateralDecimals = IERC20Metadata(collateralToken).decimals();
    }

    function _initializeMarketParams(uint256 minCollateralUnits, uint256 maxCollateralUnits) internal {
        minCollateral = minCollateralUnits * 10 ** collateralDecimals;
        maxCollateral = maxCollateralUnits * 10 ** collateralDecimals;

        uint256 currentOraclePrice = IOracle(IMarket(market).oracle()).getPrice();
        liquidatableOraclePrice = currentOraclePrice * 70 / 100;

        console.log("\nCurrent oracle price:", currentOraclePrice);
        console.log("Liquidatable oracle price (70%):", liquidatableOraclePrice);

        // 2x buffer for initial liquidity (only used for BORROW markets)
        uint256 maxBorrowPerPosition =
            maxCollateral.divideWithRounding(currentOraclePrice, LENDING_ORACLE_PRICE_PRECISION, false);
        initialLiquidity = maxBorrowPerPosition * numPositions * 2;
    }

    function _disablePriorityLiquidationIfEnabled() internal {
        IDcfDlbPriorityLiquidationEngine engine = IDcfDlbPriorityLiquidationEngine(liquidationEngine);
        LiquidationConfiguration memory config = engine.liquidationConfiguration();

        if (!config.isEnabledPriorityLiquidation) {
            console.log("\nPriority liquidation already disabled");
            return;
        }

        console.log("\n--- Disabling priority liquidation ---");

        config.isEnabledPriorityLiquidation = false;

        vm.startPrank(Ownable(liquidationEngine).owner());
        DlbDcfPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(config);
        vm.stopPrank();

        console.log("Priority liquidation disabled");
    }

    function _supplyInitialLiquidity() internal {
        console.log("\n--- Supplying initial liquidity (BORROW market) ---");

        address liquidityProvider = address(0x1111111111111111111111111111111111111111);
        deal(dusd, liquidityProvider, initialLiquidity);

        vm.startPrank(liquidityProvider);
        IERC20(dusd).approve(market, initialLiquidity);
        IMarket(market).addSupply(initialLiquidity, 0, liquidityProvider);
        vm.stopPrank();

        console.log("Supplied:", initialLiquidity / 1e18, "DUSD");
    }

    function _createPositions(uint256 _numPositions) internal {
        console.log("\n--- Creating positions ---");

        for (uint256 i = 0; i < _numPositions; i++) {
            uint256 userPk = uint256(keccak256(abi.encodePacked(i, block.timestamp)));
            address user = vm.addr(userPk);

            users.push(user);
            userPrivateKeys.push(userPk);

            uint256 randomSeed = uint256(keccak256(abi.encodePacked(i, block.timestamp, block.number)));
            uint256 collateralAmount = minCollateral + (randomSeed % (maxCollateral - minCollateral + 1));

            console.log("\nPosition", i + 1, "- User:", user);
            console.log("Collateral:", collateralAmount / 10 ** collateralDecimals, "tokens");

            _fundAndCreatePosition(user, collateralAmount);
        }
    }

    function _fundAndCreatePosition(address user, uint256 collateralAmount) internal {
        IMarket market = IMarket(market);
        uint256 currentOraclePrice = IOracle(market.oracle()).getPrice();

        uint256 collateralValueInDusd =
            collateralAmount.divideWithRounding(currentOraclePrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 borrowAmount = collateralValueInDusd.multiplyWithPrecision(market.maxLtv()) * 95 / 100;

        console.log("Borrow:", borrowAmount / 1e18, "DUSD");

        deal(collateralToken, user, collateralAmount);

        vm.startPrank(user);
        IERC20(collateralToken).approve(address(market), type(uint256).max);
        market.addCollateral(collateralAmount, user);
        market.borrow(borrowAmount, 0, user, user, "");
        vm.stopPrank();

        require(_isSolvent(user), "Position should be solvent after creation");
    }

    function _deployOracleAndMakePositionsLiquidatable() internal {
        console.log("\n--- Deploying new oracle ---");

        address marketOwner = Ownable(market).owner();

        vm.startPrank(marketOwner);
        newOracle = new OracleTestnet(marketOwner);
        newOracle.setPrice(liquidatableOraclePrice);
        IMarket(market).setOracle(address(newOracle));
        vm.stopPrank();

        console.log("Oracle deployed:", address(newOracle));
        console.log("Price set to:", liquidatableOraclePrice);
    }

    function _verifyPositionsAreLiquidatable() internal view {
        console.log("\n--- Verifying liquidatable positions ---");

        uint256 liquidatableCount = 0;
        for (uint256 i = 0; i < users.length; i++) {
            bool solvent = _isSolvent(users[i]);
            if (!solvent) {
                liquidatableCount++;
                console.log("User", i + 1, users[i], "- LIQUIDATABLE");
            } else {
                console.log("User", i + 1, users[i], "- SOLVENT (unexpected!)");
            }
        }

        console.log("\nLiquidatable:", liquidatableCount, "/", users.length);
        require(liquidatableCount == users.length, "All positions should be liquidatable");
    }

    /// @dev Mirrors _isSolvent from AltoBaseMarket.sol
    function _isSolvent(address user) internal view returns (bool) {
        IMarket market = IMarket(market);
        uint256 collateralPrice = IOracle(market.oracle()).getPrice();
        Position memory pos = market.position(user);
        Balance memory totalBorrowed = market.totalBorrowed();

        uint256 collateralValue =
            uint256(pos.collateralAssets).divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(market.maxLtv());
        uint256 borrowValue = uint256(pos.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        return maxBorrowValue >= borrowValue;
    }
}
