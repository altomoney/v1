// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMarketStaticTypes} from "@alto/lending/interfaces/IMarket.sol";

/// @notice Parameters used to initialize a single-account credit mint market.
struct CreditMarketInitParams {
    /// @dev Token minted when credit is drawn and burned when debt is repaid.
    address borrowToken;

    /// @dev Token deposited to support the credit account's borrowing capacity.
    address collateralToken;

    /// @dev Fixed-rate interest rate model used to accrue debt.
    address irm;

    /// @dev Initial governance owner of the market.
    address owner;

    /// @dev Lending oracle that quotes collateral in borrow-token units using
    /// 1e36 price convention.
    address oracle;

    /// @dev Sole account permitted to own collateral and debt in the facility.
    address creditAccount;

    /// @dev Account that receives minted opening fees and accrued interest when
    ///fees are claimed.
    address feeRecipient;

    /// @dev Maximum total debt assets permitted when a new draw is made.
    uint256 creditLimit;

    /// @dev Maximum post-draw loan-to-value ratio, expressed with 1e18 precision.
    uint256 maxLtv;

    /// @dev Loan-to-value ratio above which governance may foreclose, expressed
    /// with 1e18 precision.
    uint256 foreclosureLtv;

    /// @dev Fee charged on each draw and added to debt, expressed with 1e18
    /// precision.
    uint256 initialBorrowOpeningFee;
}

/// @title Alto Credit Market
///
/// @author Alto
///
/// @notice Interface for a single-account, collateral-supported mint credit facility.
interface IAltoCreditMarket is IMarketStaticTypes {
    /// @notice A required address was the zero address.
    error AltoCreditMarket__ZeroAddress();

    /// @notice An argument or proposed configuration violated a market invariant.
    error AltoCreditMarket__InvalidInput();

    /// @notice The caller or account is not authorized for the requested
    /// credit-market operation.
    error AltoCreditMarket__UnauthorizedAccount();

    /// @notice Callback or swap data was supplied to an operation that does not
    /// support callbacks.
    error AltoCreditMarket__CallbacksUnsupported();

    /// @notice A proposed draw would leave debt above the oracle-supported
    /// maximum LTV.
    error AltoCreditMarket__BorrowingTooMuch();

    /// @notice A proposed draw would leave total debt assets above the
    /// configured credit limit.
    error AltoCreditMarket__CreditLimitExceeded();

    /// @notice The lending oracle returned a zero collateral price.
    error AltoCreditMarket__InvalidOraclePrice();

    /// @notice Governance attempted to foreclose before the foreclosure LTV was
    /// breached.
    error AltoCreditMarket__PositionNotForeclosable();

    /// @notice An operation from the standard market surface is intentionally
    /// unsupported by this credit market.
    error AltoCreditMarket__UnsupportedOperation();

    /// @notice Public liquidation was attempted on a market that permits only
    /// governance foreclosure.
    error AltoCreditMarket__NonLiquidatable();

    /// @notice Collateral withdrawal was attempted while the credit account
    /// still had borrow shares.
    error AltoCreditMarket__OutstandingDebt();

    /// @notice Emitted when governance changes the maximum debt capacity of the
    /// facility.
    ///
    /// @param oldCreditLimit Previous credit limit.
    /// @param newCreditLimit New credit limit.
    event SetCreditLimit(uint256 oldCreditLimit, uint256 newCreditLimit);

    /// @notice Emitted when governance changes the threshold for permissioned
    /// full foreclosure.
    ///
    /// @param oldForeclosureLtv Previous foreclosure LTV.
    /// @param newForeclosureLtv New foreclosure LTV.
    event SetForeclosureLtv(uint256 oldForeclosureLtv, uint256 newForeclosureLtv);

    /// @notice Emitted when governance changes the fee charged on new draws.
    ///
    /// @param oldBorrowOpeningFee Previous opening fee.
    /// @param newBorrowOpeningFee New opening fee.
    event SetBorrowOpeningFee(uint256 oldBorrowOpeningFee, uint256 newBorrowOpeningFee);

    /// @notice Emitted when claimable fees are minted to the configured fee
    /// recipient.
    ///
    /// @param recipient    Account that received the newly minted borrow tokens.
    /// @param amount       Amount minted.
    event InterestClaimed(address indexed recipient, uint256 amount);

    /// @notice Returns the sole account that may own the market's collateral
    /// and borrow position.
    ///
    /// @return account Configured credit account.
    function creditAccount() external view returns (address account);

    /// @notice Returns the maximum total debt permitted when making a new draw.
    ///
    /// @return limit Credit limit denominated in borrow-token asset units.
    ///
    /// @dev This is the same synthetic asset value exposed as
    /// `totalSupply().assets`. Accrued interest may move existing debt above
    /// the limit, but further draws will be blocked.
    function creditLimit() external view returns (uint256 limit);

    /// @notice Returns the LTV above which governance may fully foreclose the
    /// credit position.
    ///
    /// @return ltv Foreclosure LTV expressed with 1e18 precision.
    ///
    /// @dev Foreclosure requires debt value to be strictly greater than
    /// collateral value multiplied by this ratio.
    function foreclosureLtv() external view returns (uint256 ltv);

    /// @notice Returns opening fees and accrued interest that may be minted to
    /// the fee recipient.
    ///
    /// @return assets Claimable amount denominated in borrow-token asset units.
    function claimableFeesAssets() external view returns (uint128 assets);

    /// @notice Changes the maximum total debt permitted for new draws.
    ///
    /// @param newCreditLimit New limit denominated in borrow-token asset units.
    ///
    /// @dev Callable only by the owner. Interest is accrued first while the
    /// market is unpaused. The new limit must be nonzero, fit in `uint128`, and
    /// not be below current debt assets.
    function setCreditLimit(uint256 newCreditLimit) external;

    /// @notice Changes the threshold for permissioned full foreclosure.
    ///
    /// @param newForeclosureLtv New foreclosure LTV expressed with 1e18 precision.
    ///
    /// @dev Callable only by the owner. The threshold must be greater than
    /// `maxLtv()` and no greater than 1e18.
    function setForeclosureLtv(uint256 newForeclosureLtv) external;

    /// @notice Changes the fee charged when the credit account draws debt.
    ///
    /// @param newBorrowOpeningFee New opening fee expressed with 1e18 precision.
    ///
    /// @dev Callable only by the owner. The fee may not exceed 1e18. The fee is
    /// added to the borrower's debt and becomes claimable by the protocol; only
    /// the requested draw assets are minted to the receiver.
    function setBorrowOpeningFee(uint256 newBorrowOpeningFee) external;

    /// @notice Mints claimable fees to the configured fee recipient.
    ///
    /// @param interest Amount to claim in borrow-token asset units, or zero to
    /// claim all available fees.
    ///
    /// @return claimed Amount minted to the fee recipient in borrow-token asset
    /// units.
    ///
    /// @dev Callable by either the owner or the fee recipient while the market
    /// is unpaused. Passing zero claims the entire available balance. Tokens
    /// are always minted to `feeRecipient()`, not to the caller.
    function claimInterest(uint256 interest) external returns (uint256 claimed);
}
