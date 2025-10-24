// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice The type of the market
enum MarketType {
    MINT,
    BORROW
}

/// @notice The struct for storing token address and balance
struct TokenBalance {
    /// @notice The address of the token
    address token;
    /// @notice The balance of the token
    uint256 balance;
}

interface IFeeClaimer {
    /// @notice Error thrown when the input is invalid
    error FeeClaimerInvalidInput();

    /// @notice Error thrown when the caller is not authorized to call the function
    error FeeClaimerUnauthorized();

    /// @notice Emitted when the fee claimer is set
    /// @param claimer The address of the claimer
    /// @param status The status of the claimer
    event SetFeeClaimer(address indexed claimer, bool status);

    /// @notice Emitted when the fee recipient is set
    /// @param oldFeeRecipient The old fee recipient
    /// @param newFeeRecipient The new fee recipient
    event SetFeeRecipient(address indexed oldFeeRecipient, address indexed newFeeRecipient);

    /// @notice Emitted when the DUSD is set
    /// @param oldDusd The old DUSD
    /// @param newDusd The new DUSD
    event SetDusd(address indexed oldDusd, address indexed newDusd);

    /// @notice Emitted when the markets are updated
    /// @param market The address of the market
    /// @param marketType The type of the market(MINT or BORROW)
    /// @param toAdd Whether to add or remove the market
    event UpdateMarkets(address indexed market, MarketType marketType, bool toAdd);

    /// @notice The active mint markets from which fees can be claimed
    /// @param index The index of the active mint market
    /// @return The active mint markets
    function activeMintMarkets(uint256 index) external view returns (address);

    /// @notice The active borrow markets from which fees can be claimed
    /// @param index The index of the active borrow market
    /// @return The active borrow markets
    function activeBorrowMarkets(uint256 index) external view returns (address);

    /// @notice Returns whether the address can call claimFees function
    /// @param claimer The address of the claimer
    /// @return whether the address can call claimFees function
    function feeClaimer(address claimer) external view returns (bool);

    /// @notice The address to which fees claimed will be transferred to
    /// @return The fee recipient address
    function feeRecipient() external view returns (address);

    /// @notice The address of the DUSD contract
    /// @return The DUSD address
    function dusd() external view returns (address);

    /// @notice Claims the fees and collateral from Mint markets and Borrow markets
    /// @dev can only be called by the owner or a fee claimer
    function claimFees() external;

    /// @notice Transfers the fees from the contract to the fee recipient
    /// @dev can only be called by the owner or a fee claimer
    function transferFees() external;

    /// @notice Sets whether the address can call claimFees function
    /// @param claimer The address of the claimer
    /// @param status Whether the address can call claimFees function
    function setFeeClaimer(address claimer, bool status) external;

    /// @notice Sets the address to which fees claimed will be transferred to
    /// @param feeRecipient The address to which fees claimed will be transferred to
    function setFeeRecipient(address feeRecipient) external;

    /// @notice Sets the address of the DUSD contract
    /// @param dusd The address of the DUSD contract
    function setDusd(address dusd) external;

    /// @notice Updates the markets from which fees can be claimed
    /// @param marketType The type of the market(MINT or BORROW)
    /// @param market The address of the market
    /// @param status Whether to add or remove the market
    function updateMarkets(MarketType marketType, address market, bool status) external;

    /// @notice Returns the total claimable fees from Borrow markets and Mint markets
    /// @return array of TokenBalance structs with token address and claimable balance
    function claimableFees() external view returns (TokenBalance[] memory);
}
