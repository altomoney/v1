// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";
import {IStableTokenFacilitator} from "@alto/usm/interfaces/IStableTokenFacilitator.sol";
import {IMarketStaticTypes} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {IDUSDFlashMinter} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {ISDUSDVault} from "./interfaces/ISDUSDVault.sol";
import {
    IProtocolFeeCollectorStaticTypes,
    IProtocolFeeCollectorBase,
    IAltoMintMarketFees,
    FeeSourceType,
    ProtocolFeeCollectorInitParams
} from "./interfaces/IProtocolFeeCollector.sol";

/// @title ProtocolFeeCollector
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Collects DUSD protocol fees from borrow/mint markets, USMs and the flash minter, then splits
///         the collected DUSD between the treasury and the sDUSD vault. Liquidation fee collateral is
///         withdrawn through a restricted path to a fixed manual-swap receiver
///         which will swap the collateral to DUSD and add back to this contract
/// @dev This contract should be configured as the single fee recipient of every source.
contract ProtocolFeeCollector is
    Initializable,
    AltoOwnable2StepUpgradeable,
    UUPSUpgradeable,
    Pausable,
    IProtocolFeeCollectorStaticTypes
{
    using SafeERC20 for IERC20;
    using AssetShareConversionMath for uint256;
    using FixedPointMath for uint256;

    /// @inheritdoc IProtocolFeeCollectorBase
    uint256 public constant PERCENTAGE_PRECISION = 10_000;

    /// @inheritdoc IProtocolFeeCollectorBase
    mapping(address => bool) public isCollateralOperator;

    /// @inheritdoc IProtocolFeeCollectorBase
    address public dusd;

    /// @inheritdoc IProtocolFeeCollectorBase
    address public sdusdVault;

    /// @inheritdoc IProtocolFeeCollectorBase
    address public treasury;

    /// @inheritdoc IProtocolFeeCollectorBase
    address public manualSwapReceiver;

    /// @inheritdoc IProtocolFeeCollectorBase
    address public flashMinter;

    /// @inheritdoc IProtocolFeeCollectorBase
    IMarketRegistry public marketRegistry;

    /// @inheritdoc IProtocolFeeCollectorBase
    IUsmRegistry public usmRegistry;

    /// @inheritdoc IProtocolFeeCollectorBase
    uint256 public rewardsBps;

    /// @inheritdoc IProtocolFeeCollectorBase
    uint256 public minimumRewardAmount;

    /// upgrade gap
    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the ProtocolFeeCollector
    /// @param params The initialization parameters
    function initialize(ProtocolFeeCollectorInitParams calldata params) external initializer {
        if (
            params.admin == address(0) || params.collateralOperator == address(0) || params.pauser == address(0)
                || params.dusd == address(0)
        ) {
            revert ProtocolFeeCollectorZeroAddress();
        }

        __Ownable_init(params.admin);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        _setCollateralOperator(params.collateralOperator, true);

        _setPauser(params.pauser, PAUSE_TYPE, true);
        _setPauser(params.admin, PAUSE_TYPE, true);

        dusd = params.dusd;

        _setMarketRegistry(params.marketRegistry);
        _setUsmRegistry(params.usmRegistry);
        _setFlashMinter(params.flashMinter);
        _setTreasury(params.treasury);
        _setManualSwapReceiver(params.manualSwapReceiver);

        if (params.rewardsBps != 0) {
            _setRewardsBps(params.rewardsBps);
        }
        _setMinimumRewardAmount(params.minimumRewardAmount);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function harvest(FeeSourceType[] calldata sourceTypes, address[] calldata sources) external whenNot(PAUSE_TYPE) {
        uint256 length = sourceTypes.length;
        if (length != sources.length) revert ProtocolFeeCollectorLengthMismatch();

        for (uint256 i; i < length; ++i) {
            _harvest(sourceTypes[i], sources[i]);
        }
    }

    /// @dev Isolates each source so validation or execution reverts cannot roll back other harvests.
    /// @param sourceType The type of the source being harvested
    /// @param source The address of the source being harvested
    function _harvest(FeeSourceType sourceType, address source) internal {
        try this.harvestSource(sourceType, source) {}
        catch {
            emit HarvestingFailed(sourceType, source);
        }
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function harvestSource(FeeSourceType sourceType, address source) external {
        if (msg.sender != address(this)) revert ProtocolFeeCollectorUnauthorized();

        uint256 balanceBefore = IERC20(dusd).balanceOf(address(this));

        if (sourceType == FeeSourceType.BORROW_MARKET) {
            if (!_validateAndHarvestBorrowMarket(source)) {
                emit HarvestingFailed(sourceType, source);
                return;
            }
        } else if (sourceType == FeeSourceType.MINT_MARKET) {
            if (!_validateAndHarvestMintMarket(source)) {
                emit HarvestingFailed(sourceType, source);
                return;
            }
        } else if (sourceType == FeeSourceType.USM) {
            if (!_validateAndHarvestUsm(source)) {
                emit HarvestingFailed(sourceType, source);
                return;
            }
        } else if (sourceType == FeeSourceType.FLASH_MINTER) {
            if (!_validateAndHarvestFlashMinter(source)) {
                emit HarvestingFailed(sourceType, source);
                return;
            }
        } else {
            revert ProtocolFeeCollectorInvalidSource(source);
        }

        uint256 dusdReceived = IERC20(dusd).balanceOf(address(this)) - balanceBefore;
        emit Harvested(sourceType, source, dusdReceived);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function distribute() external whenNot(PAUSE_TYPE) {
        _harvestAll();

        IERC20 _dusd = IERC20(dusd);
        uint256 collected = _dusd.balanceOf(address(this));
        // round down for the vault in favor of treasury
        uint256 rewardAmount = collected.divideWithRounding(rewardsBps, PERCENTAGE_PRECISION, false);

        uint256 _minimumRewardAmount = minimumRewardAmount;
        if (rewardAmount != 0 && rewardAmount < _minimumRewardAmount) {
            emit DistributionDeferred(collected, rewardAmount, _minimumRewardAmount);
            return;
        }

        uint256 treasuryAmount = collected - rewardAmount;

        address _sdusdVault = sdusdVault;
        if (treasuryAmount != 0) {
            _dusd.safeTransfer(treasury, treasuryAmount);
        }

        if (rewardAmount != 0) {
            if (_sdusdVault == address(0)) revert ProtocolFeeCollectorSdusdNotSet();
            if (block.timestamp < ISDUSDVault(_sdusdVault).rewardPeriodFinish()) {
                revert ProtocolFeeCollectorRewardPeriodNotFinished();
            }

            // sdusdVault will pull the rewardAmount from this contract
            _dusd.forceApprove(_sdusdVault, rewardAmount);
            ISDUSDVault(_sdusdVault).notifyRewardAmount(rewardAmount);
            _dusd.forceApprove(_sdusdVault, 0);
        }

        emit Distributed(collected, treasuryAmount, rewardAmount);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function withdrawLiquidationFees(address[] calldata markets, uint256[] calldata amounts)
        external
        whenNot(PAUSE_TYPE)
    {
        if (!isCollateralOperator[msg.sender]) revert ProtocolFeeCollectorUnauthorized();

        uint256 length = markets.length;
        if (length != amounts.length) revert ProtocolFeeCollectorLengthMismatch();

        IMarketRegistry registry = marketRegistry;
        address receiver = manualSwapReceiver;

        for (uint256 i; i < length; ++i) {
            address market = markets[i];

            if (!registry.isBorrowMarket(market) && !registry.isMintMarket(market)) {
                revert ProtocolFeeCollectorInvalidSource(market);
            }

            if (IMarketStaticTypes(market).borrowToken() != dusd) {
                revert ProtocolFeeCollectorInvalidSource(market);
            }

            IMarketStaticTypes(market).removeCollateral(amounts[i], address(this), receiver, "");

            emit LiquidationFeesWithdrawn(market, receiver, amounts[i]);
        }
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function setTreasury(address newTreasury) external onlyOwner {
        _setTreasury(newTreasury);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function setRewardsBps(uint256 newRewardsBps) external onlyOwner {
        _setRewardsBps(newRewardsBps);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function setMinimumRewardAmount(uint256 newMinimumRewardAmount) external onlyOwner {
        _setMinimumRewardAmount(newMinimumRewardAmount);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function setSdusdVault(address newSdusdVault) external onlyOwner {
        if (newSdusdVault == address(0)) revert ProtocolFeeCollectorZeroAddress();
        if (newSdusdVault == sdusdVault) revert ProtocolFeeCollectorNoStateChange();
        emit SdusdUpdated(sdusdVault, newSdusdVault);
        sdusdVault = newSdusdVault;
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function setManualSwapReceiver(address newManualSwapReceiver) external onlyOwner {
        _setManualSwapReceiver(newManualSwapReceiver);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function setFlashMinter(address newFlashMinter) external onlyOwner {
        _setFlashMinter(newFlashMinter);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function setMarketRegistry(address newMarketRegistry) external onlyOwner {
        _setMarketRegistry(newMarketRegistry);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function setUsmRegistry(address newUsmRegistry) external onlyOwner {
        _setUsmRegistry(newUsmRegistry);
    }

    /// @inheritdoc IProtocolFeeCollectorBase
    function setCollateralOperator(address operator, bool allowed) external onlyOwner {
        _setCollateralOperator(operator, allowed);
    }

    /// @inheritdoc IPausable
    /// @dev Only the owner may add or remove pausers.
    function setPauser(address pauser, bytes32 pauseType, bool status) external override(Pausable) onlyOwner {
        _setPauser(pauser, pauseType, status);
    }

    /// @notice Enforces pause restrictions for this contract.
    /// @dev Any configured pauser may pause, but only the owner may unpause.
    /// @param _paused New pause state (true when pausing, false when unpausing).
    function _onPause(bytes32, bool _paused) internal view override {
        if (!_paused && msg.sender != owner()) revert ProtocolFeeCollectorUnauthorized();
    }

    /// @dev Harvests every source configured by the market registry, USM registry, and flash-minter setting.
    function _harvestAll() internal {
        address[] memory borrowMarkets = marketRegistry.getBorrowMarkets();
        for (uint256 i; i < borrowMarkets.length; ++i) {
            _harvest(FeeSourceType.BORROW_MARKET, borrowMarkets[i]);
        }

        address[] memory mintMarkets = marketRegistry.getMintMarkets();
        for (uint256 i; i < mintMarkets.length; ++i) {
            _harvest(FeeSourceType.MINT_MARKET, mintMarkets[i]);
        }

        address[] memory usms = usmRegistry.getUsmList();
        for (uint256 i; i < usms.length; ++i) {
            _harvest(FeeSourceType.USM, usms[i]);
        }

        _harvest(FeeSourceType.FLASH_MINTER, flashMinter);
    }

    /// @dev Validates a borrow market and withdraws the collector's currently available DUSD supply from it.
    /// @param source The borrow market to withdraw from
    /// @return harvestingPassed Whether the source passed validation and its harvest completed
    function _validateAndHarvestBorrowMarket(address source) internal returns (bool harvestingPassed) {
        IMarketStaticTypes market = IMarketStaticTypes(source);
        if (!marketRegistry.isBorrowMarket(source) || market.borrowToken() != dusd || market.paused(PAUSE_TYPE)) {
            return false;
        }

        // Accrue first so the collector's supply shares convert to up-to-date assets.
        // Accruing interest on borrow markets may change the supply shares of the fee recipient(i.e. this contract)
        // because shares are minted to fee recipient based on fees accrued
        market.accrueInterest();

        (uint128 supplyShares,,) = market.position(address(this));
        if (supplyShares == 0) {
            return market.feeRecipient() == address(this);
        }

        (uint128 totalSupplyAssets, uint128 totalSupplyShares) = market.totalSupply();
        (uint128 totalBorrowedAssets,) = market.totalBorrowed();

        uint256 claimableAssets = uint256(supplyShares).convertToAssetsDown(totalSupplyAssets, totalSupplyShares);

        if (claimableAssets == 0) return true;

        // Cap by the market's actual borrow-token balance, which is what `removeSupply` physically transfers.
        uint256 availableLiquidity = Math.min(totalSupplyAssets - totalBorrowedAssets, IERC20(dusd).balanceOf(source));

        if (availableLiquidity == 0) return true;

        if (claimableAssets <= availableLiquidity) {
            // Enough free liquidity: withdraw the full share balance.
            market.removeSupply(0, supplyShares, address(this), address(this));
        } else {
            // Liquidity constrained: withdraw only what the market can currently release.
            //
            // Specifying assets makes the market convert them to shares rounding UP, then subtract those
            // shares from our position. This can never underflow, because we are in the branch where
            // `availableLiquidity < claimableAssets`. Let A = totalAssets + VA and S = totalShares + VS:
            //
            //   claimableAssets     = floor(supplyShares * A / S)      [convertToAssetsDown, rounds down]
            //   sharesToBurn  = ceil (availableLiquidity * S / A) [convertToSharesUp, rounds up]
            //
            // Step 1 - from the definition of `ownAssets` and the floor property `floor(x) <= x`:
            //
            //   claimableAssets = floor(supplyShares * A / S) <= supplyShares * A / S
            //
            // Step 2 - multiply both sides by S / A (positive, so the inequality is preserved):
            //
            //   claimableAssets * S / A <= supplyShares
            //
            // Intuition: `claimableAssets` is our shares rounded DOWN to assets, so converting those assets back
            // to shares cannot exceed the shares we started with - rounding down only throws value away.
            //
            // Step 3 - `supplyShares` is an integer and the left side is <= it, so rounding the left side
            // UP still stays <= supplyShares. Combined with `availableLiquidity < claimableAssets`:
            //
            //   sharesToBurn <= ceil(claimableAssets * S / A) <= supplyShares
            //
            // so the market always has enough of our shares to burn.
            market.removeSupply(availableLiquidity, 0, address(this), address(this));
        }

        return true;
    }

    /// @dev Validates a mint market and claims all currently available DUSD fees from it.
    /// @param source The mint market to harvest from
    /// @return harvestingPassed Whether the source passed validation and its harvest completed
    function _validateAndHarvestMintMarket(address source) internal returns (bool harvestingPassed) {
        IMarketStaticTypes market = IMarketStaticTypes(source);
        if (
            !marketRegistry.isMintMarket(source) || market.borrowToken() != dusd
                || market.feeRecipient() != address(this) || market.paused(PAUSE_TYPE)
        ) {
            return false;
        }

        market.accrueInterest();
        IAltoMintMarketFees(source).claimInterest(0);
        return true;
    }

    /// @dev Validates a USM and distributes its currently available DUSD fees to the collector.
    /// @param source The USM to harvest from
    /// @return harvestingPassed Whether the source passed validation and its harvest completed
    function _validateAndHarvestUsm(address source) internal returns (bool harvestingPassed) {
        IStableTokenFacilitator facilitator = IStableTokenFacilitator(source);
        if (
            !usmRegistry.isUsm(source) || IUsm(source).STABLE_TOKEN() != dusd
                || facilitator.getFeeRecipient() != address(this)
        ) {
            return false;
        }

        facilitator.distributeFeesToFeeRecipient();
        return true;
    }

    /// @dev Validates the configured flash minter and distributes its available DUSD fees to the collector.
    /// @param source The flash minter to harvest from
    /// @return harvestingPassed Whether the source passed validation and its harvest completed
    function _validateAndHarvestFlashMinter(address source) internal returns (bool harvestingPassed) {
        IStableTokenFacilitator facilitator = IStableTokenFacilitator(source);
        if (
            source != flashMinter || address(IDUSDFlashMinter(source).DUSD()) != dusd
                || facilitator.getFeeRecipient() != address(this)
        ) {
            return false;
        }

        facilitator.distributeFeesToFeeRecipient();
        return true;
    }

    /// @notice Sets the treasury address used for collector treasury allocations.
    /// @param newTreasury Address that will receive the treasury portion on distribution.
    function _setTreasury(address newTreasury) internal {
        if (newTreasury == address(0)) revert ProtocolFeeCollectorZeroAddress();
        if (newTreasury == treasury) revert ProtocolFeeCollectorNoStateChange();
        emit TreasuryUpdated(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// @notice Sets the fixed manual swap receiver used for liquidation-fee collateral withdrawals.
    /// @param newManualSwapReceiver Address that will receive withdrawn liquidation collateral.
    function _setManualSwapReceiver(address newManualSwapReceiver) internal {
        if (newManualSwapReceiver == address(0)) revert ProtocolFeeCollectorZeroAddress();
        if (newManualSwapReceiver == manualSwapReceiver) revert ProtocolFeeCollectorNoStateChange();
        emit ManualSwapReceiverUpdated(manualSwapReceiver, newManualSwapReceiver);
        manualSwapReceiver = newManualSwapReceiver;
    }

    /// @notice Sets the flash minter source contract used for fee harvesting.
    /// @param newFlashMinter Address of the DUSD flash minter contract.
    function _setFlashMinter(address newFlashMinter) internal {
        if (newFlashMinter == address(0)) revert ProtocolFeeCollectorZeroAddress();
        if (newFlashMinter == flashMinter) revert ProtocolFeeCollectorNoStateChange();
        emit FlashMinterUpdated(flashMinter, newFlashMinter);
        flashMinter = newFlashMinter;
    }

    /// @notice Sets the market registry used to validate borrow/mint fee sources.
    /// @param newMarketRegistry Address of the market registry.
    function _setMarketRegistry(address newMarketRegistry) internal {
        if (newMarketRegistry == address(0)) revert ProtocolFeeCollectorZeroAddress();
        if (newMarketRegistry == address(marketRegistry)) revert ProtocolFeeCollectorNoStateChange();
        emit MarketRegistryUpdated(address(marketRegistry), newMarketRegistry);
        marketRegistry = IMarketRegistry(newMarketRegistry);
    }

    /// @notice Sets the USM registry used to validate USM fee sources.
    /// @param newUsmRegistry Address of the USM registry.
    function _setUsmRegistry(address newUsmRegistry) internal {
        if (newUsmRegistry == address(0)) revert ProtocolFeeCollectorZeroAddress();
        if (newUsmRegistry == address(usmRegistry)) revert ProtocolFeeCollectorNoStateChange();
        emit UsmRegistryUpdated(address(usmRegistry), newUsmRegistry);
        usmRegistry = IUsmRegistry(newUsmRegistry);
    }

    /// @notice Adds or removes an address from the collateral-operator allowlist.
    /// @param operator Address to update.
    /// @param allowed Whether the operator is authorized for liquidation-fee withdrawals.
    function _setCollateralOperator(address operator, bool allowed) internal {
        if (operator == address(0)) revert ProtocolFeeCollectorZeroAddress();
        if (isCollateralOperator[operator] == allowed) revert ProtocolFeeCollectorNoStateChange();
        isCollateralOperator[operator] = allowed;
        emit CollateralOperatorSet(operator, allowed);
    }

    /// @notice Sets the rewards basis points split between treasury and sDUSD.
    /// @param newRewardsBps New rewards bps value, constrained to `[0, PERCENTAGE_PRECISION]`.
    function _setRewardsBps(uint256 newRewardsBps) internal {
        if (newRewardsBps > PERCENTAGE_PRECISION) revert ProtocolFeeCollectorInvalidRewardsBps();
        if (newRewardsBps == rewardsBps) revert ProtocolFeeCollectorNoStateChange();
        emit RewardsBpsUpdated(rewardsBps, newRewardsBps);
        rewardsBps = newRewardsBps;
    }

    /// @notice Sets the minimum nonzero reward required to start a new sDUSD reward period.
    /// @param newMinimumRewardAmount New minimum reward amount denominated in DUSD.
    function _setMinimumRewardAmount(uint256 newMinimumRewardAmount) internal {
        if (newMinimumRewardAmount == 0) revert ProtocolFeeCollectorInvalidMinimumRewardAmount();
        if (newMinimumRewardAmount == minimumRewardAmount) revert ProtocolFeeCollectorNoStateChange();
        emit MinimumRewardAmountUpdated(minimumRewardAmount, newMinimumRewardAmount);
        minimumRewardAmount = newMinimumRewardAmount;
    }

    /// @notice Enforces UUPS upgrade authorization.
    /// @param newImplementation Proposed implementation address.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
