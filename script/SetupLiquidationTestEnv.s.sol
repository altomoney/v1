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

uint256 constant TENDERLY_GAS_FUNDING_WEI = 1 ether;

/// @title SetupLiquidationTestEnv
/// @notice Sets up multiple liquidatable positions for any market on a Tenderly Virtual TestNet
/// @dev Run example (Tenderly Virtual TestNet):
///      MARKET=susde NUM_POSITIONS=3 MIN_COLLATERAL=1 MAX_COLLATERAL=100 forge script script/SetupLiquidationTestEnv.s.sol --rpc-url $TENDERLY_VIRTUAL_TESTNET_RPC --broadcast --unlocked --skip-simulation --slow -vvv
/// @dev Uses Tenderly Admin RPC (tenderly_setErc20Balance) to fund accounts; --unlocked
///      broadcasts unsigned txs from arbitrary addresses. Use --skip-simulation so the
///      broadcast runs after RPC balance updates are applied (simulation uses stale state).
///      See: https://docs.tenderly.co/virtual-testnets/admin-rpc
/// @dev Environment variables:
///      - MARKET: Market name (weth, wsteth, meth, reth, tbtc, susde, wbtc, cbbtc) - required
///      - NUM_POSITIONS: Number of positions to create (default: 5)
///      - MIN_COLLATERAL: Minimum collateral in whole units (default: 1)
///      - MAX_COLLATERAL: Maximum collateral in whole units (default: 100)
contract SetupLiquidationTestEnvScript is Script, StdCheats {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    address market;
    address dusd;
    address liquidationEngine;
    address collateralToken;
    uint256 collateralDecimals;
    uint256 minCollateral;
    uint256 maxCollateral;
    uint256 numPositions;
    uint256 liquidatableOraclePrice;
    uint256 initialLiquidity;
    OracleTestnet newOracle;
    address[] public users;

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
        uint256 maxBorrowPerPosition =
            maxCollateral.divideWithRounding(currentOraclePrice, LENDING_ORACLE_PRICE_PRECISION, false);
        initialLiquidity = maxBorrowPerPosition * numPositions * 2 * 102 / 100;
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

        address owner = Ownable(liquidationEngine).owner();
        _tenderlySetBalance(owner, TENDERLY_GAS_FUNDING_WEI);
        vm.startBroadcast(owner);
        DlbDcfPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(config);
        vm.stopBroadcast();

        console.log("Priority liquidation disabled");
    }

    function _supplyInitialLiquidity() internal {
        console.log("\n--- Supplying initial liquidity (BORROW market) ---");

        address liquidityProvider = address(0x1111111111111111111111111111111111111111);
        uint256 lpDusdBalance = initialLiquidity * 102 / 100;
        _tenderlySetErc20Balance(dusd, liquidityProvider, lpDusdBalance);
        _tenderlySetBalance(liquidityProvider, TENDERLY_GAS_FUNDING_WEI);
        deal(dusd, liquidityProvider, lpDusdBalance);

        vm.startBroadcast(liquidityProvider);
        IERC20(dusd).approve(market, initialLiquidity);
        IMarket(market).addSupply(initialLiquidity, 0, liquidityProvider);
        vm.stopBroadcast();

        console.log("Supplied:", initialLiquidity / 1e18, "DUSD");
    }

    function _createPositions(uint256 _numPositions) internal {
        console.log("\n--- Creating positions ---");

        for (uint256 i = 0; i < _numPositions; i++) {
            address user = vm.addr(uint256(keccak256(abi.encodePacked(i, block.number))));
            users.push(user);
            uint256 randomSeed = uint256(keccak256(abi.encodePacked(i, block.timestamp, block.number)));
            uint256 collateralAmount = minCollateral + (randomSeed % (maxCollateral - minCollateral + 1));

            console.log("\nPosition", i + 1, "- User:", user);
            console.log("Collateral:", collateralAmount / 10 ** collateralDecimals, "tokens");

            _fundAndCreatePosition(user, collateralAmount);
        }
    }

    function _fundAndCreatePosition(address user, uint256 collateralAmount) internal {
        IMarket _market = IMarket(market);
        uint256 currentOraclePrice = IOracle(_market.oracle()).getPrice();

        uint256 collateralValueInDusd =
            collateralAmount.divideWithRounding(currentOraclePrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 borrowAmount = collateralValueInDusd.multiplyWithPrecision(_market.maxLtv()) * 95 / 100;

        console.log("Borrow:", borrowAmount / 1e18, "DUSD");
        uint256 collateralBalanceToSet = collateralAmount * 102 / 100;
        _tenderlySetErc20Balance(collateralToken, user, collateralBalanceToSet);
        _tenderlySetBalance(user, TENDERLY_GAS_FUNDING_WEI);
        // Foundry runs the script in a local EVM fork (state copied from RPC). deal() updates that fork so
        // addCollateral succeed during the run. tenderly_setErc20Balance above updates Tenderly so the broadcast tx succeeds on-chain.
        deal(collateralToken, user, collateralBalanceToSet);

        vm.startBroadcast(user);
        IERC20(collateralToken).approve(address(_market), type(uint256).max);
        _market.addCollateral(collateralAmount, user);
        _market.borrow(borrowAmount, 0, user, user, "");
        vm.stopBroadcast();

        require(_isSolvent(user), "Position should be solvent after creation");
    }

    function _deployOracleAndMakePositionsLiquidatable() internal {
        console.log("\n--- Deploying new oracle ---");

        address marketOwner = Ownable(market).owner();
        _tenderlySetBalance(marketOwner, TENDERLY_GAS_FUNDING_WEI);

        vm.startBroadcast(marketOwner);
        newOracle = new OracleTestnet(marketOwner);
        newOracle.setPrice(liquidatableOraclePrice);
        IMarket(market).setOracle(address(newOracle));
        vm.stopBroadcast();

        console.log("Oracle deployed:", address(newOracle));
        console.log("Price set to:", liquidatableOraclePrice);
    }

    function _verifyPositionsAreLiquidatable() internal view {
        console.log("\n--- Verifying liquidatable positions ---");

        uint256 liquidatableCount = 0;
        for (uint256 i = 0; i < users.length; i++) {
            if (!_isSolvent(users[i])) {
                liquidatableCount++;
                console.log("User", i + 1, users[i], "- LIQUIDATABLE");
            } else {
                console.log("User", i + 1, users[i], "- SOLVENT (unexpected!)");
            }
        }
        console.log("\nLiquidatable:", liquidatableCount, "/", users.length);
        require(liquidatableCount == users.length, "All positions should be liquidatable");
    }

    function _tenderlySetBalance(address wallet, uint256 amountWei) internal {
        vm.rpc("tenderly_setBalance", string.concat('["', vm.toString(wallet), '","', _toCompactHex(amountWei), '"]'));
    }

    function _tenderlySetErc20Balance(address token, address wallet, uint256 amount) internal {
        vm.rpc(
            "tenderly_setErc20Balance",
            string.concat('["', vm.toString(token), '","', vm.toString(wallet), '","', _toCompactHex(amount), '"]')
        );
    }

    function _toCompactHex(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0x0";
        uint256 temp = value;
        uint256 length;
        while (temp != 0) {
            length++;
            temp >>= 4;
        }
        bytes memory buf = new bytes(2 + length);
        buf[0] = "0";
        buf[1] = "x";
        temp = value;
        for (uint256 i = 2 + length; i > 2;) {
            unchecked {
                i--;
                uint8 nibble = uint8(temp & 0xf);
                buf[i] = nibble < 10 ? bytes1(uint8(0x30 + nibble)) : bytes1(uint8(0x57 + nibble));
                temp >>= 4;
            }
        }
        return string(buf);
    }

    function _isSolvent(address user) internal view returns (bool) {
        IMarket _market = IMarket(market);
        uint256 collateralPrice = IOracle(_market.oracle()).getPrice();
        Position memory pos = _market.position(user);
        Balance memory totalBorrowed = _market.totalBorrowed();

        uint256 collateralValue =
            uint256(pos.collateralAssets).divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(_market.maxLtv());
        uint256 borrowValue = uint256(pos.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        return maxBorrowValue >= borrowValue;
    }
}
