// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {IMarket, Position, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleTestnet} from "@alto/deployments/testnet/contracts/OracleTestnet.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title SetupSyrupUsdcLiquidationTestEnv
/// @notice Sets up multiple liquidatable positions for syrupUSDC market on mainnet fork
/// @dev Run: NUM_POSITIONS=10 forge script script/SetupSyrupUsdcLiquidationTestEnv.s.sol --rpc-url http://localhost:8545 --broadcast -vvv
contract SetupSyrupUsdcLiquidationTestEnvScript is Script, StdCheats {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    address constant SYRUP_USDC_MARKET = 0x33B24510233281350bF8679A7c427d04db0ed208;
    address constant SYRUP_USDC = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;

    uint256 constant SYRUP_USDC_DECIMALS = 6;
    uint256 constant DUSD_DECIMALS = 18;

    // Price drop from ~1.15e48 to 0.8e48 makes positions liquidatable
    uint256 constant LIQUIDATABLE_ORACLE_PRICE = 0.8e48;

    uint256 constant MIN_COLLATERAL = 1 * 10 ** SYRUP_USDC_DECIMALS;
    uint256 constant MAX_COLLATERAL = 100_000 * 10 ** SYRUP_USDC_DECIMALS;
    uint256 constant INITIAL_LIQUIDITY = 10_000_000 ether;

    IMarket market = IMarket(SYRUP_USDC_MARKET);
    OracleTestnet newOracle;

    address[] public users;
    uint256[] public userPrivateKeys;

    function run() public {
        uint256 numPositions = vm.envOr("NUM_POSITIONS", uint256(5));

        console.log("=====================================");
        console.log("SyrupUSDC Liquidation Test Environment");
        console.log("=====================================");
        console.log("Positions to create:", numPositions);
        console.log("Market:", SYRUP_USDC_MARKET);
        console.log("=====================================");

        _supplyInitialLiquidity();
        _createPositions(numPositions);
        _deployOracleAndMakePositionsLiquidatable();
        _verifyPositionsAreLiquidatable();
    }

    function _supplyInitialLiquidity() internal {
        console.log("\n--- Supplying initial liquidity ---");

        address liquidityProvider = address(0x1111111111111111111111111111111111111111);
        deal(DUSD, liquidityProvider, INITIAL_LIQUIDITY);

        vm.startPrank(liquidityProvider);
        IERC20(DUSD).approve(SYRUP_USDC_MARKET, INITIAL_LIQUIDITY);
        market.addSupply(INITIAL_LIQUIDITY, 0, liquidityProvider);
        vm.stopPrank();

        console.log("Supplied:", INITIAL_LIQUIDITY / 1e18, "DUSD");
    }

    function _createPositions(uint256 numPositions) internal {
        console.log("\n--- Creating positions ---");

        for (uint256 i = 0; i < numPositions; i++) {
            uint256 userPk = uint256(keccak256(abi.encodePacked(i, block.timestamp)));
            address user = vm.addr(userPk);

            users.push(user);
            userPrivateKeys.push(userPk);

            uint256 randomSeed = uint256(keccak256(abi.encodePacked(i, block.timestamp, block.number)));
            uint256 collateralAmount = MIN_COLLATERAL + (randomSeed % (MAX_COLLATERAL - MIN_COLLATERAL + 1));

            console.log("\nPosition", i + 1, "- User:", user);
            console.log("Collateral:", collateralAmount / 10 ** SYRUP_USDC_DECIMALS, "syrupUSDC");

            _fundAndCreatePosition(user, collateralAmount);
        }
    }

    function _fundAndCreatePosition(address user, uint256 collateralAmount) internal {
        uint256 currentOraclePrice = IOracle(market.oracle()).getPrice();
        uint256 maxLtv = market.maxLtv();

        uint256 collateralValueInDusd =
            collateralAmount.divideWithRounding(currentOraclePrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowAmount = collateralValueInDusd.multiplyWithPrecision(maxLtv);
        uint256 borrowAmount = maxBorrowAmount * 95 / 100; // 95% of max LTV

        console.log("Borrow:", borrowAmount / 1e18, "DUSD");

        deal(SYRUP_USDC, user, collateralAmount);

        vm.startPrank(user);
        IERC20(SYRUP_USDC).approve(SYRUP_USDC_MARKET, type(uint256).max);
        market.addCollateral(collateralAmount, user);
        market.borrow(borrowAmount, 0, user, user, "");
        vm.stopPrank();

        require(_isSolvent(user), "Position should be solvent after creation");
    }

    function _deployOracleAndMakePositionsLiquidatable() internal {
        console.log("\n--- Deploying new oracle ---");

        address marketOwner = Ownable(SYRUP_USDC_MARKET).owner();

        vm.startPrank(marketOwner);
        newOracle = new OracleTestnet(marketOwner);
        newOracle.setPrice(LIQUIDATABLE_ORACLE_PRICE);
        market.setOracle(address(newOracle));
        vm.stopPrank();

        console.log("Oracle deployed:", address(newOracle));
        console.log("Price set to:", LIQUIDATABLE_ORACLE_PRICE);
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
        uint256 collateralPrice = IOracle(market.oracle()).getPrice();
        Position memory pos = market.position(user);

        uint256 collateralValue =
            uint256(pos.collateralAssets).divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(market.maxLtv());

        Balance memory totalBorrowed = market.totalBorrowed();
        uint256 borrowValue = uint256(pos.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        return maxBorrowValue >= borrowValue;
    }
}
