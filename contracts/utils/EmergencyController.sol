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
/// @dev Upgrade existing proxies with initializeV2 calldata to migrate their pause targets atomically.
contract EmergencyController is Initializable, AltoOwnable2StepUpgradeable, UUPSUpgradeable {
    error Unauthorized(address caller);
    error UnsupportedTarget(address target, bytes32 pauseType);
    error UnregisteredUsm(address usm);
    error ZeroAddress();

    event PauserSafeSet(address indexed oldPauserSafe, address indexed newPauserSafe);
    event MarketRegistrySet(address indexed oldMarketRegistry, address indexed newMarketRegistry);
    event UsmRegistrySet(address indexed oldUsmRegistry, address indexed newUsmRegistry);
    event PauseWhitelistSet(address indexed target, bool allowed);
    event FrozenWhitelistSet(address indexed target, bool allowed);

    ISafeOwnerManager public pauserSafe;
    IMarketRegistry public marketRegistry;
    IUsmRegistry public usmRegistry;

    /// @dev Reserved to preserve the storage layout of existing proxies.
    /// @custom:oz-renamed-from dusd
    IPausable private __deprecatedDusd;
    /// @dev Reserved to preserve the storage layout of existing proxies.
    /// @custom:oz-renamed-from universalRewardsDistributor
    IPausable private __deprecatedUniversalRewardsDistributor;

    mapping(address target => bool allowed) public pauseWhitelist;
    mapping(address target => bool allowed) public frozenWhitelist;

    uint256[43] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the controller configuration and governance upgrade authority.
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(address admin, address pauserSafe_, address marketRegistry_, address usmRegistry_)
        external
        initializer
    {
        if (
            admin == address(0) || pauserSafe_ == address(0) || marketRegistry_ == address(0)
                || usmRegistry_ == address(0)
        ) revert ZeroAddress();

        pauserSafe = ISafeOwnerManager(pauserSafe_);
        marketRegistry = IMarketRegistry(marketRegistry_);
        usmRegistry = IUsmRegistry(usmRegistry_);

        __Ownable_init(admin);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    /// @notice Migrates the existing DUSD and rewards distributor pause targets into the whitelist.
    /// @dev Call through upgradeToAndCall when upgrading a legacy proxy.
    function initializeV2() external reinitializer(2) onlyOwner {
        _setPauseWhitelist(address(__deprecatedDusd), true);
        _setPauseWhitelist(address(__deprecatedUniversalRewardsDistributor), true);
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

    /// @notice Adds or removes a target from the pause whitelist.
    function setPauseWhitelist(address target, bool allowed) external onlyOwner {
        _setPauseWhitelist(target, allowed);
    }

    /// @notice Adds or removes a target from the frozen whitelist.
    function setFrozenWhitelist(address target, bool allowed) external onlyOwner {
        _setFrozenWhitelist(target, allowed);
    }

    /// @notice Pauses a whitelisted target or registered mint or borrow market.
    function pause(address target) external onlyPauserSafeOwner {
        if (!pauseWhitelist[target] && !_isRegisteredMarket(target)) revert UnsupportedTarget(target, PAUSE_TYPE);
        _pause(target, PAUSE_TYPE);
    }

    /// @notice Freezes a whitelisted target or registered mint or borrow market.
    function freeze(address target) external onlyPauserSafeOwner {
        if (!frozenWhitelist[target] && !_isRegisteredMarket(target)) revert UnsupportedTarget(target, FROZEN_TYPE);
        _pause(target, FROZEN_TYPE);
    }

    /// @notice Freezes a registered USM.
    function freezeUsm(address usm) external onlyPauserSafeOwner {
        if (!usmRegistry.isUsm(usm)) revert UnregisteredUsm(usm);
        _freezeUsm(usm);
    }

    function _setPauseWhitelist(address target, bool allowed) internal {
        if (target == address(0)) revert ZeroAddress();
        pauseWhitelist[target] = allowed;
        emit PauseWhitelistSet(target, allowed);
    }

    function _setFrozenWhitelist(address target, bool allowed) internal {
        if (target == address(0)) revert ZeroAddress();
        frozenWhitelist[target] = allowed;
        emit FrozenWhitelistSet(target, allowed);
    }

    function _isRegisteredMarket(address target) internal view returns (bool) {
        return marketRegistry.isMintMarket(target) || marketRegistry.isBorrowMarket(target);
    }

    function _pause(address target, bytes32 pauseType) internal {
        if (!IPausable(target).paused(pauseType)) IPausable(target).pause(pauseType, true);
    }

    function _freezeUsm(address usm) internal {
        if (!IUsm(usm).getIsFrozen()) IUsm(usm).setSwapFreeze(true);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
