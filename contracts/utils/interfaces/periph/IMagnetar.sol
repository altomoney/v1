// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Tapioca
import {ICommonExternalContracts, IDepositData} from "../common/ICommonData.sol";
import {LZSendParam} from "../periph/ITapiocaOmnichainEngine.sol";
import {IRemoveAndRepay, IMintData} from "../oft/IUsdo.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

struct IExerciseOptionsData {
    address from;
    address target;
    address paymentToken;
    uint256 paymentTokenAmount;
    uint8 bucketId;
    uint256 tapAmount;
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
    // External operations
    WethWrap // 12
}

enum MagnetarModule {
    CollateralModule,
    MintModule,
    OptionModule
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
