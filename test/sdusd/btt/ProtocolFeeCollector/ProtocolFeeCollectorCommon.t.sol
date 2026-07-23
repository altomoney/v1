// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

import {ProtocolFeeCollector} from "@alto/sdusd/ProtocolFeeCollector.sol";
import {SDUSD} from "@alto/sdusd/SDUSD.sol";
import {SDUSDInitParams} from "@alto/sdusd/interfaces/ISDUSDVault.sol";
import {
    FeeSourceType,
    IProtocolFeeCollectorEvents,
    ProtocolFeeCollectorInitParams
} from "@alto/sdusd/interfaces/IProtocolFeeCollector.sol";
import {DUSD} from "@alto/tokens/DUSD.sol";
import {MarketRegistry} from "@alto/utils/MarketRegistry.sol";
import {UsmRegistry} from "@alto/utils/UsmRegistry.sol";
import {DUSDUsm} from "@alto/usm/DUSDUsm.sol";
import {DUSDFlashMinter} from "@alto/usm/DUSDFlashMinter.sol";
import {FixedPriceStrategy} from "@alto/usm/FixedPriceStrategy.sol";
import {FixedFeeStrategy} from "@alto/usm/FixedFeeStrategy.sol";
import {AccessMode} from "@alto/usm/interfaces/IUsm.sol";
import {FlashFee} from "@alto/usm/interfaces/IDUSDFlashMinter.sol";
import {
    IMarket,
    BaseMarketInitParams,
    BorrowMarketInitParams,
    MintMarketInitParams
} from "@alto/lending/interfaces/IMarket.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {OracleMock} from "@alto/oracles/mocks/OracleMock.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {ERC20MockMintableDecimals} from "@alto-test/helpers/ERC20MockMintableDecimals.sol";
import {MarketDeployer} from "@alto-test/helpers/MarketDeployer.sol";

contract ProtocolFeeCollectorFlashBorrower is IERC3156FlashBorrower {
    IERC3156FlashLender internal immutable lender;

    constructor(IERC3156FlashLender lender_) {
        lender = lender_;
    }

    function flashBorrow(address token, uint256 amount) external {
        lender.flashLoan(this, token, amount, "");
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        require(msg.sender == address(lender), "untrusted lender");
        require(initiator == address(this), "untrusted initiator");
        IERC20(token).approve(address(lender), amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

abstract contract ProtocolFeeCollectorCommon is Test, TestHelperOz5 {
    uint256 internal constant INITIAL_REWARDS_BPS = 3_000;
    uint256 internal constant SEED_SHARES = 1 ether;
    uint256 internal constant REWARD_DURATION = 7 days;
    uint256 internal constant MARKET_MAX_LTV = 0.75 ether;
    uint256 internal constant MINT_OPENING_FEE = 0.1 ether;
    uint256 internal constant USM_EXPOSURE_CAP = 1_000_000e6;
    uint256 internal constant USM_FEE_BPS = 100;
    uint128 internal constant FLASH_FEE = 0.01 ether;
    uint256 internal constant FLASH_MINT_CAP = 1_000_000 ether;

    address internal ADMIN = makeAddr("Admin");
    address internal COLLATERAL_OPERATOR = makeAddr("CollateralOperator");
    address internal PAUSER = makeAddr("Pauser");
    address internal TREASURY = makeAddr("Treasury");
    address internal MANUAL_SWAP_RECEIVER = makeAddr("ManualSwapReceiver");
    address internal USER = makeAddr("User");
    address internal BORROWER = makeAddr("Borrower");

    DUSD internal dusd;
    ERC20MockMintableDecimals internal otherToken;
    ERC20MockMintableDecimals internal collateralToken;
    ERC20MockMintableDecimals internal underlyingToken;
    OracleMock internal oracle;

    MarketRegistry internal marketRegistry;
    UsmRegistry internal usmRegistry;
    IMarket internal borrowMarket;
    IMarket internal mintMarket;
    IMarket internal wrongTokenBorrowMarket;
    IMarket internal wrongTokenMintMarket;
    DUSDUsm internal usm;
    DUSDUsm internal wrongTokenUsm;
    DUSDFlashMinter internal flashMinter;
    DUSDFlashMinter internal wrongTokenFlashMinter;
    ProtocolFeeCollectorFlashBorrower internal flashBorrower;
    SDUSD internal sdusdVault;

    ProtocolFeeCollector internal implementation;
    ProtocolFeeCollector internal collector;
    ProtocolFeeCollectorInitParams internal initParams;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(1, LibraryType.UltraLightNode);

        dusd = new DUSD(address(endpoints[1]), ADMIN);
        otherToken = new ERC20MockMintableDecimals("Other", "OTHER", 18);
        collateralToken = new ERC20MockMintableDecimals("Collateral", "COLL", 18);
        underlyingToken = new ERC20MockMintableDecimals("Underlying", "USDC", 6);
        oracle = new OracleMock();
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);

        marketRegistry = new MarketRegistry(ADMIN);
        usmRegistry = new UsmRegistry(ADMIN);
        borrowMarket = _deployBorrowMarket(address(dusd));
        mintMarket = _deployMintMarket(address(dusd));
        wrongTokenBorrowMarket = _deployBorrowMarket(address(otherToken));
        wrongTokenMintMarket = _deployMintMarket(address(otherToken));
        usm = _deployUsm(address(dusd));
        wrongTokenUsm = _deployUsm(address(otherToken));

        FlashFee memory flashFee = FlashFee({minFlashFee: FLASH_FEE, maxFlashFee: FLASH_FEE});
        flashMinter = new DUSDFlashMinter(address(dusd), TREASURY, flashFee, ADMIN);
        wrongTokenFlashMinter = new DUSDFlashMinter(address(otherToken), TREASURY, flashFee, ADMIN);
        flashBorrower = new ProtocolFeeCollectorFlashBorrower(IERC3156FlashLender(address(flashMinter)));

        implementation = new ProtocolFeeCollector();
        initParams = _validInitParams();
        collector = _deployCollector(initParams);

        FixedFeeStrategy feeStrategy = new FixedFeeStrategy(USM_FEE_BPS, USM_FEE_BPS, ADMIN);

        vm.startPrank(ADMIN);
        borrowMarket.setFeeRecipient(address(collector));
        mintMarket.setFeeRecipient(address(collector));
        AltoMintMarket(address(mintMarket)).setBorrowOpeningFee(MINT_OPENING_FEE);
        usm.updateFeeRecipient(address(collector));
        usm.updateFeeStrategy(address(feeStrategy));
        flashMinter.updateFeeRecipient(address(collector));

        dusd.setMinterStatus(address(this), true);
        dusd.setMinterCeiling(address(this), type(uint128).max);
        _configureDusdFacilitator(address(mintMarket));
        _configureDusdFacilitator(address(usm));
        _configureDusdFacilitator(address(flashMinter));
        vm.stopPrank();

        sdusdVault = _deploySdusdVault(_sdusdInitParams(SEED_SHARES, REWARD_DURATION));
        _seedSdusdVault();
        _depositLiveSdusdPosition();
    }

    function _sdusdInitParams(uint256 seedShares, uint256 rewardDuration)
        internal
        view
        returns (SDUSDInitParams memory params)
    {
        params = SDUSDInitParams({
            admin: ADMIN,
            pauser: PAUSER,
            dusd: address(dusd),
            rewarder: address(collector),
            seedShares: seedShares,
            rewardDuration: rewardDuration
        });
    }

    function _deploySdusdVault(SDUSDInitParams memory params) internal returns (SDUSD deployed) {
        SDUSD sdusdImplementation = new SDUSD();
        ERC1967Proxy proxy = new ERC1967Proxy(address(sdusdImplementation), abi.encodeCall(SDUSD.initialize, (params)));
        deployed = SDUSD(address(proxy));
    }

    function _expectSdusdInitializationRevert(SDUSDInitParams memory params, bytes4 expectedError) internal {
        SDUSD sdusdImplementation = new SDUSD();

        vm.expectRevert(expectedError);
        new ERC1967Proxy(address(sdusdImplementation), abi.encodeCall(SDUSD.initialize, (params)));
    }

    function _validInitParams() internal view returns (ProtocolFeeCollectorInitParams memory params) {
        params = ProtocolFeeCollectorInitParams({
            admin: ADMIN,
            collateralOperator: COLLATERAL_OPERATOR,
            pauser: PAUSER,
            dusd: address(dusd),
            marketRegistry: address(marketRegistry),
            usmRegistry: address(usmRegistry),
            flashMinter: address(flashMinter),
            treasury: TREASURY,
            manualSwapReceiver: MANUAL_SWAP_RECEIVER,
            rewardsBps: INITIAL_REWARDS_BPS
        });
    }

    function _deployCollector(ProtocolFeeCollectorInitParams memory params)
        internal
        returns (ProtocolFeeCollector deployed)
    {
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(implementation), abi.encodeCall(ProtocolFeeCollector.initialize, (params)));
        deployed = ProtocolFeeCollector(address(proxy));
    }

    function _deployBorrowMarket(address borrowToken) internal returns (IMarket market) {
        DlbDcfPriorityLiquidationEngine engine = new DlbDcfPriorityLiquidationEngine(ADMIN);
        BorrowMarketInitParams memory params = BorrowMarketInitParams({
            baseMarketInitParams: _baseMarketParams(borrowToken, address(engine)),
            initialBorrowOpeningFee: 0,
            supplyCapAssets: 0,
            initialInterestFee: 0
        });
        market = IMarket(MarketDeployer.deployBorrowMarket(params));
        _configureLiquidationEngine(engine);
    }

    function _deployMintMarket(address borrowToken) internal returns (IMarket market) {
        DlbDcfPriorityLiquidationEngine engine = new DlbDcfPriorityLiquidationEngine(ADMIN);
        MintMarketInitParams memory params = MintMarketInitParams({
            baseMarketInitParams: _baseMarketParams(borrowToken, address(engine)),
            debtCeiling: 1_000_000 ether,
            initialBorrowOpeningFee: 0
        });
        market = IMarket(MarketDeployer.deployMintMarket(params));
        _configureLiquidationEngine(engine);
    }

    function _baseMarketParams(address borrowToken, address liquidationEngine)
        internal
        view
        returns (BaseMarketInitParams memory)
    {
        return BaseMarketInitParams({
            borrowToken: borrowToken,
            collateralToken: address(collateralToken),
            irm: address(0),
            owner: ADMIN,
            oracle: address(oracle),
            maxLtv: MARKET_MAX_LTV,
            feeRecipient: TREASURY,
            liquidationEngine: liquidationEngine
        });
    }

    function _configureLiquidationEngine(DlbDcfPriorityLiquidationEngine engine) internal {
        LiquidationConfiguration memory config = LiquidationConfiguration({
            maxLiquidationLtv: 0.8 ether,
            dynamicBonusFeeStart: 0.03 ether,
            ltvForCompleteLiquidation: 0.9 ether,
            dynamicBonusFeeDecaySteepness: 5 ether,
            liquidationBaseFee: 0.05 ether,
            minPenaltyPercentage: 0.01 ether,
            protocolFeePercentage: 0,
            isEnabledPriorityLiquidation: false,
            disablePriorityLiquidationAbovePositionLtv: type(uint256).max,
            priorityLiquidationGracePeriod: 5 minutes,
            taggerLiquidationGracePeriod: 2 minutes,
            liquidationWindowTag: 3 days
        });
        vm.prank(ADMIN);
        IDcfDlbPriorityLiquidationEngine(address(engine)).setLiquidationConfiguration(config);
    }

    function _deployUsm(address stableToken) internal returns (DUSDUsm deployed) {
        FixedPriceStrategy priceStrategy = new FixedPriceStrategy(1 ether, address(underlyingToken), ADMIN);
        DUSDUsm usmImplementation = new DUSDUsm(stableToken, address(underlyingToken));
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(usmImplementation),
            abi.encodeCall(
                DUSDUsm.initialize,
                (ADMIN, TREASURY, uint128(USM_EXPOSURE_CAP), address(priceStrategy), AccessMode.PERMISSIONLESS)
            )
        );
        deployed = DUSDUsm(address(proxy));
    }

    function _configureDusdFacilitator(address facilitator) internal {
        dusd.setMinterStatus(facilitator, true);
        dusd.setMinterCeiling(facilitator, type(uint128).max);
        dusd.setBurnerStatus(facilitator, true);
    }

    function _seedSdusdVault() internal {
        dusd.mint(address(this), SEED_SHARES);
        dusd.approve(address(sdusdVault), SEED_SHARES);
        uint256 mintedShares = sdusdVault.deposit(SEED_SHARES, address(1));

        assertEq(mintedShares, SEED_SHARES);
        assertEq(sdusdVault.balanceOf(address(1)), SEED_SHARES);
        assertEq(sdusdVault.accountedAssets(), SEED_SHARES);
    }

    function _depositLiveSdusdPosition() internal {
        dusd.mint(USER, SEED_SHARES);
        vm.startPrank(USER);
        dusd.approve(address(sdusdVault), SEED_SHARES);
        sdusdVault.deposit(SEED_SHARES, USER);
        vm.stopPrank();
    }

    function _setSdusdVault() internal {
        vm.prank(ADMIN);
        collector.setSdusdVault(address(sdusdVault));
    }

    function _setRewardsBps(uint256 newRewardsBps) internal {
        vm.prank(ADMIN);
        collector.setRewardsBps(newRewardsBps);
    }

    function _pause() internal {
        vm.prank(PAUSER);
        collector.pause(PAUSE_TYPE, true);
    }

    function _allowBorrowMarket(address market) internal {
        vm.prank(ADMIN);
        marketRegistry.addBorrowMarket(market);
    }

    function _allowMintMarket(address market) internal {
        vm.prank(ADMIN);
        marketRegistry.addMintMarket(market);
    }

    function _allowUsm(address usmAddress) internal {
        vm.prank(ADMIN);
        usmRegistry.addUsm(usmAddress);
    }

    function _supplyBorrowMarket(uint256 assets) internal returns (uint256 shares) {
        dusd.mint(address(this), assets);
        dusd.approve(address(borrowMarket), assets);
        (, shares) = borrowMarket.addSupply(assets, 0, address(collector));
    }

    function _supplyBorrowMarketShares(uint256 shares) internal returns (uint256 assets) {
        dusd.mint(address(this), 1 ether);
        dusd.approve(address(borrowMarket), type(uint256).max);
        (assets,) = borrowMarket.addSupply(0, shares, address(collector));
    }

    function _borrowFromMarket(IMarket market, uint256 assets) internal {
        uint256 collateralAmount = assets * 2;
        collateralToken.mint(BORROWER, collateralAmount);
        vm.startPrank(BORROWER);
        collateralToken.approve(address(market), collateralAmount);
        market.addCollateral(collateralAmount, BORROWER);
        market.borrow(assets, 0, BORROWER, BORROWER, "");
        vm.stopPrank();
    }

    function _addCollectorCollateral(IMarket market, uint256 amount) internal {
        collateralToken.mint(address(this), amount);
        collateralToken.approve(address(market), amount);
        market.addCollateral(amount, address(collector));
    }

    function _generateMintMarketFees(uint256 borrowAmount) internal returns (uint256 fees) {
        _borrowFromMarket(mintMarket, borrowAmount);
        fees = AltoMintMarket(address(mintMarket)).claimableFeesAssets();
    }

    function _generateUsmFees(uint256 underlyingAmount) internal returns (uint256 fees) {
        underlyingToken.mint(USER, underlyingAmount);
        vm.startPrank(USER);
        underlyingToken.approve(address(usm), underlyingAmount);
        usm.sellAsset(underlyingAmount, USER);
        vm.stopPrank();
        fees = usm.getAccruedFees();
    }

    function _generateFlashFees(uint256 amount) internal returns (uint256 fees) {
        fees = flashMinter.flashFee(address(dusd), amount);
        dusd.mint(address(flashBorrower), fees);
        flashBorrower.flashBorrow(address(dusd), amount);
    }

    function _startRewardPeriod(uint256 collected) internal {
        _setSdusdVault();
        dusd.mint(address(collector), collected);
        collector.distribute();
    }

    function _singleSource(FeeSourceType sourceType, address source)
        internal
        pure
        returns (FeeSourceType[] memory sourceTypes, address[] memory sources)
    {
        sourceTypes = new FeeSourceType[](1);
        sources = new address[](1);
        sourceTypes[0] = sourceType;
        sources[0] = source;
    }

    function _singleMarket(address market, uint256 amount)
        internal
        pure
        returns (address[] memory markets, uint256[] memory amounts)
    {
        markets = new address[](1);
        amounts = new uint256[](1);
        markets[0] = market;
        amounts[0] = amount;
    }

    function _countLogs(Vm.Log[] memory logs, bytes32 topic0, address emitter) internal pure returns (uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length != 0 && logs[i].topics[0] == topic0) count++;
        }
    }

    function _expectHarvested(FeeSourceType sourceType, address source, uint256 amount) internal {
        vm.expectEmit(true, true, false, true, address(collector));
        emit IProtocolFeeCollectorEvents.Harvested(sourceType, source, amount);
    }
}
