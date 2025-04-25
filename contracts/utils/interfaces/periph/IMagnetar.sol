// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Tapioca
import {ICommonExternalContracts, IDepositData} from "../common/ICommonData.sol";
import {LZSendParam} from "../periph/ITapiocaOmnichainEngine.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/
/// ============================
/// ========= GENERIC ==========
/// ============================
struct UsdoInitStruct {
    address endpoint;
    address delegate;
    address cluster;
    address extExec;
}

struct UsdoModulesInitStruct {
    //modules
    address usdoSenderModule;
    address usdoReceiverModule;
    address marketReceiverModule;
    address optionReceiverModule;
}

/// ============================
/// ========= COMPOSE ==========
/// ============================
/**
 * @notice Encodes the message for the PT_YB_SEND_SGL_LEND_OR_REPAY operation.
 */
struct MarketLendOrRepayMsg {
    address user;
    ILendOrRepayParams lendParams;
    MagnetarWithdrawData withdrawParams;
    uint256 value;
}

/**
 * @notice Encodes the message for the PT_MARKET_REMOVE_ASSET operation.
 */
struct MarketRemoveAssetMsg {
    address user;
    ICommonExternalContracts externalData;
    IRemoveAndRepay removeAndRepayData;
    uint256 value;
}

/**
 * @notice Encodes the message for the PT_TAP_EXERCISE operation.
 */
struct ExerciseOptionsMsg {
    IExerciseOptionsData optionsData;
    bool withdrawOnOtherChain;
    //@dev send back to source message params
    LZSendParam lzSendParams;
}

struct IRemoveAndRepay {
    bool removeAssetFromSGL;
    uint256 removeAmount; //slightly greater than repayAmount to cover the interest
    bool repayAssetOnBB;
    uint256 repayAmount; // on BB
    bool removeCollateralFromBB;
    uint256 collateralAmount; // from BB
    IOptionsUnlockData unlockData;
    MagnetarWithdrawData assetWithdrawData;
    MagnetarWithdrawData collateralWithdrawData;
}

// lend or repay
struct ILendOrRepayParams {
    bool repay;
    uint256 depositAmount;
    uint256 repayAmount;
    address marketHelper;
    address magnetar;
    address market;
    bool removeCollateral;
    uint256 removeCollateralAmount;
    IOptionsLockData lockData;
}

struct IMintData {
    bool mint;
    uint256 mintAmount;
    IDepositData collateralDepositData;
}

struct IExerciseOptionsData {
    address from;
    address target;
    address paymentToken;
    uint256 paymentTokenAmount;
    uint256 tapAmount;
    uint8 bucketId;
}

struct IOptionsUnlockData {
    bool unlock;
    address target;
    uint8 bucketId;
    address to;
    uint256 amount;
}

struct IOptionsLockData {
    bool lock;
    uint8 bucketId;
    address target;
    address to;
    address sglMarket;
    uint256 usdoAmount;
}

struct MagnetarWithdrawData {
    address asset;
    address receiver;
    uint256 amount;
    bool unwrap;
    bool withdraw;
    bool extractFromSender;
}

/**
 * @dev `exitPositionAndRemoveCollateral` calldata
 */
struct ExitPositionAndRemoveCollateralData {
    address user;
    ICommonExternalContracts externalData;
    IRemoveAndRepay removeAndRepayData;
}

/**
 * @dev `depositRepayAndRemoveCollateralFromMarket` calldata
 */
struct DepositRepayAndRemoveCollateralFromMarketData {
    address market;
    address marketHelper;
    address user;
    uint256 depositAmount;
    uint256 repayAmount;
    uint256 collateralAmount;
    MagnetarWithdrawData withdrawCollateralParams;
}

/**
 * @dev `depositAddCollateralAndBorrowFromMarket` calldata
 */
struct DepositAddCollateralAndBorrowFromMarketData {
    address market;
    address marketHelper;
    address user;
    uint256 collateralAmount;
    uint256 borrowAmount;
    bool deposit;
    MagnetarWithdrawData withdrawParams;
}

struct BuyCollateralData {
    address market;
    address marketHelper;
    address user;
    uint256 collateralAmount;
    uint256 borrowAmount;
    bytes data;
}

struct SellCollateralData {
    address market;
    address marketHelper;
    address user;
    uint256 collateralShares;
    bytes data;
}

/**
 * @dev `MintFromBBAndLendOnSGLData` calldata
 */
struct MintFromBBAndLendOnSGLData {
    address user;
    uint256 lendAmount;
    IMintData mintData;
    IDepositData depositData;
    IOptionsLockData lockData;
    ICommonExternalContracts externalContracts;
}

struct LockData {
    address user;
    address magnetar;
    IOptionsLockData lockData;
}

struct MagnetarCall {
    uint8 id;
    address target;
    uint256 value;
    bytes call;
}

enum MagnetarAction {
    // Simple operations
    Permit, // 0 Permit singular operations.
    Wrap, // 1 Wrap/unwrap singular operations.
    Market, // 2 Market singular operations.
    TapLock, // 3 TapLock singular operations.
    TapUnlock, // 4 TapLock singular operations.
    TapBatchClaimRewards, // 5 TapBatchClaimRewards singular operations.
    TapExtendLock, // 6 TapExtendLock singular operations.
    OFT, // 7 LZ OFT singular operations.
    ExerciseOption, // 8 tOB singular operation
    // Complex operations
    CollateralModule, // 9 Collateral Singular related operations.
    MintModule, // 10 BigBang Singular related operations.
    OptionModule, // 11 Market Module related operations.
    LeverageModule, // 12 Leverage Singular related operations.
    // External operations
    WethWrap // 13

}

enum MagnetarModule {
    CollateralModule,
    MintModule,
    OptionModule,
    LeverageModule
}

interface IMagnetar {
    function burst(MagnetarCall[] calldata calls) external payable;
    function cluster() external view returns (address);
    function helper() external view returns (address);
}

interface IMagnetarModuleExtender {
    function isValidActionId(uint8 actionId) external view returns (bool);
    function handleAction(MagnetarCall calldata call) external payable;
}

interface IMagnetarCollateralModule {
    function depositAddCollateralAndBorrowFromMarket(DepositAddCollateralAndBorrowFromMarketData memory data)
        external
        payable;
    function depositRepayAndRemoveCollateralFromMarket(DepositRepayAndRemoveCollateralFromMarketData memory data)
        external
        payable;
}

interface IMagnetarOptionModule {
    function lockAndParticipate(LockData memory data) external payable;
    function exitPositionAndRemoveCollateral(ExitPositionAndRemoveCollateralData memory data) external payable;
}

interface IMagnetarMintModule {
    function mintBBAndLock(MintFromBBAndLendOnSGLData memory data) external payable;
}
