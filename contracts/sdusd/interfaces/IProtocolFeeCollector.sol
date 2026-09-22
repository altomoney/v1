// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";
import {IUsmRegistry} from "@alto/utils/interfaces/IUsmRegistry.sol";

/// @notice The type of a fee source the collector may harvest from
enum FeeSourceType {
    BORROW_MARKET,
    MINT_MARKET,
    USM,
    FLASH_MINTER
}

/// @notice Parameters for initializing the ProtocolFeeCollector
struct ProtocolFeeCollectorInitParams {
    /// @notice The timelock granted admin
    address admin;
    /// @notice The address granted the collateral operator role during initialization
    /// @dev there can be multiple addresses which be collateralOperator after initialization
    address collateralOperator;
    /// @notice The address granted the pauser role
    address pauser;
    /// @notice The DUSD token address
    address dusd;
    /// @notice The market registry address
    address marketRegistry;
    /// @notice The USM registry address
    address usmRegistry;
    /// @notice The flash minter address
    address flashMinter;
    /// @notice The treasury address
    address treasury;
    /// @notice The fixed manual swap receiver address which will receive the collateral from markets
    address manualSwapReceiver;
    /// @notice The reward allocation in basis points to transfer to sdusd vault
    uint256 rewardsBps;
    /// @notice The minimum nonzero DUSD reward required to start a new sDUSD reward period
    uint256 minimumRewardAmount;
}

/// @title IAltoMintMarketFees
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Minimal view of the mint market fee-claiming entrypoint (not part of IMarket).
interface IAltoMintMarketFees {
    /// @notice Claims interest and fees from the mint market by minting the borrow token to the fee recipient
    /// @param interest The amount of interest to claim (0 claims all claimable fees)
    /// @return The amount of interest and fees claimed
    function claimInterest(uint256 interest) external returns (uint256);
}

/// @title IProtocolFeeCollectorErrors
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Errors for the ProtocolFeeCollector contract
interface IProtocolFeeCollectorErrors {
    /// @notice Thrown when a provided address is the zero address
    error ProtocolFeeCollectorZeroAddress();

    /// @notice Thrown when a source must be rejected rather than skipped
    /// @dev Harvest validation failures for recognized source types emit `HarvestingFailed` and are skipped. This
    ///      error is used when a liquidation-fee withdrawal references an unregistered market or a market whose
    ///      borrow token is not DUSD, and when harvest dispatch receives an unsupported source type.
    /// @param source The source address that failed validation
    error ProtocolFeeCollectorInvalidSource(address source);

    /// @notice Thrown when `rewardsBps` is set above 10_000(i.e. percentage precision)
    error ProtocolFeeCollectorInvalidRewardsBps();

    /// @notice Thrown when the minimum reward amount is set to zero
    error ProtocolFeeCollectorInvalidMinimumRewardAmount();

    /// @notice Thrown when the sDUSD vault has not been configured yet during distribution of rewards
    error ProtocolFeeCollectorSdusdNotSet();

    /// @notice Thrown when distribute is called before the active reward release period of sDUSD vault has ended
    error ProtocolFeeCollectorRewardPeriodNotFinished();

    /// @notice Thrown when the caller lacks collateral-operator permission
    ///         or calls the source-isolation entrypoint from outside the collector
    error ProtocolFeeCollectorUnauthorized();

    /// @notice Thrown when a setter is called with a value equal to the current one
    error ProtocolFeeCollectorNoStateChange();

    /// @notice Thrown when paired input arrays have different lengths
    error ProtocolFeeCollectorLengthMismatch();
}

/// @title IProtocolFeeCollectorEvents
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Events for the ProtocolFeeCollector contract
interface IProtocolFeeCollectorEvents {
    /// @notice Emitted when fees are harvested from a source
    /// @param sourceType The type of the harvested source
    /// @param source The address of the harvested source
    /// @param dusdReceived The amount of DUSD received by the collector contract as a result of the harvest
    event Harvested(FeeSourceType indexed sourceType, address indexed source, uint256 dusdReceived);

    /// @notice Emitted when a source fails validation or reverts during harvesting and is skipped
    /// @param sourceType The type of the failed source
    /// @param source The address of the failed source
    event HarvestingFailed(FeeSourceType indexed sourceType, address indexed source);

    /// @notice Emitted when collected DUSD is distributed to the treasury and sDUSD vault
    /// @param collected The total DUSD balance distributed
    /// @param treasuryAmount The amount sent to the treasury
    /// @param rewardAmount The amount sent to the sDUSD vault as rewards
    event Distributed(uint256 collected, uint256 treasuryAmount, uint256 rewardAmount);

    /// @notice Emitted when distribution is deferred because the calculated reward is below the configured minimum
    /// @param collected The total DUSD retained in the collector
    /// @param rewardAmount The calculated reward allocation
    /// @param minimumRewardAmount The minimum reward required to start a new reward period
    event DistributionDeferred(uint256 collected, uint256 rewardAmount, uint256 minimumRewardAmount);

    /// @notice Emitted when liquidation fee collateral is withdrawn to the manual swap receiver
    /// @param market The market the collateral was withdrawn from
    /// @param receiver The manual swap receiver that received the collateral
    /// @param amount The amount of collateral withdrawn
    event LiquidationFeesWithdrawn(address indexed market, address indexed receiver, uint256 amount);

    /// @notice Emitted when the treasury address is updated
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /// @notice Emitted when the sDUSD vault address is updated
    event SdusdUpdated(address indexed oldSdusd, address indexed newSdusd);

    /// @notice Emitted when the manual swap receiver address is updated
    event ManualSwapReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);

    /// @notice Emitted when the flash minter address is updated
    event FlashMinterUpdated(address indexed oldFlashMinter, address indexed newFlashMinter);

    /// @notice Emitted when the market registry address is updated
    event MarketRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /// @notice Emitted when the USM registry address is updated
    event UsmRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);

    /// @notice Emitted when the rewards bps is updated
    event RewardsBpsUpdated(uint256 oldRewardsBps, uint256 newRewardsBps);

    /// @notice Emitted when the minimum reward amount is updated
    /// @param oldMinimumRewardAmount The previous minimum reward amount
    /// @param newMinimumRewardAmount The new minimum reward amount
    event MinimumRewardAmountUpdated(uint256 oldMinimumRewardAmount, uint256 newMinimumRewardAmount);

    /// @notice Emitted when a collateral operator's permission is set or unset
    event CollateralOperatorSet(address indexed operator, bool allowed);
}

/// @title IProtocolFeeCollectorBase
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice State-changing functions of the ProtocolFeeCollector contract
interface IProtocolFeeCollectorBase is IProtocolFeeCollectorErrors, IProtocolFeeCollectorEvents {
    /// @notice Harvests currently available DUSD fees from validated sources into the collector
    /// @dev Invalid or paused borrow- and mint-market sources, invalid USMs, and invalid flash minters are skipped and
    ///      emit `HarvestingFailed` instead of reverting or emitting `Harvested`. Reverts during a source's validation
    ///      or execution are isolated to that source, emit `HarvestingFailed`, and do not stop later sources.
    /// @param sourceTypes The types of the sources being harvested
    /// @param sources The addresses of the sources being harvested, aligned with `sourceTypes`
    function harvest(FeeSourceType[] calldata sourceTypes, address[] calldata sources) external;

    /// @notice Validates and harvests one source inside a separate call frame
    /// @dev Only callable by this collector. The harvest and distribution paths catch reverts from this call so
    ///      a failed source rolls back its own changes without reverting other sources.
    /// @param sourceType The type of the source being harvested
    /// @param source The address of the source being harvested
    function harvestSource(FeeSourceType sourceType, address source) external;

    /// @notice Harvests every configured source, then splits collected DUSD between the treasury and sDUSD vault
    /// @dev Invalid sources, paused markets and sources that revert are skipped. When a nonzero calculated reward is below
    ///      `minimumRewardAmount`, the entire balance remains in the collector for a later call. A configured vault
    ///      and a finished reward period are required only when the calculated vault reward is nonzero. The treasury
    ///      transfer and vault notification are atomic: if `notifyRewardAmount` reverts, including when the vault is
    ///      paused or only its locked seed shares remain, the treasury transfer is rolled back and its allocation
    ///      remains in this collector until a distribution can succeed.
    function distribute() external;

    /// @notice Withdraws liquidation fee collateral from markets to the manual swap receiver
    /// @dev Only a configured collateral operator may call this function. Every market must be registered as a borrow
    ///      or mint market and use DUSD as its borrow token. Collateral is always sent to the configured
    ///      `manualSwapReceiver`; neither the caller nor the input arrays can select another receiver. The complete
    ///      batch is atomic, so a failure for any market rolls back all earlier withdrawals in the same call.
    /// @param markets The markets to withdraw collateral fees from
    /// @param amounts The amounts of collateral to withdraw, aligned with `markets`
    function withdrawLiquidationFees(address[] calldata markets, uint256[] calldata amounts) external;

    /// @notice Updates the treasury address
    function setTreasury(address newTreasury) external;

    /// @notice Updates the reward allocation in basis points (0 to 10_000)
    function setRewardsBps(uint256 newRewardsBps) external;

    /// @notice Updates the minimum nonzero DUSD reward required to start a new sDUSD reward period
    /// @dev The minimum cannot be set to zero
    function setMinimumRewardAmount(uint256 newMinimumRewardAmount) external;

    /// @notice Updates the sDUSD vault address
    /// @dev The configured sDUSD vault receives future reward allocations. Replacing a vault does not migrate its
    ///      existing users, shares, assets, or reward state; the old vault remains a separate legacy vault and stops
    ///      receiving new rewards from this collector.
    function setSdusdVault(address newSdusdVault) external;

    /// @notice Updates the manual swap receiver address
    function setManualSwapReceiver(address newManualSwapReceiver) external;

    /// @notice Updates the flash minter address
    /// @dev Harvest all fees from the current flash minter before replacing it. Once replaced, its remaining fees
    ///      cannot be harvested through this collector unless the old address is configured again.
    function setFlashMinter(address newFlashMinter) external;

    /// @notice Updates the market registry address
    /// @dev Before replacing the registry, or removing a market from the current registry, harvest all DUSD fee
    ///      positions and withdraw all liquidation-fee collateral held for this collector. Positions in a market that
    ///      is absent from the configured registry are inaccessible through the collector until it is registered again.
    function setMarketRegistry(address newMarketRegistry) external;

    /// @notice Updates the USM registry address
    /// @dev Before replacing the registry, or removing a USM from the current registry, distribute all accrued fees
    ///      from that USM. Fees in a USM absent from the configured registry are inaccessible through the collector
    ///      until it is registered again.
    function setUsmRegistry(address newUsmRegistry) external;

    /// @notice Sets whether an address may withdraw liquidation fee collateral
    function setCollateralOperator(address operator, bool allowed) external;

    /// @notice Maximum value for `rewardsBps`
    function PERCENTAGE_PRECISION() external view returns (uint256);

    /// @notice Whether an address may withdraw liquidation fee collateral
    /// @dev The liquidated fee collateral will always goes to manualSwapReceiver and not collateral operator calling it
    function isCollateralOperator(address operator) external view returns (bool);

    /// @notice The DUSD token collected as protocol revenue
    function dusd() external view returns (address);

    /// @notice The sDUSD vault receiving the reward allocation
    function sdusdVault() external view returns (address);

    /// @notice The treasury receiving the non-reward allocation
    function treasury() external view returns (address);

    /// @notice The fixed protocol operations multisig receiving withdrawn liquidation collateral
    /// @dev This address receives the liquidated collateral fee from all the markets
    /// @dev This address is expected to swap liquidated collateral to DUSD and add DUSD back to the ProtocolFeeCollector contract
    function manualSwapReceiver() external view returns (address);

    /// @notice The flash minter address
    function flashMinter() external view returns (address);

    /// @notice The market registry used to validate market sources
    function marketRegistry() external view returns (IMarketRegistry);

    /// @notice The USM registry used to validate USM sources
    function usmRegistry() external view returns (IUsmRegistry);

    /// @notice The reward allocation in basis points applied on the next distribution
    function rewardsBps() external view returns (uint256);

    /// @notice The minimum nonzero DUSD reward required to start a new sDUSD reward period
    function minimumRewardAmount() external view returns (uint256);
}

/// @title IProtocolFeeCollector
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Full interface of the ProtocolFeeCollector contract
interface IProtocolFeeCollector is IProtocolFeeCollectorBase {}

/// @title IProtocolFeeCollectorStaticTypes
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Static-typed view of the ProtocolFeeCollector contract
interface IProtocolFeeCollectorStaticTypes is IProtocolFeeCollectorBase {}
