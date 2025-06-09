// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    AltoBorrowMarket, LiquidablePosition, LiquidationConfiguration, Balance
} from "@alto/lending/AltoBorrowMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IMarketBase, IMarket, IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {ERC20Mock} from "@alto-test/helpers/ERC20Mock.sol";
import {PAUSED_MARKET} from "@alto/utils/Constants.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {stdError} from "forge-std/StdError.sol";
import {Vm} from "forge-std/Vm.sol";
import {IRemoveCollateralCallback} from "@alto/lending/interfaces/IMarketCallbacks.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";

contract MockMarket is AltoBorrowMarket {
    using AssetShareConversionMath for uint256;

    constructor(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    )
        AltoBorrowMarket(
            _borrowToken,
            _collateralToken,
            _irm,
            _owner,
            _oracle,
            _maxLtv,
            _borrowOpeningFee,
            _feeRecipient,
            _liquidationConfiguration
        )
    {}

    function addInterest(uint256 amount) external {
        totalSupply.assets += uint128(amount);
        totalBorrowed.assets += uint128(amount);
    }
}

contract RemoveCollateralTest is Test {
    using AssetShareConversionMath for uint256;

    MockMarket market;
    ERC20Mock borrowToken;
    ERC20Mock collateralToken;
    OracleMock oracle;
    FixedRateIrm irm;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address receiver = address(0xC0C);
    uint256 constant INITIAL_AMOUNT = 1000 ether;

    function createMarket(
        LiquidationConfiguration memory liquidationConfiguration,
        uint256 collateralPrice,
        uint256 maxLtv
    ) public {
        borrowToken = new ERC20Mock("Borrow Token", "BTKN");
        collateralToken = new ERC20Mock("Collateral Token", "CTKN");

        address newIrm = address(new FixedRateIrm(0.04 ether / uint256(365 days), address(this)));
        address newOracle = address(new OracleMock());
        OracleMock(newOracle).setPrice(collateralPrice);

        market = new MockMarket(
            address(borrowToken),
            address(collateralToken),
            newIrm,
            address(this),
            newOracle,
            maxLtv,
            0,
            address(this),
            liquidationConfiguration
        );

        // Setup initial balances for test accounts
        deal(address(borrowToken), alice, INITIAL_AMOUNT);
        deal(address(borrowToken), bob, INITIAL_AMOUNT);
        deal(address(borrowToken), receiver, INITIAL_AMOUNT);

        deal(address(collateralToken), alice, INITIAL_AMOUNT);
        deal(address(collateralToken), bob, INITIAL_AMOUNT);
        deal(address(collateralToken), receiver, INITIAL_AMOUNT);

        // Approve market to spend tokens
        vm.startPrank(alice);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        market.addSupply(100 ether, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(receiver);
        borrowToken.approve(address(market), type(uint256).max);
        collateralToken.approve(address(market), type(uint256).max);
        vm.stopPrank();
    }

    function setUp() public {
        createMarket(
            LiquidationConfiguration({
                maxLiquidationLtv: 0.8 ether,
                dynamicBonusFeeStart: 0.01 ether,
                ltvForCompleteLiquidation: 0.9 ether,
                dynamicBonusFeeDecaySteepness: 5 ether,
                liquidationBaseFee: 0.05 ether,
                minPenaltyPercentage: 0.05 ether,
                priorityLiquidationGracePeriod: 5 minutes,
                taggerLiquidationGracePeriod: 2 minutes,
                liquidationWindowTag: 3 days
            }),
            ORACLE_PRICE_PRECISION,
            0.75 ether
        );
    }

    function test_RevertWhen_MarketIsPaused() public {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.stopPrank();

        // Set owner as pauser for PAUSED_MARKET
        market.setPauser(market.owner(), PAUSED_MARKET, true);
        vm.startPrank(market.owner());
        market.pause(PAUSED_MARKET, true);
        vm.stopPrank();

        vm.startPrank(bob);
        bytes memory expectedRevert = abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSED_MARKET);
        vm.expectRevert(expectedRevert);
        market.removeCollateral(0.5 ether, bob, receiver, "");
        vm.stopPrank();
    }

    function test_RevertWhen_AssetsIsZero() public {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeCollateral(0, bob, receiver, "");
        vm.stopPrank();
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() public {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInvalidInput.selector);
        market.removeCollateral(0.5 ether, address(0), receiver, "");
        vm.stopPrank();
    }

    modifier givenAssetsIsGreaterThanZero() {
        _;
    }

    modifier givenOnBehalfIsValidAddress() {
        _;
    }

    function test_RevertWhen_SenderIsNotAuthorizedForOnBehalf()
        public
        givenAssetsIsGreaterThanZero
        givenOnBehalfIsValidAddress
    {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.removeCollateral(0.5 ether, bob, receiver, "");
        vm.stopPrank();
    }

    modifier whenSenderIsAuthorizedForOnBehalf() {
        _;
    }

    function test_RevertWhen_UserHasInsufficientCollateral()
        public
        givenAssetsIsGreaterThanZero
        givenOnBehalfIsValidAddress
        whenSenderIsAuthorizedForOnBehalf
    {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.expectRevert(stdError.arithmeticError);
        market.removeCollateral(2 ether, bob, receiver, "");
        vm.stopPrank();
    }

    modifier whenUserHasSufficientCollateral() {
        _;
    }

    function test_RevertWhen_RemovingCollateralMakesPositionInsolvent()
        public
        givenAssetsIsGreaterThanZero
        givenOnBehalfIsValidAddress
        whenSenderIsAuthorizedForOnBehalf
        whenUserHasSufficientCollateral
    {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        market.borrow(0.5 ether, 0, bob, bob, "");
        vm.expectRevert(IMarketErrors.AltoBorrowMarketInsufficientUserCollateral.selector);
        market.removeCollateral(0.6 ether, bob, receiver, "");
        vm.stopPrank();
    }

    function test_RemoveCollateralWhen_ReceiverIsAuthorizedCallback_WithData() public {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.stopPrank();

        // Mock the callback contract
        MockCallback callback = new MockCallback();
        // Authorize the callback contract
        vm.prank(market.owner());
        market.setAuthorizedCallback(address(callback), true);

        vm.startPrank(bob);
        uint256 startBal = collateralToken.balanceOf(address(callback));
        vm.recordLogs();
        market.removeCollateral(0.5 ether, bob, address(callback), "data");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool found;
        bytes32 expectedSig = keccak256("RemoveCollateral(address,address,address,uint256)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0] == expectedSig && address(uint160(uint256(entries[i].topics[1]))) == bob
                    && address(uint160(uint256(entries[i].topics[2]))) == bob
                    && address(uint160(uint256(entries[i].topics[3]))) == address(callback)
            ) {
                found = true;
                break;
            }
        }
        assertTrue(found, "RemoveCollateral event not found");
        vm.stopPrank();

        assertEq(collateralToken.balanceOf(address(callback)) - startBal, 0.5 ether);
    }

    function test_RemoveCollateralWhen_ReceiverIsAuthorizedCallback_WithoutData() public {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.stopPrank();

        // Mock the callback contract
        MockCallback callback = new MockCallback();
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.RemoveCollateral(bob, bob, address(callback), 0.5 ether);
        market.removeCollateral(0.5 ether, bob, address(callback), "");
        vm.stopPrank();

        assertEq(collateralToken.balanceOf(address(callback)), 0.5 ether);
    }

    function test_RevertWhen_ReceiverIsNotAuthorizedCallback_WithData() public {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(IMarketErrors.AltoBorrowMarketUnauthorized.selector);
        market.removeCollateral(0.5 ether, bob, receiver, "data");
        vm.stopPrank();
    }

    function test_RemoveCollateralWhen_ReceiverIsNotAuthorizedCallback_WithoutData() public {
        vm.startPrank(bob);
        market.addCollateral(1 ether, bob);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 startBal = collateralToken.balanceOf(receiver);
        vm.expectEmit(true, true, true, true);
        emit IMarketEvents.RemoveCollateral(bob, bob, receiver, 0.5 ether);
        market.removeCollateral(0.5 ether, bob, receiver, "");
        vm.stopPrank();

        // Assert delta, not absolute value
        assertEq(collateralToken.balanceOf(receiver) - startBal, 0.5 ether);
    }
}

contract MockCallback is IRemoveCollateralCallback {
    function onRemoveCollateralCallback(uint256 amount, bytes calldata data) external {}
}

contract MockRemoveCollateralCallback is IRemoveCollateralCallback {
    uint256 public lastAmount;
    bytes public lastData;

    function onRemoveCollateralCallback(uint256 amount, bytes calldata data) external {
        lastAmount = amount;
        lastData = data;
    }
}
