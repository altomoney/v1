// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAltoConvexCreditLineMarket} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {SafeTransactionBuilder} from "deployments/ethereum-mainnet/SafeTransactionBuilder.sol";

interface IConvexPoolExit {
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function withdrawAllAndUnwrap(bool claim) external returns (bool);
}

interface ICurveDeposit {
    function coins(uint256 index) external view returns (address);
    function calc_token_amount(uint256[] calldata amounts, bool isDeposit) external view returns (uint256);
    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
        external
        returns (uint256);
}

interface IStakeDaoDeposit {
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256);
}

interface IYearnDeposit {
    function balanceOf(address account) external view returns (uint256);
    function pricePerShare() external view returns (uint256);
    function deposit(uint256 amount, address recipient) external returns (uint256);
}

/// @notice Generates batch 1 before execution and batch 2 after batch 1 is mined.
contract GenerateCreditLineLiquidityBatches is Script {
    address constant SAFE = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address constant LP = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    address constant CONVEX = 0x0E80Fe9D6F6dF530ab2Ff69ad0259e77E2ffEdeb;
    address constant CREDIT = 0x6b3458c87CD38aeFA6A5D059Eb19f609420DD852;
    address constant PSM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    address constant STAKEDAO = 0x6ea128D83bc4223A0d1e6E475CEE85998AcB6337;
    address constant YEARN = 0xB53B70Cb960FeEAf2093Df3C733E368F6D254898;
    uint256 constant BORROW = 500_000 ether;
    uint256 constant SWAP = 250_000 ether;

    function run() external {
        require(block.chainid == 1, "Ethereum mainnet fork required");
        require(IAltoConvexCreditLineMarket(CREDIT).creditAccount() == SAFE, "wrong credit account");
        require(IAltoConvexCreditLineMarket(CREDIT).collateralToken() == LP, "wrong collateral");
        require(ICurveDeposit(LP).coins(0) == FRXUSD && ICurveDeposit(LP).coins(1) == DUSD, "wrong Curve pool");

        uint256 oldConvexLp = IConvexPoolExit(CONVEX).balanceOf(SAFE);
        if (oldConvexLp > 0) {
            require(IERC20(LP).balanceOf(SAFE) == 0, "preexisting loose LP");
            _batchOne(oldConvexLp);
            return;
        }
        require(IERC20(LP).balanceOf(SAFE) > 0, "batch 1 has not minted LP");
        require(IAltoConvexCreditLineMarket(CREDIT).position(SAFE).borrowShares > 0, "batch 1 has not borrowed");
        _batchTwo();
    }

    function _batchOne(uint256 oldConvexLp) internal {
        require(IERC20(DUSD).balanceOf(SAFE) == 0, "preexisting DUSD");
        require(IAltoConvexCreditLineMarket(CREDIT).position(SAFE).collateralAssets == 0, "existing collateral");

        (uint256 assetOut, uint256 dusdCost,,) = IUsm(PSM).getStableTokenAmountForBuyAsset(SWAP);
        require(assetOut == SWAP && dusdCost == SWAP, "PSM quote changed");

        address[] memory targets = new address[](9);
        uint256[] memory values = new uint256[](9);
        bytes[] memory data = new bytes[](9);
        _add(targets, data, 0, CONVEX, abi.encodeCall(IConvexPoolExit.withdrawAllAndUnwrap, (true)));
        require(IConvexPoolExit(CONVEX).balanceOf(SAFE) == 0, "Convex stake remains");
        require(IConvexPoolExit(CONVEX).earned(SAFE) == 0, "Convex rewards remain");
        require(IERC20(LP).balanceOf(SAFE) == oldConvexLp, "Convex LP mismatch");

        _add(targets, data, 1, LP, abi.encodeCall(IERC20.approve, (CREDIT, oldConvexLp)));
        _add(targets, data, 2, CREDIT, abi.encodeCall(IAltoConvexCreditLineMarket.addCollateral, (oldConvexLp, SAFE)));
        _add(targets, data, 3, CREDIT, abi.encodeCall(IMarketBase.borrow, (BORROW, 0, SAFE, SAFE, "")));
        _add(targets, data, 4, DUSD, abi.encodeCall(IERC20.approve, (PSM, SWAP)));
        _add(targets, data, 5, PSM, abi.encodeCall(IUsm.buyAsset, (SWAP, SAFE)));

        uint256 dusd = IERC20(DUSD).balanceOf(SAFE);
        uint256 frxusd = IERC20(FRXUSD).balanceOf(SAFE);
        require(dusd == SWAP && frxusd >= SWAP, "swap balance mismatch");
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = frxusd;
        amounts[1] = dusd;
        uint256 minLp = ICurveDeposit(LP).calc_token_amount(amounts, true) * 9950 / 10_000;
        require(minLp > 0, "zero minimum LP");

        _add(targets, data, 6, FRXUSD, abi.encodeCall(IERC20.approve, (LP, frxusd)));
        _add(targets, data, 7, DUSD, abi.encodeCall(IERC20.approve, (LP, dusd)));
        _add(targets, data, 8, LP, abi.encodeCall(ICurveDeposit.add_liquidity, (amounts, minLp, SAFE)));
        require(IERC20(DUSD).balanceOf(SAFE) == 0 && IERC20(FRXUSD).balanceOf(SAFE) == 0, "token dust");
        require(IERC20(DUSD).allowance(SAFE, PSM) == 0, "PSM allowance remains");
        require(IERC20(DUSD).allowance(SAFE, LP) == 0, "Curve DUSD allowance remains");
        require(IERC20(FRXUSD).allowance(SAFE, LP) == 0, "Curve frxUSD allowance remains");
        require(IERC20(LP).balanceOf(SAFE) >= minLp, "LP mint mismatch");
        SafeTransactionBuilder.writeDirectBatch("credit-line-liquidity-01-create-lp", SAFE, targets, values, data);
    }

    function _batchTwo() internal {
        uint256 newLp = IERC20(LP).balanceOf(SAFE);
        uint256 creditLp = IAltoConvexCreditLineMarket(CREDIT).position(SAFE).collateralAssets;
        uint256 stakeDaoLp = IStakeDaoDeposit(STAKEDAO).convertToAssets(IStakeDaoDeposit(STAKEDAO).balanceOf(SAFE));
        uint256 yearnLp =
            Math.mulDiv(IYearnDeposit(YEARN).balanceOf(SAFE), IYearnDeposit(YEARN).pricePerShare(), 1 ether);
        uint256 totalOldLp = creditLp + stakeDaoLp + yearnLp;
        require(newLp > 0 && creditLp > 0 && stakeDaoLp > 0 && yearnLp > 0, "missing LP position");

        uint256 toCredit = Math.mulDiv(newLp, creditLp, totalOldLp);
        uint256 toStakeDao = Math.mulDiv(newLp, stakeDaoLp, totalOldLp);
        uint256 toYearn = newLp - toCredit - toStakeDao;
        address[] memory targets = new address[](6);
        uint256[] memory values = new uint256[](6);
        bytes[] memory data = new bytes[](6);
        _add(targets, data, 0, LP, abi.encodeCall(IERC20.approve, (CREDIT, toCredit)));
        _add(targets, data, 1, CREDIT, abi.encodeCall(IAltoConvexCreditLineMarket.addCollateral, (toCredit, SAFE)));
        _add(targets, data, 2, LP, abi.encodeCall(IERC20.approve, (STAKEDAO, toStakeDao)));
        _add(targets, data, 3, STAKEDAO, abi.encodeCall(IStakeDaoDeposit.deposit, (toStakeDao, SAFE)));
        _add(targets, data, 4, LP, abi.encodeCall(IERC20.approve, (YEARN, toYearn)));
        _add(targets, data, 5, YEARN, abi.encodeCall(IYearnDeposit.deposit, (toYearn, SAFE)));
        require(IERC20(LP).balanceOf(SAFE) == 0, "LP dust");
        require(IERC20(DUSD).balanceOf(SAFE) == 0 && IERC20(FRXUSD).balanceOf(SAFE) == 0, "token dust");
        require(IERC20(LP).allowance(SAFE, CREDIT) == 0, "credit allowance remains");
        require(IERC20(LP).allowance(SAFE, STAKEDAO) == 0, "Stake DAO allowance remains");
        require(IERC20(LP).allowance(SAFE, YEARN) == 0, "Yearn allowance remains");
        SafeTransactionBuilder.writeDirectBatch("credit-line-liquidity-02-allocate-lp", SAFE, targets, values, data);
        console.log("Mainnet fork block:", block.number);
        console.log("New LP:", newLp);
        console.log("Credit line LP:", toCredit);
        console.log("Stake DAO LP:", toStakeDao);
        console.log("Yearn LP:", toYearn);
    }

    function _add(address[] memory targets, bytes[] memory data, uint256 index, address target, bytes memory callData)
        internal
    {
        targets[index] = target;
        data[index] = callData;
        vm.prank(SAFE);
        (bool ok, bytes memory result) = target.call(callData);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
