// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

import {DusdPegCurveOracleCommon} from "./DusdPegCurveOracleCommon.t.sol";
import {DusdPegCurveOracle} from "@alto/oracles/DusdPegCurveOracle/DusdPegCurveOracle.sol";
import {
    DusdPegCurveOracleRuntimeConfig,
    DusdPegCurveOracleValidationConfig,
    IDusdPegCurveOracleErrors
} from "@alto/oracles/interfaces/IDusdPegCurveOracle.sol";
import {
    ICurveStableSwapNGFactory as ICurveStableSwapFactory
} from "@alto/interfaces/curve/ICurveStableSwapNGFactory.sol";
import {
    ICurveStableSwapNGBase,
    ICurveStableSwapNGOracle as ICurveStableSwap
} from "@alto/interfaces/curve/ICurveStableSwapNG.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DusdPegCurveOracleConstructorTest is DusdPegCurveOracleCommon {
    function test_RevertWhen_InitialOwnerIsZero() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.N_COINS.selector));
        _mockFactoryReadRevert(abi.encodeWithSelector(ICurveStableSwapFactory.get_n_coins.selector, address(pool)));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        _deployOracle(runtimeConfig, address(0));
    }

    function test_RevertWhen_PoolIsZeroAddress() external {
        vm.expectRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleZeroAddress.selector);
        _deployOracle(address(0), runtimeConfig, oracleValidationConfig, OWNER);
    }

    function test_RevertWhen_PoolImplementationIsZeroAddress() external {
        DusdPegCurveOracleValidationConfig memory invalidValidationConfig = oracleValidationConfig;
        invalidValidationConfig.expectedCurvePoolImplementation = address(0);

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOracleZeroAddress.selector,
            runtimeConfig,
            invalidValidationConfig,
            OWNER
        );
    }

    function test_RevertWhen_FactoryIsZeroAddress() external {
        DusdPegCurveOracleValidationConfig memory invalidValidationConfig = oracleValidationConfig;
        invalidValidationConfig.curveFactory = address(0);

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOracleZeroAddress.selector,
            runtimeConfig,
            invalidValidationConfig,
            OWNER
        );
    }

    function test_RevertWhen_DusdIsZeroAddress() external {
        DusdPegCurveOracleValidationConfig memory invalidValidationConfig = oracleValidationConfig;
        invalidValidationConfig.dusd = address(0);

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOracleZeroAddress.selector,
            runtimeConfig,
            invalidValidationConfig,
            OWNER
        );
    }

    function test_RevertWhen_QuoteTokenIsZeroAddress() external {
        DusdPegCurveOracleValidationConfig memory invalidValidationConfig = oracleValidationConfig;
        invalidValidationConfig.quoteToken = address(0);

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOracleZeroAddress.selector,
            runtimeConfig,
            invalidValidationConfig,
            OWNER
        );
    }

    function test_RevertWhen_MaExpTimeIsZero() external {
        DusdPegCurveOracleRuntimeConfig memory invalidConfig = runtimeConfig;
        invalidConfig.expectedMaExpTime = 0;

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidConfig.selector, invalidConfig, OWNER);
    }

    function test_RevertWhen_APreciseIsZero() external {
        DusdPegCurveOracleRuntimeConfig memory invalidConfig = runtimeConfig;
        invalidConfig.expectedAPrecise = 0;

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidConfig.selector, invalidConfig, OWNER);
    }

    function test_RevertWhen_PoolNCoinsReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.N_COINS.selector));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolNCoinsIsLessThanTwo() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwapNGBase.N_COINS.selector), abi.encode(uint256(1)));

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinCount.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_PoolNCoinsIsGreaterThanTwo() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwapNGBase.N_COINS.selector), abi.encode(uint256(3)));

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinCount.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_PoolCoinZeroReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(0)));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolCoinZeroIsNotQuoteToken_WithoutReadingCoinOne() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(0)), abi.encode(DUSD));
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(1)));

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinOrder.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_PoolCoinOneReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(1)));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolCoinOneIsNotDusd() external {
        _mockPoolReturn(
            abi.encodeWithSelector(ICurveStableSwapNGBase.coins.selector, uint256(1)), abi.encode(QUOTE_TOKEN)
        );

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinOrder.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_PoolMaExpTimeReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.ma_exp_time.selector));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolMaExpTimeDoesNotMatchConfig() external {
        _mockPoolReturn(
            abi.encodeWithSelector(ICurveStableSwap.ma_exp_time.selector), abi.encode(uint256(MA_EXP_TIME + 1))
        );

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidMaExpTime.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_PoolAPreciseReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.A_precise.selector));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolAPreciseDoesNotMatchConfig_WithoutReadingFutureA() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwap.A_precise.selector), abi.encode(uint256(A_PRECISE + 1)));
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.future_A.selector));

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidAmplification.selector, runtimeConfig, OWNER
        );
    }

    function test_RevertWhen_PoolFutureAReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.future_A.selector));

        _expectPoolReadDeployRevert();
    }

    function test_RevertWhen_PoolFutureADoesNotMatchConfig() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwap.future_A.selector), abi.encode(uint256(A_PRECISE + 1)));

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidAmplification.selector, runtimeConfig, OWNER
        );
    }

    function test_RevertWhen_PoolPriceOracleReadReverts() external {
        _mockPoolReadRevert(abi.encodeWithSelector(ICurveStableSwap.price_oracle.selector, uint256(0)));

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOracleOracleUnavailable.selector, runtimeConfig, OWNER
        );
    }

    function test_RevertWhen_PoolPriceOracleReturnDataCannotBeDecoded() external {
        _mockPoolReturn(abi.encodeWithSelector(ICurveStableSwap.price_oracle.selector, uint256(0)), hex"01");

        vm.expectRevert(bytes(""));
        _deployOracle(runtimeConfig, OWNER);
    }

    function test_RevertWhen_FactoryNCoinsReadReverts() external {
        _mockFactoryReadRevert(abi.encodeWithSelector(ICurveStableSwapFactory.get_n_coins.selector, address(pool)));

        _expectFactoryReadDeployRevert();
    }

    function test_RevertWhen_FactoryNCoinsIsLessThanTwo() external {
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_n_coins.selector, address(pool)), abi.encode(uint256(1))
        );

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinCount.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_FactoryNCoinsIsGreaterThanTwo() external {
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_n_coins.selector, address(pool)), abi.encode(uint256(3))
        );

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinCount.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_FactoryIsMetaReadReverts() external {
        _mockFactoryReadRevert(abi.encodeWithSelector(ICurveStableSwapFactory.is_meta.selector, address(pool)));

        _expectFactoryReadDeployRevert();
    }

    function test_RevertWhen_FactoryReportsMetapool() external {
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.is_meta.selector, address(pool)), abi.encode(true)
        );

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOracleUnsupportedMetapool.selector, runtimeConfig, OWNER
        );
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

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinCount.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_FactoryCoinsHasMoreThanTwoElements() external {
        address[] memory coins = _addressArray(QUOTE_TOKEN, DUSD, address(0xBEEF));
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)), abi.encode(coins)
        );

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinCount.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_FactoryCoinZeroIsNotQuoteToken() external {
        address[] memory coins = _addressArray(address(0xBEEF), DUSD);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)), abi.encode(coins)
        );

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinOrder.selector, runtimeConfig, OWNER);
    }

    function test_RevertWhen_FactoryCoinOneIsNotDusd() external {
        address[] memory coins = _addressArray(QUOTE_TOKEN, address(0xBEEF));
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_coins.selector, address(pool)), abi.encode(coins)
        );

        _expectDeployRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidCoinOrder.selector, runtimeConfig, OWNER);
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
            IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidAssetTypeCount.selector, runtimeConfig, OWNER
        );
    }

    function test_RevertWhen_FactoryAssetTypesHasMoreThanTwoElements() external {
        uint8[] memory assetTypes = _uint8Array(0, 0, 0);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_pool_asset_types.selector, address(pool)),
            abi.encode(assetTypes)
        );

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOracleInvalidAssetTypeCount.selector, runtimeConfig, OWNER
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
                IDusdPegCurveOracleErrors.DusdPegCurveOracleUnsupportedAssetType.selector, uint256(0), uint8(1)
            )
        );
        _deployOracle(runtimeConfig, OWNER);
    }

    function test_RevertWhen_FactoryAssetTypeOneIsNotStandard() external {
        uint8[] memory assetTypes = _uint8Array(0, 2);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_pool_asset_types.selector, address(pool)),
            abi.encode(assetTypes)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IDusdPegCurveOracleErrors.DusdPegCurveOracleUnsupportedAssetType.selector, uint256(1), uint8(2)
            )
        );
        _deployOracle(runtimeConfig, OWNER);
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

        _expectDeployRevert(
            IDusdPegCurveOracleErrors.DusdPegCurveOraclePoolNotRegistered.selector, runtimeConfig, OWNER
        );
    }

    function test_RevertWhen_FactoryImplementationDiffersFromConfig() external {
        address actualImplementation = address(0xBEEF);
        _mockFactoryReturn(
            abi.encodeWithSelector(ICurveStableSwapFactory.get_implementation_address.selector, address(pool)),
            abi.encode(actualImplementation)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IDusdPegCurveOracleErrors.DusdPegCurveOracleUnexpectedImplementation.selector,
                actualImplementation,
                POOL_IMPLEMENTATION
            )
        );
        _deployOracle(runtimeConfig, OWNER);
    }

    function test_WhenPriceOracleReturnsZeroDuringValidation() external {
        _mockPoolReturn(
            abi.encodeWithSelector(ICurveStableSwap.price_oracle.selector, uint256(0)), abi.encode(uint256(0))
        );

        DusdPegCurveOracle deployedOracle = _deployOracle(runtimeConfig, OWNER);
        assertEq(address(deployedOracle.curvePool()), address(pool));
    }

    function test_RevertWhen_DusdEqualsQuoteToken() external {
        DusdPegCurveOracleValidationConfig memory duplicateValidationConfig = oracleValidationConfig;
        duplicateValidationConfig.dusd = QUOTE_TOKEN;

        vm.expectRevert(IDusdPegCurveOracleErrors.DusdPegCurveOracleIdenticalCoins.selector);
        _deployOracle(runtimeConfig, duplicateValidationConfig, OWNER);
    }

    function test_WhenValidConfigurationIsProvided() external {
        vm.recordLogs();
        DusdPegCurveOracle deployedOracle = _deployOracle(runtimeConfig, OWNER);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(address(deployedOracle.curvePool()), address(pool));
        _assertRuntimeConfig(deployedOracle, MA_EXP_TIME, A_PRECISE);
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

    function test_WhenConfigurationIsValid_ValidatesPoolAndFactory() external {
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

        DusdPegCurveOracle deployedOracle = _deployOracle(runtimeConfig, OWNER);
        assertEq(deployedOracle.curvePool(), address(pool));
    }

    function _expectDeployRevert(bytes4 selector, DusdPegCurveOracleRuntimeConfig memory config, address initialOwner)
        private
    {
        vm.expectRevert(selector);
        _deployOracle(config, initialOwner);
    }

    function _expectDeployRevert(
        bytes4 selector,
        DusdPegCurveOracleRuntimeConfig memory config,
        DusdPegCurveOracleValidationConfig memory validationConfig,
        address initialOwner
    ) private {
        vm.expectRevert(selector);
        _deployOracle(config, validationConfig, initialOwner);
    }

    function _expectPoolReadDeployRevert() private {
        _expectPoolReadRevert();
        _deployOracle(runtimeConfig, OWNER);
    }

    function _expectFactoryReadDeployRevert() private {
        _expectFactoryReadRevert();
        _deployOracle(runtimeConfig, OWNER);
    }
}
