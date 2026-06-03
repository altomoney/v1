// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Metadata for a whitelisted swap target used during migration(rollover).
struct SwapTargetMetadata {
    /// @notice Address that receives token approval before the swap is executed.
    address approveTarget;
    /// @notice Whether swap target is whitelisted.
    bool isValid;
}

interface IWrapperTokenErrors {
    /// @notice Thrown when the address is zero.
    error ZeroAddress();

    /// @notice Thrown when function inputs fail validation.
    error InvalidInput();

    /// @notice Thrown when `swap` is called while the contract is not paused.
    error IsNotPaused(bytes32 pauseType);

    /// @notice Thrown when the external swap call reverts or returns failure.
    error SwapFailed();

    error MinAmountOutNotMet(uint256 minAmountOut, uint256 buyTokenBalanceReceived);

    error SellTokenBalanceLeftover(uint256 sellTokenBalanceLeftover);

    error ExchangeRateZero();

    error NotRollOverBot();
}

interface IWrapperTokenEvents {
    /// @notice Emitted when the underlying token is already set for wrapper token.
    event UnderlyingTokenSet(address oldUnderlyingToken, address newUnderlyingToken);

    /// @notice Emitted when exchange rate between underlying token to wrapper token is updated
    event ExchangeRateUpdated(uint256 exchangeRate);

    /// @notice Emitted when a user wraps underlying token into wrapped token.
    event Wrapped(address indexed user, uint256 assetAmount, uint256 wrappedTokenAmount);

    /// @notice Emitted when a user unwraps wrapped token to underlying token.
    event Unwrapped(address indexed user, uint256 wrappedTokenAmount, uint256 assetAmount);

    /// @notice Emitted when the owner migrates the full underlying token balance to a new underlying token via rollover(swap).
    event Rollover(
        address indexed sellToken, address indexed buyToken, uint256 amountIn, uint256 buyTokenBalanceReceived
    );

    /// @notice Emitted when a swap target whitelist entry is set or removed.
    event SetSwapTargetToApproveTarget(address indexed swapTarget, address indexed approveTarget, bool isValid);

    /// @notice Emitted when the roll over bot is set.
    event RollOverBotSet(address oldRollOverBot, address newRollOverBot);
}

/// @title IWrapperTokenBase
/// @notice Interface for an ERC20 wrapper around a underlying token with wrap/unwrap and owner-controlled underlying token migration/rollover.
interface IWrapperTokenBase is IWrapperTokenErrors, IWrapperTokenEvents {
    /// @notice Returns the current underlying token held by the wrapper.
    function underlyingToken() external view returns (address);

    /// @notice Returns the number of decimals, fixed at deployment from the initial underlying token.
    /// @dev The decimals of underlying tokens should always be same as initial underlying token even after migration/rollover.
    function DECIMALS() external view returns (uint8);

    /// @notice Returns the exchange rate used to convert between underlying token amounts and wrapped token amounts.
    /// @dev Wrapped amount = assetAmount * 10^DECIMALS / exchangeRate.
    ///      assetAmount = wrappedTokenAmount * exchangeRate / 10^DECIMALS.
    function exchangeRate() external view returns (uint256);

    /// @notice Deposits underlying token and mints wrapped tokens to the caller.
    /// @param assetAmount Amount of underlying token to wrap.
    /// @return wrappedTokenAmount The amount of wrapped tokens minted.
    function wrap(uint256 assetAmount) external returns (uint256);

    /// @notice Returns the wrapped token amount minted for a given underlying token amount at the current exchange rate.
    /// @param assetAmount Amount of underlying token to wrap.
    /// @return wrappedTokenAmount The amount of wrapped tokens that would be minted.
    function previewWrap(uint256 assetAmount) external view returns (uint256 wrappedTokenAmount);

    /// @notice Burns wrapped tokens from the caller and returns the corresponding underlying PT.
    /// @param wrappedTokenAmount Amount of wrapped tokens to unwrap.
    /// @return assetAmount The amount of underlying token transferred.
    function unwrap(uint256 wrappedTokenAmount) external returns (uint256);

    /// @notice Returns the underlying token amount received for a given wrapped token amount at the current exchange rate.
    /// @param wrappedTokenAmount Amount of wrapped tokens to unwrap.
    /// @return assetAmount The amount of underlying token that would be transferred.
    function previewUnwrap(uint256 wrappedTokenAmount) external view returns (uint256 assetAmount);

    /// @notice Swaps the contract's full underlying token balance into a new underlying token while paused.
    /// @dev Only callable by the owner. Updates `exchangeRate` and `underlyingToken` on success.
    /// @dev it is necessary to pause this contract and market where this token is used as a collateral
    /// to prevent new wrapping and unwrapping or donation of the token until the rollover is complete because swapRoute is generated off-chain
    /// @dev amountIn is the amount for which swapData is generated
    /// oracle of market also needs to be updated based on exchangeRate
    /// @param newUnderlyingToken New underlying token to receive; must share `DECIMALS`.
    /// @param amountIn Amount of current underlying token to swap
    /// @param minAmountOut Minimum buy-token amount required for the swap to succeed.
    /// @param swapTarget Whitelisted contract that executes the swap via `swapData`.
    /// @param swapData Calldata forwarded to `swapTarget`.
    /// @dev `approveTarget` is read from the whitelist entry for `swapTarget`.
    function rollover(
        address newUnderlyingToken,
        uint256 amountIn,
        uint256 minAmountOut,
        address swapTarget,
        bytes calldata swapData
    ) external;

    /// @notice Sets or removes a whitelisted swap target and its associated approval target.
    /// @param swapTarget Swap executor address to configure.
    /// @param swapTargetMetadata Approval target and validity flag; invalid entries are deleted.
    function setSwapTargetToApproveTarget(address swapTarget, SwapTargetMetadata memory swapTargetMetadata) external;

    /// @notice Sets the roll over bot.
    /// @param _rollOverBot New roll over bot address.
    function setRollOverBot(address _rollOverBot) external;

    /// @notice Returns the roll over bot address.
    function rollOverBot() external view returns (address);
}

interface IWrapperToken is IWrapperTokenBase {
    /// @notice Returns the approval target and validity flag for a whitelisted swap target.
    function swapTargetToApproveTarget(address swapTarget) external view returns (SwapTargetMetadata memory);
}

interface IWrapperTokenStaticTypes is IWrapperTokenBase {
    /// @notice Returns the approval target and validity flag for a whitelisted swap target.
    function swapTargetToApproveTarget(address swapTarget) external view returns (address approveTarget, bool isValid);
}
