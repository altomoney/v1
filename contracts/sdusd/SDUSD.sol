// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {ISDUSDVaultStaticTypes, ISDUSDVaultBase, SDUSDInitParams} from "./interfaces/ISDUSDVault.sol";

/// @title SDUSD
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice UUPS-upgradeable ERC-4626 vault where users stake DUSD to receive non-rebasing sDUSD shares. Protocol
///         revenue is delivered by the ProtocolFeeCollector through `notifyRewardAmount` and is released
///         linearly over a configurable period, smoothing the exchange rate.
/// @dev Uses internal asset accounting (`accountedAssets`) rather than `DUSD.balanceOf(this)` so that raw
///      DUSD transfers cannot bypass the linear release schedule. Rewards never mint shares; they only
///      increase the assets backing existing shares as they unlock. Shares use 18 decimals (no virtual
///      offset); inflation resistance instead comes from ignoring raw donations, requiring deployment to make
///      a permanent seed deposit to address(1), and refusing new reward releases while
///      all outstanding shares are held by address(1).
contract SDUSD is
    Initializable,
    ERC4626Upgradeable,
    AltoOwnable2StepUpgradeable,
    UUPSUpgradeable,
    Pausable,
    ISDUSDVaultStaticTypes
{
    using SafeERC20 for IERC20;
    using FixedPointMath for uint256;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public constant MIN_REWARD_DURATION = 1 days;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public constant MAX_REWARD_DURATION = 30 days;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public seedShares;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public accountedAssets;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public rewardsForPeriod;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public periodStart;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public rewardPeriodFinish;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public rewardDuration;

    /// @inheritdoc ISDUSDVaultBase
    address public rewarder;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public depositCap;

    /// @inheritdoc ISDUSDVaultBase
    uint256 public depositCapUsage;

    /// @dev Reserved storage for future upgrades.
    uint256[41] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ISDUSDVaultBase
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(SDUSDInitParams calldata params) external initializer {
        if (
            params.admin == address(0) || params.pauser == address(0) || params.dusd == address(0)
                || params.rewarder == address(0)
        ) {
            revert SDUSDZeroAddress();
        }
        if (params.seedShares == 0) revert SDUSDZeroAmount();
        if (params.rewardDuration < MIN_REWARD_DURATION || params.rewardDuration > MAX_REWARD_DURATION) {
            revert SDUSDInvalidRewardDuration();
        }

        __ERC20_init("Staked DUSD", "sDUSD");
        __ERC4626_init(IERC20(params.dusd));
        __Ownable_init(params.admin);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        seedShares = params.seedShares;

        depositCap = params.depositCap;
        emit DepositCapUpdated(0, params.depositCap);

        _setPauser(params.pauser, PAUSE_TYPE, true);
        _setPauser(params.admin, PAUSE_TYPE, true);

        rewarder = params.rewarder;
        emit RewarderUpdated(address(0), params.rewarder);

        rewardDuration = params.rewardDuration;
        emit RewardDurationUpdated(0, params.rewardDuration);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Excludes locked (not-yet-released) rewards so the exchange rate rises smoothly as rewards unlock.
    ///      Reads internal accounting rather than `balanceOf`, so raw DUSD transfers do not affect it.
    function totalAssets() public view override returns (uint256) {
        return accountedAssets - lockedRewardsRemaining();
    }

    /// @inheritdoc ISDUSDVaultBase
    function lockedRewardsRemaining() public view returns (uint256) {
        uint256 finish = rewardPeriodFinish;
        if (block.timestamp >= finish) return 0;

        // Round the still-locked fraction up so rewards are never recognized before they fully vest.
        return rewardsForPeriod.divideWithRounding(finish - block.timestamp, finish - periodStart, true);
    }

    /// @inheritdoc ISDUSDVaultBase
    function notifyRewardAmount(uint256 amount) external whenNot(PAUSE_TYPE) {
        if (msg.sender != rewarder) revert SDUSDNotRewarder();
        if (block.timestamp < rewardPeriodFinish) revert SDUSDRewardPeriodNotFinished();
        uint256 lockedShares = balanceOf(address(1));
        if (lockedShares < seedShares) revert SDUSDNotSeeded();
        // Exclude all permanently locked shares, including later deposits and transfers to address(1).
        // This checks participation at period start. Holders may still exit during the release.
        if (totalSupply() <= lockedShares) revert SDUSDNoActiveStakers();
        if (amount == 0) revert SDUSDZeroAmount();

        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        accountedAssets += amount;

        rewardsForPeriod = amount;
        periodStart = block.timestamp;
        uint256 finish = block.timestamp + rewardDuration;
        rewardPeriodFinish = finish;

        emit RewardAdded(amount, finish);
    }

    /// @inheritdoc ISDUSDVaultBase
    function recoverUnaccountedAssets() external onlyOwner returns (uint256 recoveredAssets) {
        IERC20 assetToken = IERC20(asset());
        recoveredAssets = assetToken.balanceOf(address(this)) - accountedAssets;

        if (recoveredAssets != 0) {
            address receiver = rewarder;
            assetToken.safeTransfer(receiver, recoveredAssets);
            emit UnaccountedAssetsRecovered(receiver, recoveredAssets);
        }
    }

    /// @inheritdoc ISDUSDVaultBase
    function setRewarder(address newRewarder) external onlyOwner {
        if (newRewarder == address(0)) revert SDUSDZeroAddress();
        if (newRewarder == rewarder) revert SDUSDNoStateChange();
        emit RewarderUpdated(rewarder, newRewarder);
        rewarder = newRewarder;
    }

    /// @inheritdoc ISDUSDVaultBase
    function setRewardDuration(uint256 newRewardDuration) external onlyOwner {
        if (newRewardDuration < MIN_REWARD_DURATION || newRewardDuration > MAX_REWARD_DURATION) {
            revert SDUSDInvalidRewardDuration();
        }
        if (newRewardDuration == rewardDuration) revert SDUSDNoStateChange();
        emit RewardDurationUpdated(rewardDuration, newRewardDuration);
        rewardDuration = newRewardDuration;
    }

    /// @inheritdoc ISDUSDVaultBase
    function setDepositCap(uint256 newDepositCap) external onlyOwner {
        if (newDepositCap == depositCap) revert SDUSDNoStateChange();
        emit DepositCapUpdated(depositCap, newDepositCap);
        depositCap = newDepositCap;
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Blocked while paused.
    function deposit(uint256 assets, address receiver) public override whenNot(PAUSE_TYPE) returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Blocked while paused.
    function mint(uint256 shares, address receiver) public override whenNot(PAUSE_TYPE) returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Returns the remaining DUSD cap headroom, or 0 while paused or when the complete remaining headroom would
    ///      round down to zero shares and therefore cannot be deposited.
    function maxDeposit(address) public view override returns (uint256) {
        if (paused[PAUSE_TYPE]) return 0;

        uint256 remainingDepositCap = _remainingDepositCap();
        return _convertToShares(remainingDepositCap, Math.Rounding.Floor) == 0 ? 0 : remainingDepositCap;
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Converts the remaining DUSD cap headroom to shares with downward rounding, or returns 0 while paused.
    function maxMint(address) public view override returns (uint256) {
        if (paused[PAUSE_TYPE]) return 0;
        return _convertToShares(_remainingDepositCap(), Math.Rounding.Floor);
    }

    /// @inheritdoc IPausable
    /// @dev Only the owner may add or remove pausers.
    function setPauser(address pauser, bytes32 pauseType, bool status) external override(Pausable) onlyOwner {
        _setPauser(pauser, pauseType, status);
    }

    /// @dev Enforces that only the owner may unpause; pausers may only pause.
    function _onPause(bytes32, bool _paused) internal view override {
        if (!_paused && msg.sender != owner()) revert SDUSDUnauthorized();
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Tracks staked principal entering the vault so `totalAssets` reflects deposits without reading
    ///      `balanceOf`. Rejects non-zero deposits that round down to zero shares so assets cannot be accepted
    ///      without giving the receiver ownership in the vault.
    /// @dev Deployment invariant: immediately after initialization, the deployer deposits exactly `seedShares`
    ///      DUSD into the empty vault with address(1) as receiver, permanently locking the first minted shares.
    ///      The first deposit is therefore excluded from `depositCapUsage`.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (assets != 0 && shares == 0) revert SDUSDZeroShares();

        if (totalSupply() != 0) depositCapUsage += assets;
        accountedAssets += assets;
        super._deposit(caller, receiver, assets, shares);
    }

    /// @inheritdoc ERC4626Upgradeable
    /// @dev Removes the pooled principal represented by the burned non-seed shares, using supply before the burn.
    ///      Rewards therefore do not directly reopen deposit-cap headroom. The calculation rounds down so a
    ///      withdrawal cannot free more principal than the burned shares proportionally represent.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (shares != 0) {
            uint256 principalRemoved = Math.mulDiv(depositCapUsage, shares, totalSupply() - seedShares);
            depositCapUsage -= principalRemoved;
        }

        accountedAssets -= assets;
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Returns the unused DUSD deposit headroom without reverting when usage exceeds the configured cap.
    function _remainingDepositCap() internal view returns (uint256) {
        uint256 cap = depositCap;
        uint256 usage = depositCapUsage;
        return usage < cap ? cap - usage : 0;
    }

    /// @dev Restricts UUPS upgrades to the vault owner.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
