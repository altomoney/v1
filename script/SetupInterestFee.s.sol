// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {IMarket, IMarketStaticTypes} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {AltoBorrowMarket} from "@alto/lending/AltoBorrowMarket.sol";

string constant ADDRESSES_FILE =
    "./contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

uint256 constant COLLATERAL_BUFFER = 2;

/// @title SetupInterestFeeScript
/// @notice Tests interestFee behavior for borrow markets with same-block and different-block txs
/// @dev Run: MARKET=susde forge script script/SetupInterestFee.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vvv
contract SetupInterestFeeScript is Script, StdCheats {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    uint256 constant NUM_USERS = 10;
    uint256 constant INTEREST_FEE = 0.05 ether; // 5%
    uint256 constant BLOCKS_TO_FORWARD = 100;
    uint256 constant TIME_TO_FORWARD = 1200; // 20 minutes

    address market;
    address dusd;
    address timelock;

    address collateralToken;
    uint256 collateralDecimals;

    // Users
    address[NUM_USERS] users;

    function run() public {
        string memory marketName = vm.envString("MARKET");

        console.log("=========================================");
        console.log("  Interest Fee Test Script");
        console.log("=========================================");
        console.log("Market:", marketName);

        _loadDeployment(marketName);

        collateralToken = IMarket(market).collateralToken();
        collateralDecimals = IERC20Metadata(collateralToken).decimals();

        console.log("Market address:", market);
        console.log("Collateral token:", collateralToken);
        console.log("Collateral decimals:", collateralDecimals);
        console.log("DUSD:", dusd);
        console.log("Timelock:", timelock);

        _generateUsers();
        _runBorrowMarketTest();

        console.log("\n=========================================");
        console.log("  Test Script Completed Successfully");
        console.log("=========================================");
    }

    /// @dev Returns collateral amount (in collateral token base units) needed to borrow `borrowAmount` with buffer
    function _collateralForBorrow(uint256 borrowAmount) internal view returns (uint256) {
        uint256 oraclePrice = IOracle(IMarket(market).oracle()).getPrice();
        uint256 maxLtv = IMarket(market).maxLtv();
        uint256 collateralValueDusd = (borrowAmount * MATH_PRECISION) / maxLtv;
        return (collateralValueDusd * LENDING_ORACLE_PRICE_PRECISION * COLLATERAL_BUFFER) / oraclePrice;
    }

    function _loadDeployment(string memory marketName) internal {
        string memory json = vm.readFile(ADDRESSES_FILE);
        dusd = vm.parseJsonAddress(json, ".contracts.dusd");
        timelock = vm.parseJsonAddress(json, ".contracts.timelock");

        string memory borrowKey = string.concat(".contracts.", marketName, "BorrowMarket");
        market = vm.parseJsonAddress(json, borrowKey);
        require(market != address(0), "Borrow market not found in addresses.json");
    }

    function _generateUsers() internal {
        for (uint256 i = 0; i < NUM_USERS; i++) {
            users[i] = vm.addr(uint256(keccak256(abi.encodePacked("interestFeeTestUser", i))));
        }
    }

    function _logMarketState(string memory label) internal view {
        console.log("Current block number:", block.number);
        console.log("Current timestamp:", block.timestamp);

        IMarketStaticTypes market = IMarketStaticTypes(market);
        (uint128 supplyAssets, uint128 supplyShares) = market.totalSupply();
        (uint128 borrowAssets, uint128 borrowShares) = market.totalBorrowed();

        console.log(string.concat("\n--- Market State: ", label, " ---"));
        console.log("  totalSupply  - assets:", supplyAssets, "shares:", supplyShares);
        console.log("  totalBorrowed - assets:", borrowAssets, "shares:", borrowShares);

        (uint128 feeSupplyShares,,) = market.position(market.feeRecipient());
        console.log("  feeRecipient supplyShares:", feeSupplyShares);
        console.log("  interestFee:", AltoBorrowMarket(address(market)).interestFee());
    }

    function _logUserPosition(uint256 idx) internal view {
        (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets) =
            IMarketStaticTypes(market).position(users[idx]);
        console.log(string.concat("  User ", vm.toString(idx + 1)), "- supplyShares:", supplyShares);
        console.log("    borrowShares:", borrowShares, "collateral:", collateralAssets);
    }

    // ─── Borrow Market Test ──────────────────────────────────────────────

    function _runBorrowMarketTest() internal {
        _enableInterestFee();
        _logMarketState("After enabling interestFee");

        _borrowMarketPhase1_SupplySameBlock();
        _logMarketState("After Phase 1 (supply same block)");

        _forwardBlocksAndTime();
        _logMarketState("After forwarding 100 blocks + 1200s (post-supply)");

        _borrowMarketPhase2_BorrowSameBlock();
        _logMarketState("After Phase 2 (borrow same block)");

        _forwardBlocksAndTime();
        _logMarketState("After forwarding 100 blocks + 1200s (post-borrow)");

        _borrowMarketPhase3_DifferentBlocks();
        _logMarketState("After Phase 3 (different blocks)");

        console.log("\n--- Final User Positions ---");
        for (uint256 i = 0; i < NUM_USERS; i++) {
            _logUserPosition(i);
        }
    }

    function _enableInterestFee() internal {
        console.log("\n=== Enabling interestFee (5%) on borrow market ===");

        uint256 currentFee = AltoBorrowMarket(market).interestFee();
        console.log("Current interestFee:", currentFee);

        vm.startPrank(timelock);
        AltoBorrowMarket(market).setInterestFee(INTEREST_FEE);
        vm.stopPrank();

        uint256 newFee = AltoBorrowMarket(market).interestFee();
        console.log("New interestFee:", newFee);
        require(newFee == INTEREST_FEE, "interestFee not set correctly");
    }

    function _borrowMarketPhase1_SupplySameBlock() internal {
        console.log("\n=== Phase 1: Supply DUSD (same block) - Users 1-5 ===");

        uint256 baseSupply = 5000 * 1e18; // 5000 DUSD

        for (uint256 i = 0; i < 5; i++) {
            uint256 supplyAmount = baseSupply + (i * 1000 * 1e18); // 5000, 6000, 7000, 8000, 9000 DUSD
            deal(dusd, users[i], supplyAmount);

            vm.startPrank(users[i]);
            IERC20(dusd).approve(market, supplyAmount);
            IMarket(market).addSupply(supplyAmount, 0, users[i]);
            vm.stopPrank();

            console.log(string.concat("  User ", vm.toString(i + 1), " supplied:"), supplyAmount / 1e18, "DUSD");
        }
    }

    function _borrowMarketPhase2_BorrowSameBlock() internal {
        console.log("\n=== Phase 2: Collateral + Borrow (same block) - Users 6-10 ===");

        uint256 baseBorrow = 1000 * 1e18; // 1000 DUSD

        for (uint256 i = 5; i < 10; i++) {
            uint256 borrowAmount = baseBorrow + ((i - 5) * 1000 * 1e18); // 1000, 2000, 3000, 4000, 5000 DUSD
            uint256 collateralAmount = _collateralForBorrow(borrowAmount);

            deal(collateralToken, users[i], collateralAmount);

            vm.startPrank(users[i]);
            IERC20(collateralToken).approve(market, collateralAmount);
            IMarket(market).addCollateral(collateralAmount, users[i]);
            IMarket(market).borrow(borrowAmount, 0, users[i], users[i], "");
            vm.stopPrank();

            console.log(
                string.concat("  User ", vm.toString(i + 1), " added collateral:"),
                collateralAmount / (10 ** collateralDecimals),
                "units"
            );
            console.log("    borrowed:", borrowAmount / 1e18, "DUSD");
        }
    }

    function _borrowMarketPhase3_DifferentBlocks() internal {
        console.log("\n=== Phase 3: Supply + Collateral + Borrow (different blocks) - Users 1-10 ===");

        for (uint256 i = 0; i < NUM_USERS; i++) {
            uint256 supplyAmount = 1000 * 1e18 + (i * 1000 * 1e18); // 1000 .. 10000 DUSD
            deal(dusd, users[i], supplyAmount);

            vm.startPrank(users[i]);
            IERC20(dusd).approve(market, supplyAmount);
            IMarket(market).addSupply(supplyAmount, 0, users[i]);
            vm.stopPrank();

            console.log(string.concat("  User ", vm.toString(i + 1), " supplied:"), supplyAmount / 1e18, "DUSD");

            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 12);

            uint256 borrowAmount = (500 + i * 100) * 1e18; // 500 .. 1400 DUSD
            uint256 collateralAmount = _collateralForBorrow(borrowAmount);
            deal(collateralToken, users[i], collateralAmount);

            vm.startPrank(users[i]);
            IERC20(collateralToken).approve(market, collateralAmount);
            IMarket(market).addCollateral(collateralAmount, users[i]);
            vm.stopPrank();

            console.log(
                string.concat("  User ", vm.toString(i + 1), " added collateral:"),
                collateralAmount / (10 ** collateralDecimals),
                "units"
            );

            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 12);

            vm.startPrank(users[i]);
            IMarket(market).borrow(borrowAmount, 0, users[i], users[i], "");
            vm.stopPrank();
            console.log("    borrowed:", borrowAmount / 1e18, "DUSD");

            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 12);

            _logMarketState(string.concat("After User ", vm.toString(i + 1), " (Phase 3)"));
        }
    }

    function _forwardBlocksAndTime() internal {
        console.log(
            string.concat(
                "\n>>> Forwarding ", vm.toString(BLOCKS_TO_FORWARD), " blocks + ", vm.toString(TIME_TO_FORWARD), "s"
            )
        );
        vm.roll(block.number + BLOCKS_TO_FORWARD);
        vm.warp(block.timestamp + TIME_TO_FORWARD);

        IMarket(market).accrueInterest();
    }
}
