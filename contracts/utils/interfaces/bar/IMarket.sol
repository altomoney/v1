// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";

/// @dev modules are contracts that holds a portion of the market's logic
enum Module {
    Base,
    Borrow,
    Collateral,
    Liquidation,
    Leverage
}

enum PauseType {
    Borrow,
    Repay,
    AddCollateral,
    RemoveCollateral,
    Liquidation,
    LeverageBuy,
    LeverageSell,
    AddAsset,
    RemoveAsset
}

interface IMarket {
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function _asset() external view returns (address);

    function _collateralizationRate() external view returns (uint256);

    function _exchangeRate() external view returns (uint256);

    function _exchangeRatePrecision() external view returns (uint256);

    function _leverageExecutor() external view returns (address);

    function _liquidationBonusAmount() external view returns (uint256);

    function _liquidationCollateralizationRate() external view returns (uint256);

    function _liquidationMultiplier() external view returns (uint256);

    function _maxLiquidationSlippage() external view returns (uint256);

    function _maxLiquidatorReward() external view returns (uint256);

    function _minBorrowAmount() external view returns (uint256);

    function _minCollateralAmount() external view returns (uint256);

    function _minLiquidatorReward() external view returns (uint256);

    function _oracle() external view returns (address);

    function _oracleData() external view returns (bytes memory);

    function _pauseOptions(uint8 _pauseProp) external view returns (bool);

    function _protocolFee() external view returns (uint256);

    function _rateTimestamp() external view returns (uint256);

    function _rateValidDuration() external view returns (uint256);

    function _totalBorrow() external view returns (Rebase memory);

    function _totalBorrowCap() external view returns (uint256);

    function _totalCollateralShare() external view returns (uint256);

    function _userBorrowPart(address _user) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256 result);

    function allowanceBorrow(address, address) external view returns (uint256);

    function allowanceCollateral(address, address) external view returns (uint256);

    function allowanceLiquidity(address, address) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function approveBorrow(address spender, uint256 amount) external returns (bool);

    function approveCollateral(address spender, uint256 amount) external returns (bool);

    function approveLiquidity(address spender, uint256 amount) external returns (bool);

    function asset() external view returns (address);

    function balanceOf(address owner) external view returns (uint256 result);

    function borrowableToken() external view returns (address);

    function collateral() external view returns (address);

    function computeLiquidatorReward(address user, uint256 _exchangeRate) external view returns (uint256);

    function computeTVLInfo(address user, uint256 _exchangeRate)
        external
        view
        returns (uint256 amountToSolvency, uint256 minTVL, uint256 maxTVL);

    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    function convertToShares(uint256 assets) external view returns (uint256 shares);

    function decimals() external view returns (uint8);

    function deposit(uint256 assets, address to) external returns (uint256 shares);

    function execute(Module[] memory modules, bytes[] memory calls, bool revertOnFail)
        external
        returns (bool[] memory successes, bytes[] memory results);

    function maxDeposit(address to) external view returns (uint256 maxAssets);

    function maxMint(address to) external view returns (uint256 maxShares);

    function maxRedeem(address owner) external view returns (uint256 maxShares);

    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

    function mint(uint256 shares, address to) external returns (uint256 assets);

    function name() external view returns (string memory);

    function nonces(address owner) external view returns (uint256);

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory)
        external
        pure
        returns (bytes4);

    function onERC1155Received(address, address, uint256, uint256, bytes memory) external pure returns (bytes4);

    function owner() external view returns (address);

    function penrose() external view returns (address);

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;

    function permitAction(
        uint8 action,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function accrue() external;

    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    function previewMint(uint256 shares) external view returns (uint256 assets);

    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    function redeem(uint256 shares, address to, address owner) external returns (uint256 assets);

    function renounceOwnership() external;

    function setLeverageExecutor(address _executor) external;

    function setLiquidationMaxSlippage(uint256 _val) external;

    function setMarketConfig(
        address _oracle,
        bytes memory _oracleData,
        uint256 _protocolFee,
        uint256 _liquidationBonusAmount,
        uint256 _minLiquidatorReward,
        uint256 _maxLiquidatorReward,
        uint256 _totalBorrowCap,
        uint256 _collateralizationRate,
        uint256 _liquidationCollateralizationRate,
        uint256 _minBorrowAmount,
        uint256 _minCollateralAmount
    ) external;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);

    function symbol() external view returns (string memory);

    function totalAssets() external view returns (uint256 assets);

    function totalSupply() external view returns (uint256 result);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function transferOwnership(address newOwner) external;

    function updateExchangeRate() external returns (bool updated, uint256 rate);

    function withdraw(uint256 assets, address to, address owner) external returns (uint256 shares);

    function updatePause(PauseType _type, bool val) external;

    function updatePauseAll(bool val) external;

    function rescueEth(uint256 amount, address to) external;

    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event ApprovalBorrow(address indexed owner, address indexed spender, uint256 indexed value);
    event ApprovalCollateral(address indexed owner, address indexed spender, uint256 indexed value);
    event ApprovalLiquidity(address indexed owner, address indexed spender, uint256 indexed value);
    event ConservatorUpdated(address old, address _new);
    event Deposit(address indexed by, address indexed owner, uint256 assets, uint256 shares);
    event ExchangeRateDurationUpdated(uint256 _oldVal, uint256 _newVal);
    event LeverageExecutorSet(address oldVal, address newVal);
    event Liquidated(
        address indexed liquidator,
        address[] users,
        uint256 liquidatorReward,
        uint256 protocolReward,
        uint256 repayedAmount,
        uint256 collateralShareRemoved
    );
    event LiquidationMaxSlippageUpdated(uint256 oldVal, uint256 newVal);
    event LiquidationMultiplierUpdated(uint256 oldVal, uint256 newVal);
    event LogBorrowCapUpdated(uint256 _oldVal, uint256 _newVal);
    event LogExchangeRate(uint256 rate);
    event OracleDataUpdated();
    event OracleUpdated(address newAddr);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PausedUpdated(uint8 indexed _type, bool oldState, bool newState);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event ValueUpdated(uint256 valType, uint256 _newVal);
    event Withdraw(address indexed by, address indexed to, address indexed owner, uint256 assets, uint256 shares);

    error AllowanceNotValid();
    error AllowanceOverflow();
    error AllowanceUnderflow();
    error DepositMoreThanMax();
    error ExchangeRateNotValid();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidPermit();
    error MarketERC4626__AlreadyInitialized();
    error MinBorrowAmountNotMet();
    error MinCollateralAmountNotMet();
    error MintMoreThanMax();
    error NotValid();
    error Permit2AllowanceIsFixedAtInfinity();
    error PermitExpired();
    error RedeemMoreThanMax();
    error TotalSupplyOverflow();
    error WithdrawMoreThanMax();
}
