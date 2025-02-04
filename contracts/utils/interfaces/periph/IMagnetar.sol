// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Tapioca
import {ICommonExternalContracts, IDepositData} from "../common/ICommonData.sol";
import {IOptionsLockData} from "../tap-token/ITapiocaOptionBroker.sol";
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
    IOptionsLockData participateData;
    ICommonExternalContracts externalContracts;
}

struct LockAndParticipateData {
    address user;
    address tSglToken;
    address magnetar;
    IOptionsLockData lockData;
    IOptionsLockData participateData;
    uint256 value;
}

struct MagnetarCall {
    uint8 id;
    address target;
    uint256 value;
    bytes call;
}

enum MagnetarAction {
    // Simple operations
    Permit, // 0 Permit singular operations. TODO Check if this is needed
    Wrap, // 1 Wrap/unwrap singular operations.
    Market, // 2 Market singular operations.
    TapLock, // 3 TapLock singular operations.
    TapUnlock, // 4 TapLock singular operations.
    OFT, // 5 LZ OFT singular operations.
    ExerciseOption, // 6 tOB singular operation
    // Complex operations
    CollateralModule, // 7 Collateral Singular related operations.
    MintModule, // 8 BigBang Singular related operations.
    OptionModule, // 9 Market Module related operations.
    // External operations
    WethWrap // 11

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
    function lockAndParticipate(LockAndParticipateData memory data) external payable;
    function exitPositionAndRemoveCollateral(ExitPositionAndRemoveCollateralData memory data) external payable;
}

interface IMagnetarMintModule {
    function mintBBAndLock(MintFromBBAndLendOnSGLData memory data) external payable;
}
