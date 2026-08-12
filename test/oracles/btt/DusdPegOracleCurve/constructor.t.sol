// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

import {DusdPegOracleCurveCommon} from "./DusdPegOracleCurveCommon.t.sol";
import {DusdPegOracleCurve} from "@alto/oracles/dusd/DusdPegOracleCurve.sol";
import {
    DusdPegOracleCurveConfig,
    IDusdPegOracleCurveErrors
} from "@alto/oracles/dusd/interfaces/IDusdPegOracleCurve.sol";
import {
    ICurveStableSwapNGFactory as ICurveStableSwapFactory
} from "@alto/interfaces/curve/ICurveStableSwapNGFactory.sol";
import {
    ICurveStableSwapNGBase,
    ICurveStableSwapNGOracle as ICurveStableSwap
} from "@alto/interfaces/curve/ICurveStableSwapNG.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DusdPegOracleCurveConstructorTest is DusdPegOracleCurveCommon {
    function test_RevertWhen_InitialOwnerIsZero() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.N_COINS.selector));
        _mockFactoryReadRevert(abi.encodeWithSelector(ICurveStableSwapFactory.get_n_coins.selector, address(pool)));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        _deployOracle(cfg, true, address(0));
    }

    function test_RevertWhen_PoolIsZeroAddress() external {
        DusdPegOracleCurveConfig memory invalidCfg = cfg;
        invalidCfg.pool = address(0);

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveZeroAddress.selector, invalidCfg, true, OWNER);
    }

    function test_RevertWhen_PoolImplementationIsZeroAddress() external {
        DusdPegOracleCurveConfig memory invalidCfg = cfg;
        invalidCfg.poolImpl = address(0);

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveZeroAddress.selector, invalidCfg, true, OWNER);
    }

    function test_RevertWhen_FactoryIsZeroAddress() external {
        DusdPegOracleCurveConfig memory invalidCfg = cfg;
        invalidCfg.factory = address(0);

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveZeroAddress.selector, invalidCfg, true, OWNER);
    }

    function test_RevertWhen_DusdIsZeroAddress() external {
        DusdPegOracleCurveConfig memory invalidCfg = cfg;
        invalidCfg.dusd = address(0);

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveZeroAddress.selector, invalidCfg, true, OWNER);
    }

    function test_RevertWhen_QuoteTokenIsZeroAddress() external {
        DusdPegOracleCurveConfig memory invalidCfg = cfg;
        invalidCfg.quoteToken = address(0);

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveZeroAddress.selector, invalidCfg, true, OWNER);
    }

    function test_RevertWhen_MaExpTimeIsZero() external {
        DusdPegOracleCurveConfig memory invalidCfg = cfg;
        invalidCfg.maExpTime = 0;

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidConfig.selector, invalidCfg, true, OWNER);
    }

    function test_RevertWhen_APreciseIsZero() external {
        DusdPegOracleCurveConfig memory invalidCfg = cfg;
        invalidCfg.aPrecise = 0;

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidConfig.selector, invalidCfg, true, OWNER);
    }

    function test_RevertWhen_PoolNCoinsReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.N_COINS.selector));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolNCoinsIsLessThanTwo() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwapNGBase.N_COINS.selector), abi.encode(uint256(1)));

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinCount.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_PoolNCoinsIsGreaterThanTwo() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwapNGBase.N_COINS.selector), abi.encode(uint256(3)));

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinCount.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_PoolCoinZeroReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(0)));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolCoinZeroIsNotQuoteToken_WithoutReadingCoinOne() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(0)), abi.encode(DUSD));
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(1)));

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinOrder.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_PoolCoinOneReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(1)));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolCoinOneIsNotDusd() external {
        _mockPoolReturn(
            abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(1)), abi.encode(QUOTE_TOKEN)
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinOrder.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_PoolMaExpTimeReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.ma_exp_time.selector));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolMaExpTimeDoesNotMatchConfig() external {
        _mockPoolReturn(
            abi.encodeWithSelector(ICurveStableSwap.ma_exp_time.selector), abi.encode(uint256(MA_EXP_TIME + 1))
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidMaExpTime.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_PoolAPreciseReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.A_precise.selector));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolAPreciseDoesNotMatchConfig_WithoutReadingFutureA() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwap.A_precise.selector), abi.encode(uint256(A_PRECISE + 1)));
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.future_A.selector));

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidAmplification.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_PoolFutureAReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.future_A.selector));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolFutureADoesNotMatchConfig() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwap.future_A.selector), abi.encode(uint256(A_PRECISE + 1)));

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidAmplification.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_PoolPriceOracleReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.price_oracle.selector, uint256(0)));

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveOracleUnavailable.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_PoolPriceOracleReturnDataCannotBeDecoded() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwap.price_oracle.selector, uint256(0)), hex"01");

        vm.expectRevert(bytes(""));
        _deployOracle(cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryNCoinsReadReverts() external {
        _mockFactoryReadRevert(abi.encodeWithSelector(ICurveStableSwapFactory.get_n_coins.selector, address(pool)));

        _expectFactoryReadDeployRevert();
    }

    function test_RevertWhen_FactoryNCoinsIsLessThanTwo() external {
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_n_coins.selector, address(pool)), abi.encode(uint256(1))
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinCount.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryNCoinsIsGreaterThanTwo() external {
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_n_coins.selector, address(pool)), abi.encode(uint256(3))
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinCount.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryIsMetaReadReverts() external {
        _mockFactoryReadRevert(abi.encodeWithSelector(ICurveStableSwapFactory.is_meta.selector, address(pool)));

        _expectFactoryReadDeployRevert();
    }

    function test_RevertWhen_FactoryReportsMetapool() external {
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.is_meta.selector, address(pool)), abi.encode(true)
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveUnsupportedMetapool.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryCoinsReadReverts() external {
        _mockFactoryReadRevert(abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)));

        _expectFactoryReadDeployRevert();
    }

    function test_RevertWhen_FactoryCoinsHasFewerThanTwoElements() external {
        address[] memory coins = _addressArray(QUOTE_TOKEN);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)), abi.encode(coins)
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinCount.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryCoinsHasMoreThanTwoElements() external {
        address[] memory coins = _addressArray(QUOTE_TOKEN, DUSD, address(0xBEEF));
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)), abi.encode(coins)
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinCount.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryCoinZeroIsNotQuoteToken() external {
        address[] memory coins = _addressArray(address(0xBEEF), DUSD);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)), abi.encode(coins)
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinOrder.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryCoinOneIsNotDusd() external {
        address[] memory coins = _addressArray(QUOTE_TOKEN, address(0xBEEF));
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)), abi.encode(coins)
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidCoinOrder.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryAssetTypesReadReverts() external {
        _mockFactoryReadRevert(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_pool_asset_types.selector, address(pool))
        );

        _expectFactoryReadDeployRevert();
    }

    function test_RevertWhen_FactoryAssetTypesHasFewerThanTwoElements() external {
        uint8[] memory assetTypes = _uint8Array(0);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_pool_asset_types.selector, address(pool)),
            abi.encode(assetTypes)
        );

        _expectDeployRevert(
            IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidAssetTypeCount.selector, cfg, true, OWNER
        );
    }

    function test_RevertWhen_FactoryAssetTypesHasMoreThanTwoElements() external {
        uint8[] memory assetTypes = _uint8Array(0, 0, 0);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_pool_asset_types.selector, address(pool)),
            abi.encode(assetTypes)
        );

        _expectDeployRevert(
            IDusdPegOracleCurveErrors.DusdPegOracleCurveInvalidAssetTypeCount.selector, cfg, true, OWNER
        );
    }

    function test_RevertWhen_FactoryAssetTypeZeroIsNotStandard_WithoutValidatingAssetTypeOne() external {
        uint8[] memory assetTypes = _uint8Array(1, type(uint8).max);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_pool_asset_types.selector, address(pool)),
            abi.encode(assetTypes)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IDusdPegOracleCurveErrors.DusdPegOracleCurveUnsupportedAssetType.selector, uint256(0), uint8(1)
            )
        );
        _deployOracle(cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryAssetTypeOneIsNotStandard() external {
        uint8[] memory assetTypes = _uint8Array(0, 2);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_pool_asset_types.selector, address(pool)),
            abi.encode(assetTypes)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IDusdPegOracleCurveErrors.DusdPegOracleCurveUnsupportedAssetType.selector, uint256(1), uint8(2)
            )
        );
        _deployOracle(cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryImplementationReadReverts() external {
        _mockFactoryReadRevert(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_implementation_address.selector, address(pool))
        );

        _expectFactoryReadDeployRevert();
    }

    function test_RevertWhen_FactoryImplementationIsZeroAddress() external {
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_implementation_address.selector, address(pool)),
            abi.encode(address(0))
        );

        _expectDeployRevert(IDusdPegOracleCurveErrors.DusdPegOracleCurvePoolNotRegistered.selector, cfg, true, OWNER);
    }

    function test_RevertWhen_FactoryImplementationDiffersFromConfig() external {
        address actualImplementation = address(0xBEEF);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_implementation_address.selector, address(pool)),
            abi.encode(actualImplementation)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IDusdPegOracleCurveErrors.DusdPegOracleCurveUnexpectedImplementation.selector,
                actualImplementation,
                POOL_IMPLEMENTATION
            )
        );
        _deployOracle(cfg, true, OWNER);
    }

    function test_WhenRuntimeChecksIsFalse() external {
        DusdPegOracleCurve deployedOracle = _deployOracle(cfg, false, OWNER);

        assertFalse(deployedOracle.runtimeConfigChecksEnabled());
    }

    function test_WhenRuntimeChecksIsTrue() external {
        DusdPegOracleCurve deployedOracle = _deployOracle(cfg, true, OWNER);

        assertTrue(deployedOracle.runtimeConfigChecksEnabled());
    }

    function test_WhenPriceOracleReturnsZeroDuringValidation() external {
        _mockPoolReturn(
            abi.encodeWithSelector(ICurveStableSwap.price_oracle.selector, uint256(0)), abi.encode(uint256(0))
        );

        DusdPegOracleCurve deployedOracle = _deployOracle(cfg, true, OWNER);
        assertEq(address(deployedOracle.pool()), address(pool));
    }

    function test_WhenDusdEqualsQuoteToken() external {
        DusdPegOracleCurveConfig memory duplicateCfg = cfg;
        duplicateCfg.dusd = QUOTE_TOKEN;

        _mockPoolReturn(
            abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(1)), abi.encode(QUOTE_TOKEN)
        );
        address[] memory coins = _addressArray(QUOTE_TOKEN, QUOTE_TOKEN);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)), abi.encode(coins)
        );

        DusdPegOracleCurve deployedOracle = _deployOracle(duplicateCfg, true, OWNER);
        assertEq(deployedOracle.dusd(), deployedOracle.quoteToken());
    }

    function test_WhenValidConfigurationIsProvided() external {
        vm.recordLogs();
        DusdPegOracleCurve deployedOracle = _deployOracle(cfg, true, OWNER);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(address(deployedOracle.pool()), address(pool));
        assertEq(address(deployedOracle.factory()), address(factory));
        assertEq(deployedOracle.poolImplementation(), POOL_IMPLEMENTATION);
        assertEq(deployedOracle.dusd(), DUSD);
        assertEq(deployedOracle.quoteToken(), QUOTE_TOKEN);
        assertEq(deployedOracle.expectedMaExpTime(), MA_EXP_TIME);
        assertEq(deployedOracle.expectedAPrecise(), A_PRECISE);
        assertTrue(deployedOracle.runtimeConfigChecksEnabled());
        assertEq(deployedOracle.owner(), OWNER);
        assertEq(deployedOracle.pendingOwner(), address(0));

        assertEq(deployedOracle.ORACLE_INDEX(), 0);
        assertEq(deployedOracle.EXPECTED_COIN_COUNT(), 2);
        assertEq(deployedOracle.STANDARD_ASSET_TYPE(), 0);
        assertEq(deployedOracle.PRICE_TIMESTAMP_MASK(), type(uint128).max);

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployedOracle));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("OwnershipTransferred(address,address)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(OWNER))));
    }

    function test_WhenRuntimeChecksIsFalse_StillValidatesPoolAndFactory() external {
        vm.expectCall(address(pool), abi.encodeWithSelector(ICurveStableSwapNGBase.N_COINS.selector), 1);
        vm.expectCall(address(pool), abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(0)), 1);
        vm.expectCall(address(pool), abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(1)), 1);
        vm.expectCall(address(pool), abi.encodeWithSelector(ICurveStableSwap.ma_exp_time.selector), 1);
        vm.expectCall(address(pool), abi.encodeWithSelector(ICurveStableSwap.A_precise.selector), 1);
        vm.expectCall(address(pool), abi.encodeWithSelector(ICurveStableSwap.future_A.selector), 1);
        vm.expectCall(address(pool), abi.encodeWithSelector(ICurveStableSwap.price_oracle.selector, uint256(0)), 1);
        vm.expectCall(
            address(factory), abi.encodeWithSelector(ICurveStableSwapFactory.get_n_coins.selector, address(pool)), 1
        );
        vm.expectCall(
            address(factory), abi.encodeWithSelector(ICurveStableSwapFactory.is_meta.selector, address(pool)), 1
        );
        vm.expectCall(
            address(factory), abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)), 1
        );
        vm.expectCall(
            address(factory),
            abi.encodeWithSelector(ICurveStableSwapFactory.get_pool_asset_types.selector, address(pool)),
            1
        );
        vm.expectCall(
            address(factory),
            abi.encodeWithSelector(ICurveStableSwapFactory.get_implementation_address.selector, address(pool)),
            1
        );

        DusdPegOracleCurve deployedOracle = _deployOracle(cfg, false, OWNER);
        assertFalse(deployedOracle.runtimeConfigChecksEnabled());
    }

    function _expectDeployRevert(
        bytes4 selector,
        DusdPegOracleCurveConfig memory config,
        bool runtimeChecks,
        address initialOwner
    ) private {
        vm.expectRevert(selector);
        _deployOracle(config, runtimeChecks, initialOwner);
    }

    function _expectPoolReadDeployRevert() private {
        _expectPoolReadRevert();
        _deployOracle(cfg, true, OWNER);
    }

    function _expectFactoryReadDeployRevert() private {
        _expectFactoryReadRevert();
        _deployOracle(cfg, true, OWNER);
    }
}
