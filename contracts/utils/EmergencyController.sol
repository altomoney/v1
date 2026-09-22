// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";

interface ISafeOwnerManager {
    function isOwner(address owner) external view returns (bool);
}

/// @title EmergencyController
/// @custom:contact security@altofoundation.org
/// @notice Lets any current Pauser Safe owner take explicitly permitted emergency actions.
/// @dev Deploy behind a UUPS proxy owned by protocol governance.
contract EmergencyController is Initializable, AltoOwnable2StepUpgradeable, UUPSUpgradeable {
    error Unauthorized(address caller);
    error UnregisteredMarket(address market);
    error UnregisteredUsm(address usm);
    error ZeroAddress();

    event PauserSafeSet(address indexed oldPauserSafe, address indexed newPauserSafe);
    event MarketRegistrySet(address indexed oldMarketRegistry, address indexed newMarketRegistry);
    event UsmRegistrySet(address indexed oldUsmRegistry, address indexed newUsmRegistry);
    event DusdSet(address indexed oldDusd, address indexed newDusd);
    event SdusdSet(address indexed oldSdusd, address indexed newSdusd);
    event ProtocolFeeCollectorSet(address indexed oldProtocolFeeCollector, address indexed newProtocolFeeCollector);
    event UniversalRewardsDistributorSet(
        address indexed oldUniversalRewardsDistributor, address indexed newUniversalRewardsDistributor
    );

    ISafeOwnerManager public pauserSafe;
    IMarketRegistry public marketRegistry;
    IUsmRegistry public usmRegistry;
    IPausable public dusd;
    IPausable public universalRewardsDistributor;
    IPausable public sdusd;
    IPausable public protocolFeeCollector;

    uint256[43] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the controller configuration and governance upgrade authority.
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(
        address admin,
        address pauserSafe_,
        address marketRegistry_,
        address usmRegistry_,
        address dusd_,
        address universalRewardsDistributor_
    ) external initializer {
        if (
            admin == address(0) || pauserSafe_ == address(0) || marketRegistry_ == address(0)
                || usmRegistry_ == address(0) || dusd_ == address(0) || universalRewardsDistributor_ == address(0)
        ) revert ZeroAddress();

        pauserSafe = ISafeOwnerManager(pauserSafe_);
        marketRegistry = IMarketRegistry(marketRegistry_);
        usmRegistry = IUsmRegistry(usmRegistry_);
        dusd = IPausable(dusd_);
        universalRewardsDistributor = IPausable(universalRewardsDistributor_);

        __Ownable_init(admin);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    modifier onlyPauserSafeOwner() {
        if (!pauserSafe.isOwner(msg.sender)) revert Unauthorized(msg.sender);
        _;
    }

    /// @notice Updates the Safe whose current owners can use the controller.
    function setPauserSafe(address newPauserSafe) external onlyOwner {
        if (newPauserSafe == address(0)) revert ZeroAddress();
        emit PauserSafeSet(address(pauserSafe), newPauserSafe);
        pauserSafe = ISafeOwnerManager(newPauserSafe);
    }

    /// @notice Updates the registry used to validate markets.
    function setMarketRegistry(address newMarketRegistry) external onlyOwner {
        if (newMarketRegistry == address(0)) revert ZeroAddress();
        emit MarketRegistrySet(address(marketRegistry), newMarketRegistry);
        marketRegistry = IMarketRegistry(newMarketRegistry);
    }

    /// @notice Updates the registry used to validate USMs.
    function setUsmRegistry(address newUsmRegistry) external onlyOwner {
        if (newUsmRegistry == address(0)) revert ZeroAddress();
        emit UsmRegistrySet(address(usmRegistry), newUsmRegistry);
        usmRegistry = IUsmRegistry(newUsmRegistry);
    }

    /// @notice Updates the DUSD pause target.
    function setDusd(address newDusd) external onlyOwner {
        if (newDusd == address(0)) revert ZeroAddress();
        emit DusdSet(address(dusd), newDusd);
        dusd = IPausable(newDusd);
    }

    /// @notice Updates the UniversalRewardsDistributor pause target.
    function setUniversalRewardsDistributor(address newUniversalRewardsDistributor) external onlyOwner {
        if (newUniversalRewardsDistributor == address(0)) revert ZeroAddress();
        emit UniversalRewardsDistributorSet(address(universalRewardsDistributor), newUniversalRewardsDistributor);
        universalRewardsDistributor = IPausable(newUniversalRewardsDistributor);
    }

    /// @notice Updates the sDUSD freeze and pause target after deploying or upgrading the controller.
    function setSdusd(address newSdusd) external onlyOwner {
        if (newSdusd == address(0)) revert ZeroAddress();
        emit SdusdSet(address(sdusd), newSdusd);
        sdusd = IPausable(newSdusd);
    }

    /// @notice Updates the ProtocolFeeCollector pause target after deploying or upgrading the controller.
    function setProtocolFeeCollector(address newProtocolFeeCollector) external onlyOwner {
        if (newProtocolFeeCollector == address(0)) revert ZeroAddress();
        emit ProtocolFeeCollectorSet(address(protocolFeeCollector), newProtocolFeeCollector);
        protocolFeeCollector = IPausable(newProtocolFeeCollector);
    }

    /// @notice Pauses a registered mint or borrow market.
    function pauseMarket(address market) external onlyPauserSafeOwner {
        _requireRegisteredMarket(market);
        _pause(market, PAUSE_TYPE);
    }

    /// @notice Freezes a registered mint or borrow market.
    function freezeMarket(address market) external onlyPauserSafeOwner {
        _requireRegisteredMarket(market);
        _pause(market, FROZEN_TYPE);
    }

    /// @notice Freezes a registered USM.
    function freezeUsm(address usm) external onlyPauserSafeOwner {
        if (!usmRegistry.isUsm(usm)) revert UnregisteredUsm(usm);
        _freezeUsm(usm);
    }

    /// @notice Pauses DUSD minting and burning.
    function pauseDusd() external onlyPauserSafeOwner {
        _pause(address(dusd), PAUSE_TYPE);
    }

    /// @notice Pauses claims from the UniversalRewardsDistributor.
    function pauseUniversalRewardsDistributor() external onlyPauserSafeOwner {
        _pause(address(universalRewardsDistributor), PAUSE_TYPE);
    }

    /// @notice Blocks new sDUSD deposits and mints while leaving exits and reward notifications available.
    function freezeSdusd() external onlyPauserSafeOwner {
        _pause(address(sdusd), FROZEN_TYPE);
    }

    /// @notice Blocks sDUSD deposits, mints, withdrawals, redemptions, and new reward notifications.
    function pauseSdusd() external onlyPauserSafeOwner {
        _pause(address(sdusd), PAUSE_TYPE);
    }

    /// @notice Pauses harvesting, distribution, and collateral operations in the ProtocolFeeCollector.
    function pauseProtocolFeeCollector() external onlyPauserSafeOwner {
        _pause(address(protocolFeeCollector), PAUSE_TYPE);
    }

    function _requireRegisteredMarket(address market) internal view {
        if (!marketRegistry.isMintMarket(market) && !marketRegistry.isBorrowMarket(market)) {
            revert UnregisteredMarket(market);
        }
    }

    function _pause(address target, bytes32 pauseType) internal {
        if (target == address(0)) revert ZeroAddress();
        if (!IPausable(target).paused(pauseType)) IPausable(target).pause(pauseType, true);
    }

    function _freezeUsm(address usm) internal {
        if (!IUsm(usm).getIsFrozen()) IUsm(usm).setSwapFreeze(true);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
