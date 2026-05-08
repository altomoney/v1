// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

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

interface INonfungiblePositionManagerTreasury {
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

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

interface ICurveFrxUsdDusdPool {
    function coins(uint256 i) external view returns (address);

    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
        external
        returns (uint256);
}

/// @title GenerateTreasuryCurveRebalance
/// @notice Generates Safe Transaction Builder JSON for the treasury Uniswap -> Curve rebalance.
/// @dev command to run: forge script script/GenerateTreasuryCurveRebalance.s.sol:GenerateTreasuryCurveRebalance  --rpc-url ethereum
contract GenerateTreasuryCurveRebalance is Script {
    struct PositionConfig {
        string label;
        uint256 tokenId;
        uint256 reductionBps;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct CurveConfig {
        uint256 frxUsdAmount;
        uint256 dusdAmount;
        uint256 minMintAmount;
    }

    address constant TREASURY = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant FRAX_CUSTODIAN = 0x4F95C5bA0C7c69FB2f9340E190cCeE890B3bd87c;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant FRXUSD_USM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address constant USDC_USM = 0x2dE874B83f4d0a64D81A16f2e050bcB55f118398;

    uint256 constant NARROW_TOKEN_ID = 1_150_307;
    uint256 constant WIDE_TOKEN_ID = 1_150_308;
    uint256 constant BPS = 10_000;
    uint256 constant TOKEN_DECIMAL_SCALE = 1e12; // 18-decimal frxUSD/DUSD to 6-decimal USDC.

    string constant OUTPUT_FILE = "contracts/deployments/ethereum-mainnet/output/safe-tx-treasury-curve-rebalance.json";

    function run() public {
        string memory rpcUrl = vm.rpcUrl("ethereum");
        vm.createSelectFork(rpcUrl);

        address curvePool = vm.promptAddress("Curve frxUSD/DUSD pool address (mainnet checksummed hex)");
        require(curvePool.code.length > 0, "Invalid curve pool address");

        (address curveCoin0, address curveCoin1) = _readCurveCoins(curvePool);
        require(
            (curveCoin0 == FRXUSD && curveCoin1 == DUSD) || (curveCoin0 == DUSD && curveCoin1 == FRXUSD),
            "curve pool coins[0,1] must be frxUSD and DUSD"
        );

        uint256 deadline = block.timestamp
            + vm.promptUint("Deadline hours from now - this deadline is set for uniswap remove liquidity transactions")
            * 1 hours;

        PositionConfig memory narrow = _readPositionConfig("narrow tick range", NARROW_TOKEN_ID);
        PositionConfig memory wide = _readPositionConfig("wide tick range", WIDE_TOKEN_ID);
        CurveConfig memory curveConfig = CurveConfig({
            frxUsdAmount: vm.promptUint("Curve frxUSD amount to deposit (18 decimals)"),
            dusdAmount: vm.promptUint("Curve DUSD amount to deposit (18 decimals)"),
            minMintAmount: vm.promptUint(
                "Curve min LP tokens to mint - Please simulate it on curve UI and then set this value"
            )
        });

        // NOTE: This is DUSD  expected to be received from uniswap and sent back to USDC USM
        // @dev We may receive extra DUSD from uniswap due to slippage, so there can be residue
        uint256 extraDusd = narrow.amount0Min + wide.amount0Min;

        address[] memory to = new address[](14);
        bytes[] memory data = new bytes[](14);
        string[] memory labels = new string[](14);
        uint256 idx;

        _appendDecreaseLiquidity(to, data, labels, idx++, narrow, deadline);
        _appendCollect(to, data, labels, idx++, narrow);
        _appendDecreaseLiquidity(to, data, labels, idx++, wide, deadline);
        _appendCollect(to, data, labels, idx++, wide);

        uint256 usdcForCurveDusd = curveConfig.dusdAmount / TOKEN_DECIMAL_SCALE;
        uint256 usdcForCurveFrxUsd = curveConfig.frxUsdAmount / TOKEN_DECIMAL_SCALE;
        uint256 totalUsdcForFrax = usdcForCurveDusd + usdcForCurveFrxUsd;

        labels[idx] = "approve USDC to fraxCustodian";
        to[idx] = USDC;
        data[idx] = abi.encodeCall(IERC20.approve, (FRAX_CUSTODIAN, totalUsdcForFrax));
        ++idx;

        labels[idx] = "fraxCustodian.deposit USDC for DUSD leg";
        to[idx] = FRAX_CUSTODIAN;
        data[idx] = abi.encodeCall(IERC4626.deposit, (usdcForCurveDusd, TREASURY));
        ++idx;

        labels[idx] = "approve frxUSD to frxUSD USM";
        to[idx] = FRXUSD;
        data[idx] = abi.encodeCall(IERC20.approve, (FRXUSD_USM, curveConfig.dusdAmount));
        ++idx;

        labels[idx] = "frxUSD USM sellAsset frxUSD for DUSD";
        to[idx] = FRXUSD_USM;
        data[idx] = abi.encodeCall(IUsm.sellAsset, (curveConfig.dusdAmount, TREASURY));
        ++idx;

        labels[idx] = "fraxCustodian.deposit frxUSD for frxUSD leg";
        to[idx] = FRAX_CUSTODIAN;
        data[idx] = abi.encodeCall(IERC4626.deposit, (usdcForCurveFrxUsd, TREASURY));
        ++idx;

        labels[idx] = "approve frxUSD to Curve";
        to[idx] = FRXUSD;
        data[idx] = abi.encodeCall(IERC20.approve, (curvePool, curveConfig.frxUsdAmount));
        ++idx;

        labels[idx] = "approve DUSD to Curve";
        to[idx] = DUSD;
        data[idx] = abi.encodeCall(IERC20.approve, (curvePool, curveConfig.dusdAmount));
        ++idx;

        uint256[] memory curveAmounts = _curveAddLiquidityAmounts(curveCoin0, curveConfig);

        labels[idx] = "Curve add_liquidity frxUSD and DUSD";
        to[idx] = curvePool;
        data[idx] =
            abi.encodeCall(ICurveFrxUsdDusdPool.add_liquidity, (curveAmounts, curveConfig.minMintAmount, TREASURY));
        ++idx;

        labels[idx] = "approve extra DUSD received from uniswap positions to USDC USM";
        to[idx] = DUSD;
        data[idx] = abi.encodeCall(IERC20.approve, (USDC_USM, extraDusd));
        ++idx;

        labels[idx] = "USDC USM buyAsset with extra DUSD received from uniswap positions to USDC";
        to[idx] = USDC_USM;
        data[idx] = abi.encodeCall(IUsm.buyAsset, (extraDusd / TOKEN_DECIMAL_SCALE, TREASURY));
        ++idx;

        require(idx == to.length, "transaction count mismatch");

        _logTransactions(labels, to, data);
        _writeSafeBatch(to, data);
    }

    function _readCurveCoins(address pool) internal view returns (address coin0, address coin1) {
        ICurveFrxUsdDusdPool p = ICurveFrxUsdDusdPool(pool);
        coin0 = p.coins(0);
        coin1 = p.coins(1);
    }

    /// @notice `_amounts[i]` matches `pool.coins(i)` for a 2-coin pool.
    function _curveAddLiquidityAmounts(address curveCoin0, CurveConfig memory cfg)
        internal
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        if (curveCoin0 == FRXUSD) {
            amounts[0] = cfg.frxUsdAmount;
            amounts[1] = cfg.dusdAmount;
        } else {
            amounts[0] = cfg.dusdAmount;
            amounts[1] = cfg.frxUsdAmount;
        }
    }

    function _readPositionConfig(string memory label, uint256 tokenId) internal returns (PositionConfig memory cfg) {
        cfg.label = label;
        cfg.tokenId = tokenId;
        cfg.reductionBps = vm.promptUint(string.concat("Uniswap ", label, " reduction bps (10000 = 100%)"));
        cfg.amount0Min = vm.promptUint(
            string.concat(
                "Uniswap ", label, " amount0Min DUSD (18 decimals) - simulate it on uniswap UI and then set this value"
            )
        );
        cfg.amount1Min = vm.promptUint(
            string.concat(
                "Uniswap ", label, " amount1Min USDC (6 decimals) - simulate it on uniswap UI and then set this value"
            )
        );

        require(cfg.reductionBps <= BPS, "reduction bps too high");
    }

    function _appendDecreaseLiquidity(
        address[] memory to,
        bytes[] memory data,
        string[] memory labels,
        uint256 idx,
        PositionConfig memory cfg,
        uint256 deadline
    ) internal view {
        (address token0, address token1, uint128 currentLiquidity) = _positionTokensAndLiquidity(cfg.tokenId);
        require(token0 == DUSD, "unexpected Uniswap token0");
        require(token1 == USDC, "unexpected Uniswap token1");

        uint128 liquidityToRemove = uint128(uint256(currentLiquidity) * cfg.reductionBps / BPS);
        require(liquidityToRemove > 0, "zero liquidity to remove");

        DecreaseLiquidityParams memory params = DecreaseLiquidityParams({
            tokenId: cfg.tokenId,
            liquidity: liquidityToRemove,
            amount0Min: cfg.amount0Min,
            amount1Min: cfg.amount1Min,
            deadline: deadline
        });

        labels[idx] = string.concat("Uniswap decreaseLiquidity ", cfg.label);
        to[idx] = NONFUNGIBLE_POSITION_MANAGER;
        data[idx] = abi.encodeCall(INonfungiblePositionManagerTreasury.decreaseLiquidity, (params));

        console.log("Position %s tokenId: %s", cfg.label, vm.toString(cfg.tokenId));
        console.log("  current liquidity: %s", vm.toString(currentLiquidity));
        console.log("  liquidity to remove: %s", vm.toString(liquidityToRemove));
    }

    function _appendCollect(
        address[] memory to,
        bytes[] memory data,
        string[] memory labels,
        uint256 idx,
        PositionConfig memory cfg
    ) internal pure {
        CollectParams memory params = CollectParams({
            tokenId: cfg.tokenId, recipient: TREASURY, amount0Max: type(uint128).max, amount1Max: type(uint128).max
        });

        labels[idx] = string.concat("Uniswap collect ", cfg.label);
        to[idx] = NONFUNGIBLE_POSITION_MANAGER;
        data[idx] = abi.encodeCall(INonfungiblePositionManagerTreasury.collect, (params));
    }

    function _positionTokensAndLiquidity(uint256 tokenId)
        internal
        view
        returns (address token0, address token1, uint128 liquidity)
    {
        (,, token0, token1,,,, liquidity,,,,) =
            INonfungiblePositionManagerTreasury(NONFUNGIBLE_POSITION_MANAGER).positions(tokenId);
    }

    function _logTransactions(string[] memory labels, address[] memory to, bytes[] memory data) internal view {
        console.log("=== Treasury Curve Rebalance - %s transactions ===", vm.toString(to.length));
        for (uint256 i; i < to.length; ++i) {
            console.log("TX %s: %s", vm.toString(i + 1), labels[i]);
            console.log("     to   : %s", to[i]);
            console.log("     value: 0");
            console.log("     data : %s", vm.toString(data[i]));
        }
    }

    function _writeSafeBatch(address[] memory to, bytes[] memory data) internal {
        string memory txList;
        for (uint256 i; i < to.length; ++i) {
            string memory entry =
                string.concat('{"to":"', vm.toString(to[i]), '","value":"0","data":"', vm.toString(data[i]), '"}');
            txList = i == 0 ? entry : string.concat(txList, ",", entry);
        }

        string memory json = string.concat(
            '{"version":"1.0","chainId":"1",',
            '"meta":{"name":"Treasury Curve Rebalance"},',
            '"transactions":[',
            txList,
            "]}"
        );

        vm.writeFile(OUTPUT_FILE, json);
        console.log("\nSafe TX JSON written to: %s", OUTPUT_FILE);
    }
}
