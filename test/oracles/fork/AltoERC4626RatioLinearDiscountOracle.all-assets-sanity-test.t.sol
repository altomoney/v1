// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {EthereumMainnetOracleDeployer} from "@alto/deployments/EthereumMainnetOracleDeployer.sol";
import {ILendingOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {console} from "forge-std/console.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

contract AltoERC4626RatioLinearDiscountOracleGetPriceForkTest is Test {
    using FixedPointMath for uint256;

    address internal OWNER = makeAddr("Alto-multisig");

    function test_GetPrice_PtReusd() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"), 25049751);

        uint256 price = ILendingOracle(EthereumMainnetOracleDeployer.deployPtReusdOracle(OWNER)).getPrice();

        // PT-reUSD has 6 decimals, DUSD has 18 decimals
        // outDecimals = 36 + 18 - 6 = 48
        // 1000 PT-reUSD tokens (1e9 base units) collateral value in DUSD:
        // collateralValue = 1e9 * price / 1e36

        uint256 collateral1000 = 1000e6;
        // according to _isSolvent in AltoBaseMarket.sol - this represents the value of 1000 PT-reUSD in borrow assets
        // in our case DUSD (or any other 18 decimals token)
        uint256 collateralValue1000 = collateral1000.divideWithRounding(price, LENDING_ORACLE_PRICE_PRECISION, false);
        // 1000 PT-reUSD should be worth ~$989 DUSD at the time of the fork

        assertEq(
            collateralValue1000,
            989582261303309648000,
            "Collateral value of 1000 PT-reUSD in DUSD should be 989582261303309648000"
        );
    }
}
