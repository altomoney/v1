// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAltoConvexCreditLineMarket} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IUsm} from "@alto/usm/interfaces/IUsm.sol";
import {SafeTransactionBuilder} from "deployments/ethereum-mainnet/SafeTransactionBuilder.sol";

interface ISecondDrawCurvePool {
    function coins(uint256 index) external view returns (address);
    function calc_token_amount(uint256[] calldata amounts, bool isDeposit) external view returns (uint256);
    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
        external
        returns (uint256);
}

/// @notice Run once to create the draw batch, then again after it executes to deposit the exact minted LP balance.
contract GenerateCreditLineSecondDrawBatches is Script {
    address private constant SAFE = 0xA1148A1b94262540994Cf9Aa431A13ad39764228;
    address private constant CREDIT = 0x6b3458c87CD38aeFA6A5D059Eb19f609420DD852;
    address private constant PSM = 0x1BD08B43D1579881cfAd0A35AEEa5b547dBE4c91;
    address private constant LP = 0x104d6a1b97A6CEf88D905d7b865A378d90be932A;
    address private constant DUSD = 0x63d74d22E689C715a04F2C13962b1f77F443d35b;
    address private constant FRXUSD = 0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29;
    uint256 private constant BORROW = 499_000 ether;
    uint256 private constant SWAP = BORROW / 2;

    function run() external {
        require(block.chainid == 1, "Ethereum mainnet fork required");
        IAltoConvexCreditLineMarket market = IAltoConvexCreditLineMarket(CREDIT);
        require(market.creditAccount() == SAFE, "credit account changed");
        require(market.borrowToken() == DUSD && market.collateralToken() == LP, "market tokens changed");
        require(ISecondDrawCurvePool(LP).coins(0) == FRXUSD, "Curve coin 0 changed");
        require(ISecondDrawCurvePool(LP).coins(1) == DUSD, "Curve coin 1 changed");

        uint256 looseLp = IERC20(LP).balanceOf(SAFE);
        if (looseLp == 0) {
            _drawAndMint(market);
        } else {
            _depositCollateral(market, looseLp);
        }
    }

    function _drawAndMint(IAltoConvexCreditLineMarket market) private {
        require(IERC20(DUSD).balanceOf(SAFE) == 0, "preexisting DUSD");
        require(IERC20(FRXUSD).balanceOf(SAFE) == 0, "preexisting frxUSD");
        uint128 limit = market.totalSupply().assets;
        uint128 debt = market.totalBorrowed().assets;
        require(limit == 1_000_000 ether && debt >= 500_000 ether && debt < 501_000 ether, "unexpected debt");
        (uint256 interest,) = IIrm(market.irm()).updateInterestRateView(limit, debt);
        require(uint256(debt) + interest + BORROW <= limit, "499k draw no longer fits credit limit");

        (uint256 frxOut, uint256 dusdCost,,) = IUsm(PSM).getStableTokenAmountForBuyAsset(SWAP);
        require(frxOut == SWAP && dusdCost == SWAP, "PSM quote changed");

        address[] memory targets = new address[](6);
        uint256[] memory values = new uint256[](6);
        bytes[] memory data = new bytes[](6);
        _add(targets, data, 0, CREDIT, abi.encodeCall(IMarketBase.borrow, (BORROW, 0, SAFE, SAFE, "")));
        _add(targets, data, 1, DUSD, abi.encodeCall(IERC20.approve, (PSM, SWAP)));
        _add(targets, data, 2, PSM, abi.encodeCall(IUsm.buyAsset, (SWAP, SAFE)));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = IERC20(FRXUSD).balanceOf(SAFE);
        amounts[1] = IERC20(DUSD).balanceOf(SAFE);
        require(amounts[0] == SWAP && amounts[1] == SWAP, "swap balances changed");
        uint256 minLp = ISecondDrawCurvePool(LP).calc_token_amount(amounts, true) * 9950 / 10_000;
        require(minLp > 0, "zero minimum LP");
        _add(targets, data, 3, FRXUSD, abi.encodeCall(IERC20.approve, (LP, SWAP)));
        _add(targets, data, 4, DUSD, abi.encodeCall(IERC20.approve, (LP, SWAP)));
        _add(targets, data, 5, LP, abi.encodeCall(ISecondDrawCurvePool.add_liquidity, (amounts, minLp, SAFE)));

        require(IERC20(DUSD).balanceOf(SAFE) == 0 && IERC20(FRXUSD).balanceOf(SAFE) == 0, "token dust");
        require(IERC20(DUSD).allowance(SAFE, PSM) == 0, "PSM allowance remains");
        require(IERC20(DUSD).allowance(SAFE, LP) == 0, "Curve DUSD allowance remains");
        require(IERC20(FRXUSD).allowance(SAFE, LP) == 0, "Curve frxUSD allowance remains");
        require(IERC20(LP).balanceOf(SAFE) >= minLp, "LP mint mismatch");
        SafeTransactionBuilder.writeDirectBatch("credit-line-second-draw-01-create-lp", SAFE, targets, values, data);
        console.log("Fork block:", block.number);
        console.log("Debt including pending interest:", uint256(debt) + interest);
        console.log("Minimum minted LP:", minLp);
    }

    function _depositCollateral(IAltoConvexCreditLineMarket market, uint256 looseLp) private {
        uint128 debt = market.totalBorrowed().assets;
        require(debt >= 999_000 ether, "second draw has not executed");
        require(IERC20(DUSD).balanceOf(SAFE) == 0 && IERC20(FRXUSD).balanceOf(SAFE) == 0, "token dust");

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);
        _add(targets, data, 0, LP, abi.encodeCall(IERC20.approve, (CREDIT, looseLp)));
        _add(targets, data, 1, CREDIT, abi.encodeCall(IAltoConvexCreditLineMarket.addCollateral, (looseLp, SAFE)));
        require(IERC20(LP).balanceOf(SAFE) == 0, "LP dust");
        require(IERC20(LP).allowance(SAFE, CREDIT) == 0, "credit allowance remains");
        SafeTransactionBuilder.writeDirectBatch("credit-line-second-draw-02-collateral", SAFE, targets, values, data);
        console.log("LP deposited to credit line:", looseLp);
    }

    function _add(address[] memory targets, bytes[] memory data, uint256 index, address target, bytes memory callData)
        private
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
