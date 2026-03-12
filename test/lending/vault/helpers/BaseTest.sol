// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConstantsLib} from "@alto/lending/libraries/ConstantsLib.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {BaseMarketInitParams, BorrowMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";

import {IrmMock} from "@alto-test/helpers/IrmMock.sol";
import {ERC20MockMintable} from "@alto-test/helpers/ERC20MockMintable.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IAltoVault, MarketAllocation} from "@alto/lending/interfaces/IAltoVault.sol";
import {AltoVault} from "@alto/lending/vault/AltoVault.sol";
import {PendingUint192, PendingAddress, MarketConfig} from "@metamorpho/libraries/PendingLib.sol";
import {AltoBalancesLib} from "@alto/lending/libraries/AltoBalancesLib.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAltoVaultEvents, IAltoVaultErrors} from "@alto/lending/interfaces/IAltoVault.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IMarket} from "@alto/lending/interfaces/IMarket.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {MarketLib} from "@alto/lending/libraries/MarketLib.sol";
import {UtilsLib} from "@bundler3/lib/morpho-blue/src/libraries/UtilsLib.sol";

import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";

import {Test} from "forge-std/Test.sol";

uint256 constant BLOCK_TIME = 1;
uint256 constant MIN_TEST_ASSETS = 1e8;
uint256 constant MAX_TEST_ASSETS = 1e28;
uint184 constant CAP = type(uint128).max;
uint256 constant NB_MARKETS = ConstantsLib.MAX_QUEUE_LENGTH + 1;

contract BaseTest is Test {
    address internal OWNER = makeAddr("Owner");
    address internal SUPPLIER = makeAddr("Supplier");
    address internal BORROWER = makeAddr("Borrower");
    address internal REPAYER = makeAddr("Repayer");
    address internal ONBEHALF = makeAddr("OnBehalf");
    address internal RECEIVER = makeAddr("Receiver");
    address internal ALLOCATOR = makeAddr("Allocator");
    address internal CURATOR = makeAddr("Curator");
    address internal GUARDIAN = makeAddr("Guardian");
    address internal FEE_RECIPIENT = makeAddr("FeeRecipient");
    address internal SKIM_RECIPIENT = makeAddr("SkimRecipient");
    address internal MARKET_OWNER = makeAddr("MarketOwner");
    address internal MARKET_FEE_RECIPIENT = makeAddr("MarketFeeRecipient");

    ERC20MockMintable internal loanToken = new ERC20MockMintable("loan", "B");
    ERC20MockMintable internal collateralToken = new ERC20MockMintable("collateral", "C");
    OracleMock internal oracle = new OracleMock();
    OracleMock internal idleMarketOracle = new OracleMock();
    IrmMock internal irmIdleMarket;
    IrmMock[] internal irmMarkets;

    MarketRegistry internal marketRegistry;
    address[] internal allMarkets;
    uint256[] internal allMarketsLltvs;
    address internal idleMarket;

    function setUp() public virtual {
        vm.label(address(loanToken), "Loan");
        vm.label(address(collateralToken), "Collateral");
        vm.label(address(oracle), "Oracle");

        marketRegistry = new MarketRegistry(MARKET_OWNER);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        idleMarketOracle.setPrice(0);

        irmIdleMarket = new IrmMock();
        irmIdleMarket.setBorrowRate(0.5 ether / uint256(365 days)); // 50% per annum
        idleMarket = _deployMarket(
            address(collateralToken), address(loanToken), 0, address(idleMarketOracle), address(irmIdleMarket)
        );

        for (uint256 i; i < NB_MARKETS; ++i) {
            uint256 lltv = 0.8 ether / (i + 1);
            allMarketsLltvs.push(lltv);
            address market = _deployMarket(address(collateralToken), address(loanToken), lltv, address(0), address(0));
            irmMarkets.push(IrmMock(IMarket(market).irm()));
            allMarkets.push(market);
        }

        allMarkets.push(idleMarket); // Must be pushed last.

        _registerMarketsInRegistry();

        vm.startPrank(SUPPLIER);
        for (uint256 i = 0; i < allMarkets.length; ++i) {
            loanToken.approve(allMarkets[i], type(uint256).max);
            collateralToken.approve(allMarkets[i], type(uint256).max);
        }
        vm.stopPrank();

        vm.startPrank(BORROWER);
        for (uint256 i = 0; i < allMarkets.length; ++i) {
            collateralToken.approve(allMarkets[i], type(uint256).max);
        }
        vm.stopPrank();

        vm.startPrank(REPAYER);
        for (uint256 i = 0; i < allMarkets.length; ++i) {
            loanToken.approve(allMarkets[i], type(uint256).max);
        }
        vm.stopPrank();
    }

    /// @dev Deploys a borrow market with the given collateral token, loan token, LLTV, and optional oracle/IRM overrides.
    /// @param collateralToken_ Collateral token address.
    /// @param loanToken_ Loan (borrow) token address.
    /// @param lltv Max LTV (and liquidation config base).
    /// @param oracle_ Oracle address; pass address(0) to use the default contract oracle.
    /// @param irm_ IRM address; pass address(0) to create a new IrmMock (50% p.a.) and wire it to the market.
    /// @return market The address of the deployed borrow market.
    function _deployMarket(address collateralToken_, address loanToken_, uint256 lltv, address oracle_, address irm_)
        internal
        returns (address market)
    {
        LiquidationConfiguration memory liquidationConfig = LiquidationConfiguration({
            maxLiquidationLtv: lltv,
            dynamicBonusFeeStart: 0.01 ether, // 1%
            ltvForCompleteLiquidation: lltv, // 88%
            dynamicBonusFeeDecaySteepness: 5 ether, // 5
            liquidationBaseFee: 0.07 ether, // 7%
            minPenaltyPercentage: 0.005 ether, // 0.5%
            protocolFeePercentage: 0.07 ether, // 7%
            isEnabledPriorityLiquidation: false,
            disablePriorityLiquidationAbovePositionLtv: 0,
            priorityLiquidationGracePeriod: 0,
            taggerLiquidationGracePeriod: 0,
            liquidationWindowTag: 0
        });

        address irmToUse = irm_;
        if (irmToUse == address(0)) {
            IrmMock irm = new IrmMock();
            irm.setBorrowRate(0.5 ether / uint256(365 days)); // 50% per annum
            irmToUse = address(irm);
        }

        DlbDcfPriorityLiquidationEngine liquidationEngine = new DlbDcfPriorityLiquidationEngine(MARKET_OWNER);

        address oracleToUse = oracle_ == address(0) ? address(oracle) : oracle_;

        BorrowMarketInitParams memory borrowMarketInitParams = BorrowMarketInitParams({
            baseMarketInitParams: BaseMarketInitParams({
                borrowToken: loanToken_,
                collateralToken: collateralToken_,
                irm: irmToUse,
                owner: MARKET_OWNER,
                oracle: oracleToUse,
                maxLtv: lltv,
                feeRecipient: MARKET_FEE_RECIPIENT,
                liquidationEngine: address(liquidationEngine)
            }),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });

        market = MarketDeployer.deployBorrowMarket(borrowMarketInitParams);

        if (irm_ != address(0)) {
            IrmMock(irm_).setMarket(market);
        } else {
            IrmMock(irmToUse).setMarket(market);
        }

        vm.prank(MARKET_OWNER);
        liquidationEngine.setLiquidationConfiguration(liquidationConfig);
    }

    /// @dev Rolls & warps the given number of blocks forward the blockchain.
    function _forward(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * BLOCK_TIME); // Block speed should depend on test network.
    }

    /// @dev Bounds the fuzzing input to a realistic number of blocks.
    function _boundBlocks(uint256 blocks) internal pure returns (uint256) {
        return bound(blocks, 2, type(uint24).max);
    }

    /// @dev Bounds the fuzzing input to a non-zero address.
    /// @dev This function should be used in place of `vm.assume` in invariant test handler functions:
    /// https://github.com/foundry-rs/foundry/issues/4190.
    function _boundAddressNotZero(address input) internal view virtual returns (address) {
        return address(uint160(bound(uint256(uint160(input)), 1, type(uint160).max)));
    }

    function _accrueInterest(address market) internal {
        IMarket(market).accrueInterest();
    }

    /// @dev Returns a random market from the list of markets.
    function _randomMarket(uint256 seed) internal view returns (address) {
        return allMarkets[seed % (allMarkets.length - 1)];
    }

    function _randomCandidate(address[] memory candidates, uint256 seed) internal pure returns (address) {
        if (candidates.length == 0) return address(0);

        return candidates[seed % candidates.length];
    }

    function _removeAll(address[] memory inputs, address removed) internal pure returns (address[] memory result) {
        result = new address[](inputs.length);

        uint256 nbAddresses;
        for (uint256 i; i < inputs.length; ++i) {
            address input = inputs[i];

            if (input != removed) {
                result[nbAddresses] = input;
                ++nbAddresses;
            }
        }

        assembly {
            mstore(result, nbAddresses)
        }
    }

    function _randomNonZero(address[] memory users, uint256 seed) internal pure returns (address) {
        users = _removeAll(users, address(0));

        return _randomCandidate(users, seed);
    }

    function _registerMarketsInRegistry() internal {
        vm.startPrank(MARKET_OWNER);
        for (uint256 i; i < allMarkets.length; ++i) {
            marketRegistry.addBorrowMarket(allMarkets[i]);
        }
        vm.stopPrank();
    }

    function _registerMarketInRegistry(address market) internal {
        vm.prank(MARKET_OWNER);
        marketRegistry.addBorrowMarket(market);
    }
}
