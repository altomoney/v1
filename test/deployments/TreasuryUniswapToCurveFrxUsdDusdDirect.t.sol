// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";
import {
    TreasuryUniswapToCurveFrxUsdDusdDirectScript,
    DirectMigrationParams,
    INonfungiblePositionManager
} from "../../script/TreasuryUniswapToCurveFrxUsdDusdDirect.s.sol";

interface ICurvePool {
    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount) external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract TreasuryUniswapToCurveFrxUsdDusdDirectTest is Test {
    address constant TREASURY_MULTISIG = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant UNISWAP_V3_NPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant FRXUSD_DUSD_CURVE_POOL = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;

    uint256 constant POSITION_ID_1 = 1310034;
    uint256 constant POSITION_ID_2 = 1310035;

    TreasuryUniswapToCurveFrxUsdDusdDirectScript internal script;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("ethereum"));
        script = new TreasuryUniswapToCurveFrxUsdDusdDirectScript();
    }

    function test_computeParams_matchesOnchainPositions() public {
        DirectMigrationParams memory params = script.computeParams();

        (,,,,,,, uint128 liq1,,,,) = INonfungiblePositionManager(UNISWAP_V3_NPM).positions(POSITION_ID_1);
        (,,,,,,, uint128 liq2,,,,) = INonfungiblePositionManager(UNISWAP_V3_NPM).positions(POSITION_ID_2);

        assertEq(params.position1Liquidity, liq1, "position 1 liquidity mismatch");
        assertEq(params.position2Liquidity, liq2, "position 2 liquidity mismatch");
        assertGt(params.totalDusd, 0, "expected DUSD from Uniswap");
        assertGt(params.totalFrxUsd, 0, "expected frxUSD from Uniswap");
        assertEq(
            params.totalDusd,
            params.position1Dusd + params.position2Dusd,
            "total DUSD should equal per-position sum"
        );
        assertEq(
            params.totalFrxUsd,
            params.position1FrxUsd + params.position2FrxUsd,
            "total frxUSD should equal per-position sum"
        );
        assertGt(params.curveMinMintAmount, 0, "expected curve LP mint");

        console.log("total DUSD", params.totalDusd);
        console.log("total frxUSD", params.totalFrxUsd);
        console.log("curve min LP", params.curveMinMintAmount);
    }

    function test_migrateUniswapToCurveDirect() public {
        DirectMigrationParams memory params = script.computeParams();

        uint256 dusdBefore = IERC20(DUSD).balanceOf(TREASURY_MULTISIG);
        uint256 frxUsdBefore = IERC20(FRXUSD_MAINNET).balanceOf(TREASURY_MULTISIG);
        uint256 curveLpBefore = ICurvePool(FRXUSD_DUSD_CURVE_POOL).balanceOf(TREASURY_MULTISIG);

        vm.startPrank(TREASURY_MULTISIG);

        if (params.position1Liquidity > 0) {
            INonfungiblePositionManager(UNISWAP_V3_NPM)
                .decreaseLiquidity(
                    INonfungiblePositionManager.DecreaseLiquidityParams({
                        tokenId: POSITION_ID_1,
                        liquidity: params.position1Liquidity,
                        amount0Min: params.position1DecreaseAmount0Min,
                        amount1Min: params.position1DecreaseAmount1Min,
                        deadline: block.timestamp + 1 hours
                    })
                );
        }
        INonfungiblePositionManager(UNISWAP_V3_NPM)
            .collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: POSITION_ID_1,
                    recipient: TREASURY_MULTISIG,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

        if (params.position2Liquidity > 0) {
            INonfungiblePositionManager(UNISWAP_V3_NPM)
                .decreaseLiquidity(
                    INonfungiblePositionManager.DecreaseLiquidityParams({
                        tokenId: POSITION_ID_2,
                        liquidity: params.position2Liquidity,
                        amount0Min: params.position2DecreaseAmount0Min,
                        amount1Min: params.position2DecreaseAmount1Min,
                        deadline: block.timestamp + 1 hours
                    })
                );
        }
        INonfungiblePositionManager(UNISWAP_V3_NPM)
            .collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: POSITION_ID_2,
                    recipient: TREASURY_MULTISIG,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

        assertEq(IERC20(DUSD).balanceOf(TREASURY_MULTISIG) - dusdBefore, params.totalDusd, "DUSD from Uniswap");
        assertEq(
            IERC20(FRXUSD_MAINNET).balanceOf(TREASURY_MULTISIG) - frxUsdBefore,
            params.totalFrxUsd,
            "frxUSD from Uniswap"
        );

        IERC20(FRXUSD_MAINNET).approve(FRXUSD_DUSD_CURVE_POOL, params.totalFrxUsd);
        IERC20(DUSD).approve(FRXUSD_DUSD_CURVE_POOL, params.totalDusd);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = params.totalFrxUsd;
        amounts[1] = params.totalDusd;

        uint256 lpMinted = ICurvePool(FRXUSD_DUSD_CURVE_POOL).add_liquidity(amounts, params.curveMinMintAmount);

        vm.stopPrank();

        (,,,,,,, uint128 liq1,,,,) = INonfungiblePositionManager(UNISWAP_V3_NPM).positions(POSITION_ID_1);
        (,,,,,,, uint128 liq2,,,,) = INonfungiblePositionManager(UNISWAP_V3_NPM).positions(POSITION_ID_2);
        assertEq(liq1, 0, "position 1 should have zero liquidity");
        assertEq(liq2, 0, "position 2 should have zero liquidity");

        assertEq(IERC20(DUSD).balanceOf(TREASURY_MULTISIG), dusdBefore, "all DUSD deposited to Curve");
        assertEq(IERC20(FRXUSD_MAINNET).balanceOf(TREASURY_MULTISIG), frxUsdBefore, "all frxUSD deposited to Curve");
        assertGe(lpMinted, params.curveMinMintAmount, "curve LP mint below minimum");
        assertEq(
            ICurvePool(FRXUSD_DUSD_CURVE_POOL).balanceOf(TREASURY_MULTISIG),
            curveLpBefore + lpMinted,
            "treasury curve LP balance"
        );
    }
}
