// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {MarketConfig, PendingUint192, PendingAddress} from "@alto/lending/libraries/PendingLib.sol";
import {IMarketRegistry} from "@alto/utils/interfaces/IMarketRegistry.sol";

struct MarketAllocation {
    /// @notice The market to allocate.
    address market;
    /// @notice The amount of assets to allocate.
    uint256 assets;
}

interface IAltoVaultErrors {
    /// @notice Thrown when the address passed is the zero address.
    error ZeroAddress();

    /// @notice Thrown when the caller doesn't have the curator role.
    error NotCuratorRole();

    /// @notice Thrown when the caller doesn't have the allocator role.
    error NotAllocatorRole();

    /// @notice Thrown when the caller doesn't have the guardian role.
    error NotGuardianRole();

    /// @notice Thrown when the caller doesn't have the curator nor the guardian role.
    error NotCuratorNorGuardianRole();

    /// @notice Thrown when the market cannot be set in the supply queue.
    error UnauthorizedMarket(address market);

    /// @notice Thrown when submitting a cap for a market whose loan token does not correspond to the underlying asset.
    error InconsistentAsset(address market);

    /// @notice Thrown when the supply cap has been exceeded on market during a reallocation of funds.
    error SupplyCapExceeded(address market);

    /// @notice Thrown when the fee to set exceeds the maximum fee.
    error MaxFeeExceeded();

    /// @notice Thrown when the value is already set.
    error AlreadySet();

    /// @notice Thrown when a value is already pending.
    error AlreadyPending();

    /// @notice Thrown when submitting the removal of a market when there is a cap already pending on that market.
    error PendingCap(address market);

    /// @notice Thrown when submitting a cap for a market with a pending removal.
    error PendingRemoval();

    /// @notice Thrown when submitting a market removal for a market with a non zero cap.
    error NonZeroCap();

    /// @notice Thrown when market is a duplicate in the new withdraw queue to set.
    error DuplicateMarket(address market);

    /// @notice Thrown when market is missing in the updated withdraw queue and the market has a non-zero cap set.
    error InvalidMarketRemovalNonZeroCap(address market);

    /// @notice Thrown when market is missing in the updated withdraw queue and the market has a non-zero supply.
    error InvalidMarketRemovalNonZeroSupply(address market);

    /// @notice Thrown when market is missing in the updated withdraw queue and the market is not yet disabled.
    error InvalidMarketRemovalTimelockNotElapsed(address market);

    /// @notice Thrown when there's no pending value to set.
    error NoPendingValue();

    /// @notice Thrown when the requested liquidity cannot be withdrawn from market.
    error NotEnoughLiquidity();

    /// @notice Thrown when interacting with a non previously enabled market.
    error MarketNotEnabled(address market);

    /// @notice Thrown when the submitted timelock is above the max timelock.
    error AboveMaxTimelock();

    /// @notice Thrown when the submitted timelock is below the min timelock.
    error BelowMinTimelock();

    /// @notice Thrown when the timelock is not elapsed.
    error TimelockNotElapsed();

    /// @notice Thrown when too many markets are in the withdraw queue.
    error MaxQueueLengthExceeded();

    /// @notice Thrown when setting the fee to a non zero value while the fee recipient is the zero address.
    error ZeroFeeRecipient();

    /// @notice Thrown when the amount withdrawn is not exactly the amount supplied.
    error InconsistentReallocation();

    /// @notice Thrown when all caps have been reached.
    error AllCapsReached();

    /// @notice Thrown when the market is not registered in the MarketRegistry.
    error MarketNotInRegistry(address market);
}

interface IAltoVaultEvents {
    /// @notice Emitted when a pending `newTimelock` is submitted.
    event SubmitTimelock(uint256 newTimelock);

    /// @notice Emitted when `timelock` is set to `newTimelock`.
    event SetTimelock(address indexed caller, uint256 newTimelock);

    /// @notice Emitted when `marketRegistry` is set to `newMarketRegistry`.
    event SetMarketRegistry(address indexed newMarketRegistry);

    /// @notice Emitted when `skimRecipient` is set to `newSkimRecipient`.
    event SetSkimRecipient(address indexed newSkimRecipient);

    /// @notice Emitted when `fee` is set to `newFee`.
    event SetFee(address indexed caller, uint256 newFee);

    /// @notice Emitted when a new `newFeeRecipient` is set.
    event SetFeeRecipient(address indexed newFeeRecipient);

    /// @notice Emitted when the name of the vault is set to `newName`.
    event SetName(string indexed newName);

    /// @notice Emitted when the symbol of the vault is set to `newSymbol`.
    event SetSymbol(string indexed newSymbol);

    /// @notice Emitted when a pending `newGuardian` is submitted.
    event SubmitGuardian(address indexed newGuardian);

    /// @notice Emitted when `guardian` is set to `newGuardian`.
    event SetGuardian(address indexed caller, address indexed guardian);

    /// @notice Emitted when a pending `cap` is submitted for market.
    event SubmitCap(address indexed caller, address indexed market, uint256 cap);

    /// @notice Emitted when a new `cap` is set for market.
    event SetCap(address indexed caller, address indexed market, uint256 cap);

    /// @notice Emitted when the vault's last total assets is updated to `updatedTotalAssets`.
    event UpdateLastTotalAssets(uint256 updatedTotalAssets);

    /// @notice Emitted when the vault's lostAssets is updated to `newLostAssets`.
    event UpdateLostAssets(uint256 newLostAssets);

    /// @notice Emitted when the market is submitted for removal.
    event SubmitMarketRemoval(address indexed caller, address indexed market);

    /// @notice Emitted when `curator` is set to `newCurator`.
    event SetCurator(address indexed newCurator);

    /// @notice Emitted when an `allocator` is set to `isAllocator`.
    event SetIsAllocator(address indexed allocator, bool isAllocator);

    /// @notice Emitted when a `pendingTimelock` is revoked.
    event RevokePendingTimelock(address indexed caller);

    /// @notice Emitted when a `pendingCap` for the market is revoked.
    event RevokePendingCap(address indexed caller, address indexed market);

    /// @notice Emitted when a `pendingGuardian` is revoked.
    event RevokePendingGuardian(address indexed caller);

    /// @notice Emitted when a pending market removal is revoked.
    event RevokePendingMarketRemoval(address indexed caller, address indexed market);

    /// @notice Emitted when the `supplyQueue` is set to `newSupplyQueue`.
    event SetSupplyQueue(address indexed caller, address[] newSupplyQueue);

    /// @notice Emitted when the `withdrawQueue` is set to `newWithdrawQueue`.
    event SetWithdrawQueue(address indexed caller, address[] newWithdrawQueue);

    /// @notice Emitted when a reallocation supplies assets to the market.
    event ReallocateSupply(
        address indexed caller, address indexed market, uint256 suppliedAssets, uint256 suppliedShares
    );

    /// @notice Emitted when a reallocation withdraws assets from the market.
    event ReallocateWithdraw(
        address indexed caller, address indexed market, uint256 withdrawnAssets, uint256 withdrawnShares
    );

    /// @notice Emitted when interest is accrued.
    event AccrueInterest(uint256 newTotalAssets, uint256 feeShares);

    /// @notice Emitted when an `amount` of `token` is transferred to the skim recipient by `caller`.
    event Skim(address indexed caller, address indexed token, uint256 amount);
}

/// @dev This interface is used for factorizing IAltoVaultStaticTypes and IAltoVault.
/// @dev Consider using the IAltoVault interface instead of this one.
interface IAltoVaultBase is IAltoVaultErrors, IAltoVaultEvents {
    /// @notice OpenZeppelin decimals offset used by the ERC4626 implementation.
    /// @dev Calculated to be max(0, 18 - underlyingDecimals).
    /// @dev When equal to zero (<=> token decimals >= 18), the protection against the inflation front-running attack on
    /// empty vault is low (see https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack). To protect
    /// against this attack, vault deployers should make an initial deposit of a non-trivial amount in the vault or
    /// depositors should check that the share price does not exceed a certain limit.
    function DECIMALS_OFFSET() external view returns (uint8);

    /// @notice The market registry used to validate markets.
    function marketRegistry() external view returns (IMarketRegistry);

    /// @notice The address of the curator.
    function curator() external view returns (address);

    /// @notice Stores whether an address is an allocator or not.
    function isAllocator(address target) external view returns (bool);

    /// @notice The current guardian. Can be set even without the timelock set.
    function guardian() external view returns (address);

    /// @notice The current fee.
    function fee() external view returns (uint96);

    /// @notice The fee recipient.
    function feeRecipient() external view returns (address);

    /// @notice The skim recipient.
    function skimRecipient() external view returns (address);

    /// @notice The current timelock.
    function timelock() external view returns (uint256);

    /// @dev Stores the order of markets on which liquidity is supplied upon deposit.
    /// @dev Can contain any market. A market is skipped as soon as its supply cap is reached.
    function supplyQueue(uint256) external view returns (address);

    /// @notice Returns the length of the supply queue.
    function supplyQueueLength() external view returns (uint256);

    /// @dev Stores the order of markets from which liquidity is withdrawn upon withdrawal.
    /// @dev Always contain all non-zero cap markets as well as all markets on which the vault supplies liquidity,
    /// without duplicate.
    function withdrawQueue(uint256) external view returns (address);

    /// @notice Returns the length of the withdraw queue.
    function withdrawQueueLength() external view returns (uint256);

    /// @notice Stores the total assets managed by this vault when the fee was last accrued.
    function lastTotalAssets() external view returns (uint256);

    /// @notice Stores the missing assets due to realized bad debt or forced market removal.
    /// @dev In order to cover those lost assets, it is advised to supply on behalf of address(1) on the vault
    /// (canonical method).
    function lostAssets() external view returns (uint256);

    /// @notice Submits a `newTimelock`.
    /// @dev Warning: Reverts if a timelock is already pending. Revoke the pending timelock to overwrite it.
    /// @dev In case the new timelock is higher than the current one, the timelock is set immediately.
    function submitTimelock(uint256 newTimelock) external;

    /// @notice Accepts the pending timelock.
    function acceptTimelock() external;

    /// @notice Revokes the pending timelock.
    /// @dev Does not revert if there is no pending timelock.
    function revokePendingTimelock() external;

    /// @notice Submits a `newSupplyCap` for the market at `market`.
    /// @dev Warning: Reverts if a cap is already pending. Revoke the pending cap to overwrite it.
    /// @dev Warning: Reverts if a market removal is pending.
    /// @dev In case the new cap is lower than the current one, the cap is set immediately.
    function submitCap(address market, uint256 newSupplyCap) external;

    /// @notice Accepts the pending cap for the market at `market`.
    function acceptCap(address market) external;

    /// @notice Revokes the pending cap of the market
    /// @dev Does not revert if there is no pending cap.
    function revokePendingCap(address market) external;

    /// @notice Submits a forced market removal from the vault, eventually losing all funds supplied to the market.
    /// @notice This forced removal is expected to be used as an emergency process in case a market constantly reverts.
    /// To softly remove a sane market, the curator role is expected to bundle a reallocation that empties the market
    /// first (using `reallocate`), followed by the removal of the market (using `updateWithdrawQueue`).
    /// @dev Warning: Reverts for non-zero cap or if there is a pending cap. Successfully submitting a zero cap will
    /// prevent such reverts.
    function submitMarketRemoval(address market) external;

    /// @notice Revokes the pending removal of the market
    /// @dev Does not revert if there is no pending market removal.
    function revokePendingMarketRemoval(address market) external;

    /// @notice Sets the name of the vault.
    function setName(string memory newName) external;

    /// @notice Sets the symbol of the vault.
    function setSymbol(string memory newSymbol) external;

    /// @notice Submits a `newGuardian`.
    /// @notice Warning: a malicious guardian could disrupt the vault's operation, and would have the power to revoke
    /// any pending guardian.
    /// @dev In case there is no guardian, the guardian is set immediately.
    /// @dev Warning: Submitting a guardian will overwrite the current pending guardian.
    function submitGuardian(address newGuardian) external;

    /// @notice Accepts the pending guardian.
    function acceptGuardian() external;

    /// @notice Revokes the pending guardian.
    function revokePendingGuardian() external;

    /// @notice Skims the vault `token` balance to `skimRecipient`.
    function skim(address) external;

    /// @notice Sets `newAllocator` as an allocator or not (`newIsAllocator`).
    function setIsAllocator(address newAllocator, bool newIsAllocator) external;

    /// @notice Sets `marketRegistry` to `newMarketRegistry`.
    function setMarketRegistry(address newMarketRegistry) external;

    /// @notice Sets `curator` to `newCurator`.
    function setCurator(address newCurator) external;

    /// @notice Sets the `fee` to `newFee`.
    function setFee(uint256 newFee) external;

    /// @notice Sets `feeRecipient` to `newFeeRecipient`.
    function setFeeRecipient(address newFeeRecipient) external;

    /// @notice Sets `skimRecipient` to `newSkimRecipient`.
    function setSkimRecipient(address newSkimRecipient) external;

    /// @notice Sets `supplyQueue` to `newSupplyQueue`.
    /// @param newSupplyQueue is an array of enabled markets, and can contain duplicate markets, but it would only
    /// increase the cost of depositing to the vault.
    function setSupplyQueue(address[] calldata newSupplyQueue) external;

    /// @notice Updates the withdraw queue. Some markets can be removed, but no market can be added.
    /// @notice Removing a market requires the vault to have 0 supply on it, or to have previously submitted a removal
    /// for this market (with the function `submitMarketRemoval`).
    /// @notice Warning: Anyone can supply on behalf of the vault so the call to `updateWithdrawQueue` that expects a
    /// market to be empty can be griefed by a front-run. To circumvent this, the allocator can simply bundle a
    /// reallocation that withdraws max from this market with a call to `updateWithdrawQueue`.
    /// @dev Warning: Removing a market with supply will decrease the fee accrued until one of the functions updating
    /// `lastTotalAssets` is triggered (deposit/mint/withdraw/redeem/setFee/setFeeRecipient).
    /// @dev Warning: `updateWithdrawQueue` is not idempotent. Submitting twice the same tx will change the queue twice.
    /// @param indexes The indexes of each market in the previous withdraw queue, in the new withdraw queue's order.
    function updateWithdrawQueue(uint256[] calldata indexes) external;

    /// @notice Reallocates the vault's liquidity so as to reach a given allocation of assets on each given market.
    /// @dev The behavior of the reallocation can be altered by state changes, including:
    /// - Deposits on the vault that supplies to markets that are expected to be supplied to during reallocation.
    /// - Withdrawals from the vault that withdraws from markets that are expected to be withdrawn from during
    /// reallocation.
    /// - Donations to the vault on markets that are expected to be supplied to during reallocation.
    /// - Withdrawals from markets that are expected to be withdrawn from during reallocation.
    /// @dev Sender is expected to pass `assets = type(uint256).max` with the last MarketAllocation of `allocations` to
    /// supply all the remaining withdrawn liquidity, which would ensure that `totalWithdrawn` = `totalSupplied`.
    /// @dev A supply in a reallocation step will make the reallocation revert if the amount is greater than the net
    /// amount from previous steps (i.e. total withdrawn minus total supplied).
    function reallocate(MarketAllocation[] calldata allocations) external;
}

/// @dev This interface is inherited by AltoVault so that function signatures are checked by the compiler.
/// @dev Consider using the IAltoVault interface instead of this one.
interface IAltoVaultStaticTypes is IAltoVaultBase {
    /// @notice Returns the current configuration of each market.
    function config(address market) external view returns (uint184 cap, bool enabled, uint64 removableAt);

    /// @notice Returns the pending guardian.
    function pendingGuardian() external view returns (address guardian, uint64 validAt);

    /// @notice Returns the pending cap for each market.
    function pendingCap(address market) external view returns (uint192 value, uint64 validAt);

    /// @notice Returns the pending timelock.
    function pendingTimelock() external view returns (uint192 value, uint64 validAt);
}

/// @title IAltoVault
/// @author GPM
/// @author Adapted from Morpho Labs' IMetaMorphoV1.1 (https://github.com/morpho-org/metamorpho-v1.1/blob/main/src/interfaces/IMetaMorphoV1_1.sol)
/// @custom:contact security@altofoundation.org
/// @dev Use this interface for AltoVault to have access to all the functions with the appropriate function signatures.
interface IAltoVault is IAltoVaultBase {
    /// @notice Returns the current configuration of each market.
    function config(address market) external view returns (MarketConfig memory);

    /// @notice Returns the pending guardian.
    function pendingGuardian() external view returns (PendingAddress memory);

    /// @notice Returns the pending cap for each market.
    function pendingCap(address market) external view returns (PendingUint192 memory);

    /// @notice Returns the pending timelock.
    function pendingTimelock() external view returns (PendingUint192 memory);
}
