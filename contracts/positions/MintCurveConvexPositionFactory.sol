// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {ICurveStablePool} from "./interfaces/ICurveStablePool.sol";
import {IConvexBooster, IConvexRewardPool} from "./interfaces/IConvex.sol";
import {
    IMintCurveConvexPositionFactoryBase,
    IMintCurveConvexPositionFactoryStaticTypes,
    MintCurveConvexConfig
} from "./interfaces/IMintCurveConvexPositionFactory.sol";
import {MintCurveConvexPosition} from "./MintCurveConvexPosition.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title MintCurveConvexPositionFactory
/// @notice UUPS-upgradeable factory that deploys beacon-backed MintCurveConvexPosition  strategy instances.
/// @dev The beacon implementation must be MintCurveConvexPosition contract.
/// @custom:audit Pending
contract MintCurveConvexPositionFactory is
    IMintCurveConvexPositionFactoryStaticTypes,
    Initializable,
    AltoOwnable2StepUpgradeable,
    UUPSUpgradeable
{
    /// @inheritdoc IMintCurveConvexPositionFactoryBase
    uint256 public constant EXPECTED_POSITION_VERSION = 1;

    /// @inheritdoc IMintCurveConvexPositionFactoryBase
    address public beacon;

    /// @inheritdoc IMintCurveConvexPositionFactoryStaticTypes
    MintCurveConvexConfig public config;

    /// @inheritdoc IMintCurveConvexPositionFactoryBase
    address public marketRegistry;

    mapping(address owner => address[] positions) internal _positionsOf;
    mapping(address position => uint256 index) internal _positionIndex;

    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the factory.
    /// @param admin Owner address of this factory.
    /// @param _marketRegistry Address of the market registry used to validate mint markets.
    /// @param _config The shared Curve/Convex configuration applied to all deployed positions.
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(address admin, address _marketRegistry, MintCurveConvexConfig calldata _config)
        external
        virtual
        initializer
    {
        __MintCurveConvexPositionFactory_init(admin, _marketRegistry, _config);
    }

    function __MintCurveConvexPositionFactory_init(
        address admin,
        address _marketRegistry,
        MintCurveConvexConfig calldata _config
    ) internal onlyInitializing {
        if (admin == address(0) || _marketRegistry == address(0)) {
            revert MintCurveConvexPositionFactoryZeroAddress();
        }
        _validateConfig(_config);

        marketRegistry = _marketRegistry;
        emit MarketRegistrySet(_marketRegistry);

        config = _config;
        emit MintCurveConvexConfigSet(_config);

        __Ownable_init(admin);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    /// @inheritdoc IMintCurveConvexPositionFactoryBase
    function setBeacon(address _beacon) external onlyOwner {
        if (_beacon == address(0)) revert MintCurveConvexPositionFactoryZeroAddress();
        if (beacon != address(0)) revert MintCurveConvexPositionFactoryBeaconAlreadySet();

        address implementation = IBeacon(_beacon).implementation();
        if (implementation == address(0)) revert MintCurveConvexPositionFactoryInvalidBeacon();
        if (MintCurveConvexPosition(implementation).version() != EXPECTED_POSITION_VERSION) {
            revert MintCurveConvexPositionFactoryInvalidImplementationVersion();
        }

        beacon = _beacon;
        emit BeaconSet(_beacon);
    }

    /// @inheritdoc IMintCurveConvexPositionFactoryBase
    function setMarketRegistry(address _marketRegistry) external onlyOwner {
        if (_marketRegistry == address(0)) revert MintCurveConvexPositionFactoryZeroAddress();
        marketRegistry = _marketRegistry;
        emit MarketRegistrySet(_marketRegistry);
    }

    /// @inheritdoc IMintCurveConvexPositionFactoryBase
    function positionsOf(address owner) external view returns (address[] memory) {
        return _positionsOf[owner];
    }

    /// @inheritdoc IMintCurveConvexPositionFactoryBase
    function onPositionOwnershipTransferred(address previousOwner) external {
        address[] storage previousOwnerPositions = _positionsOf[previousOwner];
        uint256 positionIndex = _positionIndex[msg.sender];
        if (positionIndex >= previousOwnerPositions.length || previousOwnerPositions[positionIndex] != msg.sender) {
            revert MintCurveConvexPositionFactoryInvalidPosition();
        }

        address newOwner = MintCurveConvexPosition(msg.sender).owner();
        if (newOwner == address(0)) revert MintCurveConvexPositionFactoryZeroAddress();

        uint256 lastPositionIndex = previousOwnerPositions.length - 1;
        if (positionIndex != lastPositionIndex) {
            address lastPosition = previousOwnerPositions[lastPositionIndex];
            previousOwnerPositions[positionIndex] = lastPosition;
            _positionIndex[lastPosition] = positionIndex;
        }
        previousOwnerPositions.pop();

        _positionIndex[msg.sender] = _positionsOf[newOwner].length;
        _positionsOf[newOwner].push(msg.sender);
    }

    /// @inheritdoc IMintCurveConvexPositionFactoryBase
    function createPosition(address market) external returns (address position) {
        if (beacon == address(0)) revert MintCurveConvexPositionFactoryBeaconNotSet();
        if (!IMarketRegistry(marketRegistry).isMintMarket(market)) {
            revert MintCurveConvexPositionFactoryUnsupportedMarket();
        }

        bytes memory initData =
            abi.encodeCall(MintCurveConvexPosition.initialize, (msg.sender, address(this), market, config));
        position = address(new BeaconProxy(beacon, initData));

        _positionIndex[position] = _positionsOf[msg.sender].length;
        _positionsOf[msg.sender].push(position);
        emit PositionCreated(msg.sender, position);
    }

    function _validateConfig(MintCurveConvexConfig memory config) internal view {
        if (
            config.curvePool == address(0) || config.convexBooster == address(0)
                || config.convexRewardPool == address(0) || config.crv == address(0) || config.cvx == address(0)
                || ICurveStablePool(config.curvePool).N_COINS() != 2
                || IConvexRewardPool(config.convexRewardPool).pid() != config.convexPid
        ) {
            revert MintCurveConvexPositionFactoryInvalidConfig();
        }

        // Bind the booster's on-chain registry entry for this pid to the rest of the config.
        (address lptoken,,, address crvRewards,, bool shutdown) =
            IConvexBooster(config.convexBooster).poolInfo(config.convexPid);
        if (lptoken != config.curvePool || crvRewards != config.convexRewardPool || shutdown) {
            revert MintCurveConvexPositionFactoryInvalidConfig();
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
