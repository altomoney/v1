// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {ERC20Mock} from "../../../helpers/ERC20Mock.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";

contract MintableERC20Mock is ERC20, IMintableERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public override {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public override {
        _burn(from, amount);
    }
}

abstract contract AltoMintMarketTest is Test {
    AltoMintMarket internal market;
    MintableERC20Mock internal borrowToken;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    FixedRateIrm internal irm;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");
    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");

    uint256 internal constant INITIAL_BALANCE = 10000 ether;
    uint256 internal constant DEBT_CEILING = 1000000 ether;
    uint256 internal constant MAX_LTV = 0.75 ether;
    uint256 internal constant BORROW_OPENING_FEE = 100000000000000000; // 1%

    function setUp() public virtual {
        borrowToken = new MintableERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        oracle = new OracleMock();
        irm = new FixedRateIrm(0.04 ether / uint256(365 days), owner);

        // Set oracle price to proper precision
        oracle.setPrice(ORACLE_PRICE_PRECISION);

        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.01 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.05 ether,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });

        market = new AltoMintMarket(
            address(borrowToken),
            address(collateralToken),
            address(irm),
            owner,
            address(oracle),
            MAX_LTV,
            DEBT_CEILING,
            feeRecipient,
            BORROW_OPENING_FEE,
            config
        );

        // Mint tokens to test accounts
        deal(address(collateralToken), alice, INITIAL_BALANCE);
        deal(address(collateralToken), bob, INITIAL_BALANCE);
        deal(address(collateralToken), charlie, INITIAL_BALANCE);

        deal(address(borrowToken), alice, INITIAL_BALANCE);
        deal(address(borrowToken), bob, INITIAL_BALANCE);
        deal(address(borrowToken), charlie, INITIAL_BALANCE);

        // Approve market to spend tokens
        vm.startPrank(alice);
        collateralToken.approve(address(market), type(uint256).max);
        borrowToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        collateralToken.approve(address(market), type(uint256).max);
        borrowToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        collateralToken.approve(address(market), type(uint256).max);
        borrowToken.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }
}
