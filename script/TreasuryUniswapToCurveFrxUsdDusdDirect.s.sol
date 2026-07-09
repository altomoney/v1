// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FRXUSD_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

interface INonfungiblePositionManager {
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);
}

interface ICurvePool {
    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount) external returns (uint256);
}

struct TreasurySafeTx {
    address to;
    bytes data;
}

struct DirectMigrationParams {
    uint128 position1Liquidity;
    uint128 position2Liquidity;
    uint256 position1Dusd;
    uint256 position1FrxUsd;
    uint256 position2Dusd;
    uint256 position2FrxUsd;
    uint256 position1DecreaseAmount0Min;
    uint256 position1DecreaseAmount1Min;
    uint256 position2DecreaseAmount0Min;
    uint256 position2DecreaseAmount1Min;
    uint256 totalDusd;
    uint256 totalFrxUsd;
    uint256 curveMinMintAmount;
}

/// @title Treasury Uniswap frxUSD/DUSD LP to Curve (Direct)
/// @notice Generates Safe txs to unwind two Uniswap V3 positions and deposit received amounts into Curve as-is
/// @dev Run with `forge script script/TreasuryUniswapToCurveFrxUsdDusdDirect.s.sol:TreasuryUniswapToCurveFrxUsdDusdDirectScript --rpc-url ethereum -vvvv`
/// @dev WARNING: Execute the generated Safe batch promptly after generation. Uniswap position
///      liquidity, accrued fees, and pool price move with every swap
contract TreasuryUniswapToCurveFrxUsdDusdDirectScript is Script {
    address constant TREASURY_MULTISIG = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant FRXUSD_DUSD_UNISWAP_POOL = 0x78b8F4abAEaC80F5c8c932A0d42Ba0F14b6820bc;
    address constant UNISWAP_V3_NPM = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant FRXUSD_DUSD_CURVE_POOL = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;

    uint256 constant POSITION_ID_1 = 1310034;
    uint256 constant POSITION_ID_2 = 1310035;

    /// @dev 1% slippage tolerance on Uniswap decreaseLiquidity principal amounts
    uint256 constant UNISWAP_SLIPPAGE_BPS = 100;

    /// @dev 0.1% slippage tolerance on Curve LP mint (same convention as treasury migration script)
    uint256 constant CURVE_SLIPPAGE_BPS = 10;

    string constant SAFE_BATCH_NAME = "treasury-uniswap-to-curve-frxusd-dusd-direct";
    string constant OUTPUT_DIR = "contracts/deployments/ethereum-mainnet/output";

    function run() public {
        DirectMigrationParams memory params = computeParams();
        TreasurySafeTx[] memory txs = getSafeTransactions(params);

        console.log("=== Treasury Uniswap -> Curve frxUSD/DUSD (Direct) ===");
        console.log("");
        console.log("*** WARNING: Execute this Safe batch immediately after generation. ***");
        console.log("*** Uniswap liquidity/fees and pool price drift with mainnet activity. ***");
        console.log("");
        console.log("Treasury Multisig:", TREASURY_MULTISIG);
        console.log("Uniswap pool:", FRXUSD_DUSD_UNISWAP_POOL);
        console.log("Position IDs:", POSITION_ID_1, POSITION_ID_2);
        console.log("Curve pool:", FRXUSD_DUSD_CURVE_POOL);
        console.log("");
        console.log("Position 1 liquidity:", uint256(params.position1Liquidity));
        console.log("Position 1 DUSD (principal + fees):", params.position1Dusd);
        console.log("Position 1 frxUSD (principal + fees):", params.position1FrxUsd);
        console.log("Position 1 decrease DUSD min:", params.position1DecreaseAmount0Min);
        console.log("Position 1 decrease frxUSD min:", params.position1DecreaseAmount1Min);
        console.log("Position 2 liquidity:", uint256(params.position2Liquidity));
        console.log("Position 2 DUSD (principal + fees):", params.position2Dusd);
        console.log("Position 2 frxUSD (principal + fees):", params.position2FrxUsd);
        console.log("Position 2 decrease DUSD min:", params.position2DecreaseAmount0Min);
        console.log("Position 2 decrease frxUSD min:", params.position2DecreaseAmount1Min);
        console.log("Total DUSD from Uniswap:", params.totalDusd);
        console.log("Total frxUSD from Uniswap:", params.totalFrxUsd);
        console.log("Curve min LP mint:", params.curveMinMintAmount);
        console.log("Transaction count:", txs.length);

        vm.writeFile(
            string.concat(OUTPUT_DIR, "/safe-tx-", SAFE_BATCH_NAME, ".json"),
            _buildSafeBatchJson(SAFE_BATCH_NAME, txs)
        );

        console.log("\nSafe TX Builder JSON written:");
        console.log("  safe-tx-%s.json", SAFE_BATCH_NAME);
    }

    /// @dev Simulates Uniswap unwind and Curve deposit on the forked mainnet state used by `forge script`.
    function computeParams() public returns (DirectMigrationParams memory params) {
        uint256 snapshot = vm.snapshotState();

        uint256 dusdBefore = IERC20(DUSD).balanceOf(TREASURY_MULTISIG);
        uint256 frxUsdBefore = IERC20(FRXUSD_MAINNET).balanceOf(TREASURY_MULTISIG);

        (
            params.position1Liquidity,
            params.position1DecreaseAmount0Min,
            params.position1DecreaseAmount1Min,
            params.position1Dusd,
            params.position1FrxUsd
        ) = _simulateUnwind(POSITION_ID_1);
        (
            params.position2Liquidity,
            params.position2DecreaseAmount0Min,
            params.position2DecreaseAmount1Min,
            params.position2Dusd,
            params.position2FrxUsd
        ) = _simulateUnwind(POSITION_ID_2);

        params.totalDusd = IERC20(DUSD).balanceOf(TREASURY_MULTISIG) - dusdBefore;
        params.totalFrxUsd = IERC20(FRXUSD_MAINNET).balanceOf(TREASURY_MULTISIG) - frxUsdBefore;

        require(params.totalDusd > 0 && params.totalFrxUsd > 0, "no liquidity to migrate");

        uint256 expectedLpMint = _simulateCurveDeposit(params.totalDusd, params.totalFrxUsd);
        params.curveMinMintAmount = expectedLpMint - (expectedLpMint * CURVE_SLIPPAGE_BPS / 10_000);

        vm.revertToState(snapshot);
    }

    function getSafeTransactions(DirectMigrationParams memory params)
        public
        view
        returns (TreasurySafeTx[] memory txs)
    {
        txs = new TreasurySafeTx[](7);

        txs[0] = _decreaseLiquidityTx(
            POSITION_ID_1,
            params.position1Liquidity,
            params.position1DecreaseAmount0Min,
            params.position1DecreaseAmount1Min
        );
        txs[1] = _collectTx(POSITION_ID_1);
        txs[2] = _decreaseLiquidityTx(
            POSITION_ID_2,
            params.position2Liquidity,
            params.position2DecreaseAmount0Min,
            params.position2DecreaseAmount1Min
        );
        txs[3] = _collectTx(POSITION_ID_2);

        txs[4] = TreasurySafeTx({
            to: FRXUSD_MAINNET,
            data: abi.encodeWithSelector(IERC20.approve.selector, FRXUSD_DUSD_CURVE_POOL, params.totalFrxUsd)
        });
        txs[5] = TreasurySafeTx({
            to: DUSD,
            data: abi.encodeWithSelector(IERC20.approve.selector, FRXUSD_DUSD_CURVE_POOL, params.totalDusd)
        });

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = params.totalFrxUsd;
        amounts[1] = params.totalDusd;

        txs[6] = TreasurySafeTx({
            to: FRXUSD_DUSD_CURVE_POOL,
            data: abi.encodeWithSelector(
                ICurvePool.add_liquidity.selector, amounts, params.curveMinMintAmount
            )
        });
    }

    function _simulateUnwind(uint256 tokenId)
        internal
        returns (
            uint128 liquidity,
            uint256 amount0Min,
            uint256 amount1Min,
            uint256 total0,
            uint256 total1
        )
    {
        (,,,,,,, liquidity,,,,) = INonfungiblePositionManager(UNISWAP_V3_NPM).positions(tokenId);

        vm.startPrank(TREASURY_MULTISIG);

        uint256 decrease0;
        uint256 decrease1;
        if (liquidity > 0) {
            (decrease0, decrease1) = INonfungiblePositionManager(UNISWAP_V3_NPM).decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 1 hours
                })
            );
        }

        amount0Min = _minAfterSlippage(decrease0);
        amount1Min = _minAfterSlippage(decrease1);

        (total0, total1) = INonfungiblePositionManager(UNISWAP_V3_NPM).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: TREASURY_MULTISIG,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        vm.stopPrank();
    }

    function _simulateCurveDeposit(uint256 dusdAmount, uint256 frxUsdAmount) internal returns (uint256 lpMinted) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = frxUsdAmount;
        amounts[1] = dusdAmount;

        vm.startPrank(TREASURY_MULTISIG);
        IERC20(FRXUSD_MAINNET).approve(FRXUSD_DUSD_CURVE_POOL, frxUsdAmount);
        IERC20(DUSD).approve(FRXUSD_DUSD_CURVE_POOL, dusdAmount);
        lpMinted = ICurvePool(FRXUSD_DUSD_CURVE_POOL).add_liquidity(amounts, 0);
        vm.stopPrank();
    }

    function _decreaseLiquidityTx(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal view returns (TreasurySafeTx memory tx_) {
        tx_ = TreasurySafeTx({
            to: UNISWAP_V3_NPM,
            data: abi.encodeWithSelector(
                INonfungiblePositionManager.decreaseLiquidity.selector,
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    deadline: block.timestamp + 1 hours
                })
            )
        });
    }

    function _minAfterSlippage(uint256 amount) internal pure returns (uint256) {
        return amount - (amount * UNISWAP_SLIPPAGE_BPS / 10_000);
    }

    function _collectTx(uint256 tokenId) internal pure returns (TreasurySafeTx memory tx_) {
        tx_ = TreasurySafeTx({
            to: UNISWAP_V3_NPM,
            data: abi.encodeWithSelector(
                INonfungiblePositionManager.collect.selector,
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: TREASURY_MULTISIG,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            )
        });
    }

    function _buildSafeBatchJson(string memory name, TreasurySafeTx[] memory txs)
        internal
        pure
        returns (string memory)
    {
        string memory json = string.concat(
            '{"version":"1.0","chainId":"1","meta":{"name":"',
            name,
            '","txBuilderVersion":"1.16.5"},"transactions":['
        );

        for (uint256 i = 0; i < txs.length; ++i) {
            if (i > 0) {
                json = string.concat(json, ",");
            }
            json = string.concat(
                json,
                '{"to":"',
                vm.toString(txs[i].to),
                '","value":"0","data":"',
                vm.toString(txs[i].data),
                '","contractMethod":null,"contractInputsValues":null}'
            );
        }

        return string.concat(json, "]}");
    }
}
