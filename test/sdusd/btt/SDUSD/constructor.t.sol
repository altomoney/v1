// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {ISDUSDVaultErrors, ISDUSDVaultEvents, SDUSDInitParams} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {SDUSDCommon} from "./SDUSDCommon.t.sol";

contract SDUSD_Initialize_Test is SDUSDCommon {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function test_RevertWhen_AdminIsZeroAddress() public {
        SDUSDInitParams memory params = _sdusdInitParams(SEED_SHARES, REWARD_DURATION);
        params.admin = address(0);

        _expectSdusdInitializationRevert(params, ISDUSDVaultErrors.SDUSDZeroAddress.selector);
    }

    function test_RevertWhen_PauserIsZeroAddress() public {
        SDUSDInitParams memory params = _sdusdInitParams(SEED_SHARES, REWARD_DURATION);
        params.pauser = address(0);

        _expectSdusdInitializationRevert(params, ISDUSDVaultErrors.SDUSDZeroAddress.selector);
    }

    function test_RevertWhen_DusdIsZeroAddress() public {
        SDUSDInitParams memory params = _sdusdInitParams(SEED_SHARES, REWARD_DURATION);
        params.dusd = address(0);

        _expectSdusdInitializationRevert(params, ISDUSDVaultErrors.SDUSDZeroAddress.selector);
    }

    function test_RevertWhen_RewarderIsZeroAddress() public {
        SDUSDInitParams memory params = _sdusdInitParams(SEED_SHARES, REWARD_DURATION);
        params.rewarder = address(0);

        _expectSdusdInitializationRevert(params, ISDUSDVaultErrors.SDUSDZeroAddress.selector);
    }

    function test_RevertWhen_SeedSharesIsZero() public {
        SDUSDInitParams memory params = _sdusdInitParams(0, REWARD_DURATION);

        _expectSdusdInitializationRevert(params, ISDUSDVaultErrors.SDUSDZeroAmount.selector);
    }

    function test_RevertWhen_RewardDurationIsBelowMinimum() public {
        SDUSDInitParams memory params = _sdusdInitParams(SEED_SHARES, 1 days - 1);

        _expectSdusdInitializationRevert(params, ISDUSDVaultErrors.SDUSDInvalidRewardDuration.selector);
    }

    function test_RevertWhen_RewardDurationIsAboveMaximum() public {
        SDUSDInitParams memory params = _sdusdInitParams(SEED_SHARES, 30 days + 1);

        _expectSdusdInitializationRevert(params, ISDUSDVaultErrors.SDUSDInvalidRewardDuration.selector);
    }

    function test_RevertWhen_ImplementationIsInitialized() public {
        SDUSD implementation = new SDUSD();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(_sdusdInitParams(SEED_SHARES, REWARD_DURATION));
    }

    function test_RevertWhen_ProxyIsInitializedTwice() public {
        SDUSD deployed = _deployVault(SEED_SHARES, REWARD_DURATION);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        deployed.initialize(_sdusdInitParams(SEED_SHARES, REWARD_DURATION));
    }

    function test_InitializesAllConfigurationMetadataAndStateAndEmitsEvents() public {
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(address(0), ADMIN);
        vm.expectEmit(false, false, false, true);
        emit ISDUSDVaultEvents.DepositCapUpdated(0, INITIAL_DEPOSIT_CAP);
        vm.expectEmit(true, true, false, true);
        emit IPausable.PauserUpdated(PAUSER, PAUSE_TYPE, true);
        vm.expectEmit(true, true, false, true);
        emit IPausable.PauserUpdated(ADMIN, PAUSE_TYPE, true);
        vm.expectEmit(true, true, false, true);
        emit ISDUSDVaultEvents.RewarderUpdated(address(0), address(collector));
        vm.expectEmit(false, false, false, true);
        emit ISDUSDVaultEvents.RewardDurationUpdated(0, REWARD_DURATION);

        SDUSD deployed = _deployVault(SEED_SHARES, REWARD_DURATION);

        assertEq(deployed.owner(), ADMIN);
        assertEq(deployed.pendingOwner(), address(0));
        assertEq(deployed.asset(), address(dusd));
        assertEq(deployed.name(), "Staked DUSD");
        assertEq(deployed.symbol(), "sDUSD");
        assertEq(deployed.decimals(), dusd.decimals());
        assertEq(deployed.seedShares(), SEED_SHARES);
        assertEq(deployed.depositCap(), INITIAL_DEPOSIT_CAP);
        assertEq(deployed.depositCapUsage(), 0);
        assertEq(deployed.rewarder(), address(collector));
        assertEq(deployed.rewardDuration(), REWARD_DURATION);
        assertTrue(deployed.pausers(PAUSER, PAUSE_TYPE));
        assertTrue(deployed.pausers(ADMIN, PAUSE_TYPE));
        assertFalse(deployed.paused(PAUSE_TYPE));
        assertFalse(deployed.paused(FROZEN_TYPE));
        assertTrue(deployed.pausers(PAUSER, FROZEN_TYPE));
        assertTrue(deployed.pausers(ADMIN, FROZEN_TYPE));
        assertEq(deployed.accountedAssets(), 0);
        assertEq(deployed.rewardsForPeriod(), 0);
        assertEq(deployed.periodStart(), 0);
        assertEq(deployed.rewardPeriodFinish(), 0);
        assertEq(deployed.totalSupply(), 0);
        assertEq(deployed.totalAssets(), 0);
        assertEq(deployed.convertToAssets(1 ether), 1 ether);
        assertEq(deployed.convertToShares(1 ether), 1 ether);
    }

    function test_AllowsMinimumRewardDuration() public {
        SDUSD deployed = _deployVault(1, 1 days);
        assertEq(deployed.rewardDuration(), deployed.MIN_REWARD_DURATION());
    }

    function test_AllowsMaximumRewardDuration() public {
        SDUSD deployed = _deployVault(1, 30 days);
        assertEq(deployed.rewardDuration(), deployed.MAX_REWARD_DURATION());
    }

    function test_AllowsZeroDepositCap() public {
        SDUSD deployed = _deployVaultWithCap(SEED_SHARES, REWARD_DURATION, 0);
        assertEq(deployed.depositCap(), 0);
        assertEq(deployed.depositCapUsage(), 0);
    }

    function test_DeploymentSetupLocksOneDusdWorthOfSharesAtAddressOne() public view {
        assertEq(vault.seedShares(), 1 ether);
        assertEq(vault.balanceOf(address(1)), 1 ether);
        assertEq(vault.convertToAssets(vault.balanceOf(address(1))), 1 ether);
        assertEq(dusd.balanceOf(address(vault)), vault.accountedAssets());
    }

    function test_DeploymentSeedDepositIsExcludedFromDepositCapUsage() public {
        _useEmptyVault();
        _depositFor(SEED_LOCK, SEED_SHARES);

        assertEq(vault.balanceOf(SEED_LOCK), SEED_SHARES);
        assertEq(dusd.balanceOf(address(vault)), SEED_SHARES);
        assertEq(vault.accountedAssets(), SEED_SHARES);
        assertEq(vault.depositCapUsage(), 0);
    }

    function test_DeploymentUserDepositAfterSeedConsumesDepositCap() public view {
        assertEq(vault.depositCapUsage(), SEED_SHARES);
    }
}
