// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "../../../helpers/ERC20Mock.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {MockIrm} from "../../../mocks/MockIrm.sol";

import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {IMarketErrors} from "@alto/lending/interfaces/IMarket.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";

contract MintableERC20Mock is ERC20Mock, IMintableERC20 {
    constructor(string memory name, string memory symbol) ERC20Mock(name, symbol) {}

    function mint(address to, uint256 amount) public override(ERC20Mock, IMintableERC20) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public override(ERC20Mock, IMintableERC20) {
        _burn(from, amount);
    }
}

abstract contract AltoMintMarketTest is Test {
    AltoMintMarket internal market;
    MintableERC20Mock internal borrowToken;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    MockIrm internal irm;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");
    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");

    uint256 internal constant INITIAL_BALANCE = 1000 ether;
    uint256 internal constant DEBT_CEILING = 1000000 ether;
    uint256 internal constant MAX_LTV = 0.75 ether;
    uint256 internal constant BORROW_OPENING_FEE = 0.01 ether;

    function setUp() public virtual {
        borrowToken = new MintableERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");
        oracle = new OracleMock();
        irm = new MockIrm();

        // Set oracle price to 1:1
        oracle.setPrice(1 ether);

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
        collateralToken.mint(alice, INITIAL_BALANCE);
        collateralToken.mint(bob, INITIAL_BALANCE);
        collateralToken.mint(charlie, INITIAL_BALANCE);

        borrowToken.mint(alice, INITIAL_BALANCE);
        borrowToken.mint(bob, INITIAL_BALANCE);
        borrowToken.mint(charlie, INITIAL_BALANCE);

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
