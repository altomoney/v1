// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

enum IRMType {
    FIXED_RATE, // FixedRateIrm
    ADAPTIVE_CURVE // AdaptiveCurveIrm
}

interface IIrm {
    /// @notice Error thrown when the caller is not the market
    error IrmUnauthorized();

    /// @notice Error thrown when the market is already set
    error IrmMarketAlreadySet();

    /// @notice Error thrown when the market is not set
    error IrmMarketNotSet();

    /// @notice Error thrown when the parameters are invalid
    error IrmInvalidParams();

    /// @notice The type of the IRM
    /// @dev This is used to identify the type of the IRM during indexing
    function IRM_TYPE() external view returns (IRMType);

    /// @notice Sets the market for the IRM
    /// @param _market The market to set
    /// @dev This function has to be called first time by the market to set up the IRM
    function setMarket(address _market) external;

    /// @notice Called when the market is paused
    /// @param _paused The new paused state
    /// @dev This function is function is used when market of this IRM is paused/unpaused.
    /// Pausing market should also pause the accrual of interest.
    function onMarketPause(bool _paused) external;

    /// @notice Updates interest rate the the latest value
    /// @param totalSupply Total amount of assets supplied to the markets
    /// @param totalBorrowed Total amount of assets borrowed from the markets
    /// @return new interest rate in second percent yield (SPY), new interest since last update
    function updateInterestRate(uint256 totalSupply, uint256 totalBorrowed) external returns (uint256, uint256);

    /// @notice Performs compuutation of the interest rate without mutating state
    /// @param totalSupply Total amount of assets supplied to the markets
    /// @param totalBorrowed Total amount of assets borrowed from the markets
    /// @return new interest rate in second percent yield (SPY), new interest since last update
    function updateInterestRateView(uint256 totalSupply, uint256 totalBorrowed) external view returns (uint256, uint256);
}
