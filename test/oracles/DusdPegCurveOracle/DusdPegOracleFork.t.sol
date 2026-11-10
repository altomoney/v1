// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

import {Fork} from "@alto-test/helpers/Fork.sol";

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {PegResponsiveExponentialIrmConfig} from "@alto/lending/interfaces/IPegResponsiveExponentialIrm.sol";
import {ICurveStableSwapNGOracle} from "@alto/interfaces/curve/ICurveStableSwapNG.sol";
import {ICurveStableSwapNGFactory} from "@alto/interfaces/curve/ICurveStableSwapNGFactory.sol";
import {DusdPegCurveOracle} from "@alto/oracles/DusdPegCurveOracle/DusdPegCurveOracle.sol";
import {
    DusdPegCurveOracleRawPoolState,
    DusdPegCurveOracleRuntimeConfig,
    DusdPegCurveOracleValidationConfig
} from "@alto/oracles/interfaces/IDusdPegCurveOracle.sol";

interface ICurveStableSwapNGForkSnapshot {
    function initial_A() external view returns (uint256);
    function initial_A_time() external view returns (uint256);
    function future_A_time() external view returns (uint256);
}

interface ICurveStableSwapNGFactoryForkSnapshot {
    function admin() external view returns (address);
    function fee_receiver() external view returns (address);
}

contract DusdPegOracleForkTest is Test {
    struct PoolSnapshot {
        uint256 priceUpdatedAt;
        uint256 invariantUpdatedAt;
        uint256 currentStatePriceWad;
        uint256 lastStatePriceWad;
        uint256 storedEmaPriceWad;
        uint256 currentEmaPriceWad;
        uint256 quoteTokenBalance;
        uint256 dusdBalance;
    }

    string internal constant MAINNET_ADDRESSES_PATH =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

    uint256 internal constant FORK_BLOCK = 25_746_611;

    address internal constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address internal constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address internal constant CURVE_POOL = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    address internal constant CURVE_FACTORY = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;
    address internal constant CURVE_POOL_IMPLEMENTATION = 0xDCc91f930b42619377C200BA05b7513f2958b202;
    address internal constant CURVE_FACTORY_ADMIN = 0x40907540d8a6C65c637785e8f8B742ae6b0b9968;
    address internal constant CURVE_FEE_RECEIVER = 0xa2Bcd1a4Efbd04B63cd03f5aFf2561106ebCCE00;

    bytes32 internal constant POOL_CODEHASH = 0x78f9db8ec3bc4812db8f7d9d1bee8568ecfacfd9f29c5950c26ea3d112a9ab46;
    bytes32 internal constant FACTORY_CODEHASH = 0xb78c1b32cd364260f3fa497ccc7e98c73cdc26bdae2d3635e763ee8b59a1d6fd;
    bytes32 internal constant IMPLEMENTATION_CODEHASH =
        0xe2a3dd8d583b86eb7f562b4307aab6e5a373ddb5c6b348e4cf63d41914f35a9f;

    uint256 internal constant EXPECTED_MA_EXP_TIME = 866;
    uint256 internal constant EXPECTED_A_PRECISE = 100_000;

    uint256 private constant YEAR = 365 days;
    uint256 private constant RECOVERY_PRICE = 1.001e18;
    uint256 private constant STRESS_PRICE = 1e18;
    uint256 private constant BASE_RATE = 0.05e18 / YEAR;
    uint256 private constant STRESS_RATE = 0.075e18 / YEAR;
    uint256 private constant MAX_RATE = 8e18 / YEAR;

    ICurveStableSwapNGOracle internal pool = ICurveStableSwapNGOracle(CURVE_POOL);
    ICurveStableSwapNGFactory internal factory = ICurveStableSwapNGFactory(CURVE_FACTORY);
    IMarket internal wethMintMarket;
    DusdPegCurveOracle internal oracle;
    PoolSnapshot internal poolSnapshot;

    function setUp() public {
        Fork.selectEthereum(FORK_BLOCK);
        poolSnapshot = _readPoolSnapshot();

        string memory addressesJson = vm.readFile(MAINNET_ADDRESSES_PATH);
        wethMintMarket = IMarket(vm.parseJsonAddress(addressesJson, ".contracts.wethMarket"));

        oracle = new DusdPegCurveOracle(
            CURVE_POOL,
            _runtimeConfig(),
            DusdPegCurveOracleValidationConfig({
                curveFactory: CURVE_FACTORY,
                expectedCurvePoolImplementation: CURVE_POOL_IMPLEMENTATION,
                dusd: DUSD,
                quoteToken: FRXUSD
            }),
            address(this)
        );
    }

    function test_ForkPinsReviewedBlockAndContractIdentities() external view {
        assertEq(block.number, FORK_BLOCK, "fork block");
        assertEq(CURVE_POOL.codehash, POOL_CODEHASH, "pool codehash");
        assertEq(CURVE_FACTORY.codehash, FACTORY_CODEHASH, "factory codehash");
        assertEq(CURVE_POOL_IMPLEMENTATION.codehash, IMPLEMENTATION_CODEHASH, "implementation codehash");
    }

    function test_PoolAndFactoryReportReviewedProvenance() external view {
        assertEq(pool.N_COINS(), 2, "pool N_COINS");
        assertEq(pool.coins(0), FRXUSD, "pool coin 0");
        assertEq(pool.coins(1), DUSD, "pool coin 1");
        assertEq(IERC20Metadata(FRXUSD).decimals(), 18, "frxUSD decimals");
        assertEq(IERC20Metadata(DUSD).decimals(), 18, "DUSD decimals");

        assertEq(factory.get_n_coins(CURVE_POOL), 2, "factory coin count");
        address[] memory registeredCoins = factory.get_coins(CURVE_POOL);
        assertEq(registeredCoins.length, 2, "registered coin length");
        assertEq(registeredCoins[0], FRXUSD, "factory coin 0");
        assertEq(registeredCoins[1], DUSD, "factory coin 1");

        uint8[] memory assetTypes = factory.get_pool_asset_types(CURVE_POOL);
        assertEq(assetTypes.length, 2, "asset type length");
        assertEq(assetTypes[0], 0, "asset type 0");
        assertEq(assetTypes[1], 0, "asset type 1");
        assertFalse(factory.is_meta(CURVE_POOL), "is meta");
        assertEq(factory.get_implementation_address(CURVE_POOL), CURVE_POOL_IMPLEMENTATION, "implementation");

        ICurveStableSwapNGFactoryForkSnapshot snapshot = ICurveStableSwapNGFactoryForkSnapshot(CURVE_FACTORY);
        assertEq(snapshot.admin(), CURVE_FACTORY_ADMIN, "factory admin");
        assertEq(snapshot.fee_receiver(), CURVE_FEE_RECEIVER, "fee receiver");
    }

    function test_PoolConfigurationMatchesApprovedParameters() external view {
        ICurveStableSwapNGForkSnapshot snapshot = ICurveStableSwapNGForkSnapshot(CURVE_POOL);
        assertEq(pool.ma_exp_time(), EXPECTED_MA_EXP_TIME, "ma_exp_time");
        assertEq(pool.A_precise(), EXPECTED_A_PRECISE, "A_precise");
        assertEq(pool.future_A(), EXPECTED_A_PRECISE, "future_A");
        assertEq(snapshot.initial_A(), EXPECTED_A_PRECISE, "initial_A");
        assertEq(snapshot.initial_A_time(), 0, "initial_A_time");
        assertEq(snapshot.future_A_time(), 0, "future_A_time");
    }

    function test_OracleDeploysAgainstReviewedProductionState() external view {
        assertEq(oracle.curvePool(), CURVE_POOL, "curve pool");
        assertEq(oracle.owner(), address(this), "owner");
        (uint256 maExpTime, uint256 aPrecise) = oracle.runtimeConfig();
        assertEq(maExpTime, EXPECTED_MA_EXP_TIME, "expected ma_exp_time");
        assertEq(aPrecise, EXPECTED_A_PRECISE, "expected A_precise");
    }

    function test_GetPriceMatchesPinnedPool() external view {
        (uint256 priceWad, uint48 observedAt, bool valid) = oracle.getPrice();
        assertEq(priceWad, poolSnapshot.currentEmaPriceWad, "priceWad");
        assertEq(observedAt, poolSnapshot.priceUpdatedAt, "observedAt");
        assertTrue(valid, "valid");
    }

    function test_RawPoolStateMatchesPinnedPool() external view {
        DusdPegCurveOracleRawPoolState memory state = oracle.rawPoolState();
        assertEq(state.currentStatePriceWad, poolSnapshot.currentStatePriceWad, "currentStatePriceWad");
        assertEq(state.lastStatePriceWad, poolSnapshot.lastStatePriceWad, "lastStatePriceWad");
        assertEq(state.storedEmaPriceWad, poolSnapshot.storedEmaPriceWad, "storedEmaPriceWad");
        assertEq(state.currentEmaPriceWad, poolSnapshot.currentEmaPriceWad, "currentEmaPriceWad");
        assertEq(state.priceUpdatedAt, poolSnapshot.priceUpdatedAt, "priceUpdatedAt");
        assertEq(state.invariantUpdatedAt, poolSnapshot.invariantUpdatedAt, "invariantUpdatedAt");
        assertEq(state.maExpTime, EXPECTED_MA_EXP_TIME, "maExpTime");
        assertEq(state.aPrecise, EXPECTED_A_PRECISE, "aPrecise");
        assertEq(state.futureAPrecise, EXPECTED_A_PRECISE, "futureAPrecise");
        assertEq(state.quoteTokenBalance, poolSnapshot.quoteTokenBalance, "quoteTokenBalance");
        assertEq(state.dusdBalance, poolSnapshot.dusdBalance, "dusdBalance");
    }

    function test_PrmConsumesRealOracleWhenFreshnessWindowIncludesPinnedAge() external {
        PegResponsiveExponentialIrm prm = _deployPrm(_observationAge());
        vm.prank(Ownable(address(wethMintMarket)).owner());
        wethMintMarket.setIrm(address(prm), true);

        assertEq(wethMintMarket.irm(), address(prm), "market IRM");
        assertEq(prm.market(), address(wethMintMarket), "IRM market");
        uint256 expectedRate = prm.targetBorrowRate(poolSnapshot.currentEmaPriceWad);

        (uint256 priceWad, uint48 observedAt, bool oracleValid, uint256 previewRate) = prm.previewBorrowRate();
        assertEq(priceWad, poolSnapshot.currentEmaPriceWad, "priceWad");
        assertEq(observedAt, poolSnapshot.priceUpdatedAt, "observedAt");
        assertTrue(oracleValid, "oracleValid");
        assertEq(previewRate, expectedRate, "previewRate");

        wethMintMarket.accrueInterest();
        (uint256 borrowRate,,,) = prm.irState();
        assertEq(borrowRate, expectedRate, "stored rate");
    }

    function test_PrmRejectsRealOracleWhenPinnedObservationIsTooOld() external {
        PegResponsiveExponentialIrm prm = _deployPrm(_observationAge() - 1);

        (uint256 priceWad, uint48 observedAt, bool oracleValid, uint256 previewRate) = prm.previewBorrowRate();
        assertEq(priceWad, 0, "priceWad");
        assertEq(observedAt, poolSnapshot.priceUpdatedAt, "observedAt");
        assertFalse(oracleValid, "oracleValid");
        assertEq(previewRate, BASE_RATE, "held rate");
    }

    function _readPoolSnapshot() private view returns (PoolSnapshot memory snapshot) {
        uint256 packedTimestamps = pool.ma_last_time();
        uint256[] memory balances = pool.get_balances();
        assertEq(balances.length, 2, "snapshot balance length");

        snapshot = PoolSnapshot({
            priceUpdatedAt: packedTimestamps & type(uint128).max,
            invariantUpdatedAt: packedTimestamps >> 128,
            currentStatePriceWad: pool.get_p(0),
            lastStatePriceWad: pool.last_price(0),
            storedEmaPriceWad: pool.ema_price(0),
            currentEmaPriceWad: pool.price_oracle(0),
            quoteTokenBalance: balances[0],
            dusdBalance: balances[1]
        });
    }

    function _runtimeConfig() private pure returns (DusdPegCurveOracleRuntimeConfig memory config) {
        config = DusdPegCurveOracleRuntimeConfig({
            expectedMaExpTime: EXPECTED_MA_EXP_TIME, expectedAPrecise: EXPECTED_A_PRECISE
        });
    }

    function _observationAge() private view returns (uint48) {
        return uint48(block.timestamp - poolSnapshot.priceUpdatedAt);
    }

    function _deployPrm(uint48 maxOracleAge) private returns (PegResponsiveExponentialIrm prm) {
        PegResponsiveExponentialIrmConfig memory config = PegResponsiveExponentialIrmConfig({
            recoveryPrice: RECOVERY_PRICE,
            stressPrice: STRESS_PRICE,
            baseRate: BASE_RATE,
            stressRate: STRESS_RATE,
            maxRate: MAX_RATE,
            doublingDistance: 0.0025e18,
            recoveryDelay: 6 hours,
            maxOracleAge: maxOracleAge
        });
        prm = new PegResponsiveExponentialIrm(address(oracle), config, address(this));
    }
}
