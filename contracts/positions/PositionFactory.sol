// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {PositionType} from "./interfaces/IPosition.sol";
import {ICurveStablePool} from "./interfaces/ICurveStablePool.sol";
import {
    IPositionFactoryBase,
    IPositionFactoryStaticTypes,
    MintCurveConvexConfig
} from "./interfaces/IPositionFactory.sol";
import {MintCurveConvexPosition} from "./MintCurveConvexPosition.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title PositionFactory
/// @notice UUPS-upgradeable factory that deploys beacon-backed strategies(positions) instances.
/// @dev Register each strategy's `PositionBeacon` via `setBeacon`.
contract PositionFactory is IPositionFactoryStaticTypes, Initializable, AltoOwnable2StepUpgradeable, UUPSUpgradeable {
    /// @inheritdoc IPositionFactoryBase
    mapping(PositionType => address) public beacon;

    /// @inheritdoc IPositionFactoryBase
    mapping(address => bool) public approvedSwapTarget;

    /// @inheritdoc IPositionFactoryStaticTypes
    MintCurveConvexConfig public mintCurveConvexConfig;

    /// @inheritdoc IPositionFactoryBase
    address public marketRegistry;

    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the factory .
    /// @param admin Owner authorized to configure beacons, strategy settings, and factory upgrades.
    /// @param _marketRegistry The market registry used to validate mint markets.
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(address admin, address _marketRegistry) external virtual initializer {
        __PositionFactory_init(admin, _marketRegistry);
    }

    function __PositionFactory_init(address admin, address _marketRegistry) internal onlyInitializing {
        if (admin == address(0)) revert PositionFactoryZeroAddress();
        if (_marketRegistry == address(0)) revert PositionFactoryZeroAddress();
        emit MarketRegistrySet(_marketRegistry);
        marketRegistry = _marketRegistry;
        __Ownable_init(admin);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    /// @inheritdoc IPositionFactoryBase
    function setBeacon(PositionType positionType, address _beacon) external onlyOwner {
        if (_beacon == address(0)) revert PositionFactoryZeroAddress();
        if (beacon[positionType] != address(0)) revert PositionFactoryBeaconAlreadySet();
        beacon[positionType] = _beacon;
        emit BeaconSet(positionType, _beacon);
    }

    /// @inheritdoc IPositionFactoryBase
    function setMarketRegistry(address _marketRegistry) external onlyOwner {
        if (_marketRegistry == address(0)) revert PositionFactoryZeroAddress();
        marketRegistry = _marketRegistry;
        emit MarketRegistrySet(_marketRegistry);
    }

    /// @inheritdoc IPositionFactoryBase
    function setMintCurveConvexConfig(MintCurveConvexConfig calldata config) external onlyOwner {
        _validateMintCurveConvexConfig(config);
        mintCurveConvexConfig = config;
        emit MintCurveConvexConfigSet(config);
    }

    /// @inheritdoc IPositionFactoryBase
    function setApprovedSwapTarget(address swapTarget, bool approved) external onlyOwner {
        if (swapTarget == address(0)) revert PositionFactoryZeroAddress();

        if (approvedSwapTarget[swapTarget] == approved) return;

        approvedSwapTarget[swapTarget] = approved;

        emit ApprovedSwapTargetSet(swapTarget, approved);
    }

    /// @inheritdoc IPositionFactoryBase
    function createPosition(PositionType positionType, bytes calldata data) external returns (address position) {
        address beaconAddr = beacon[positionType];
        if (beaconAddr == address(0)) revert PositionFactoryUnsupportedType();

        if (positionType == PositionType.MINT_CURVE_CONVEX) {
            address market = abi.decode(data, (address));
            if (!IMarketRegistry(marketRegistry).isMintMarket(market)) revert PositionFactoryUnsupportedMarket();
            bytes memory initData =
                abi.encodeCall(MintCurveConvexPosition.initialize, (msg.sender, address(this), market));
            position = address(new BeaconProxy(beaconAddr, initData));
        } else {
            revert PositionFactoryUnsupportedType();
        }

        emit PositionCreated(msg.sender, position, positionType);
    }

    function _validateMintCurveConvexConfig(MintCurveConvexConfig memory config) internal view {
        if (
            config.frxUsd == address(0) || config.curvePool == address(0) || config.convexBooster == address(0)
                || config.convexRewardPool == address(0) || config.crv == address(0) || config.cvx == address(0)
                || ICurveStablePool(config.curvePool).N_COINS() != 2
        ) {
            revert PositionFactoryInvalidConfig();
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
