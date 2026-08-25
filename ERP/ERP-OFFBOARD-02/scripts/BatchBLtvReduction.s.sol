// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ErpOffboard02Json, SafeTransaction} from "./ErpOffboard02Json.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {IIrm, IRMType} from "@alto/lending/interfaces/IIrm.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineBase,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Generates Timelock batches that update Batch B IRM rates and reduce LTVs by five percentage points.
contract BatchBLtvReductionScript is ErpOffboard02Json {
    string public constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";
    uint256 public constant LTV_REDUCTION = 0.05 ether;

    function run() external {
        require(block.chainid == 1, "Batch B: Ethereum mainnet only");

        string memory addresses = vm.readFile(ADDRESSES_FILE);
        address timelock = vm.parseJsonAddress(addresses, ".contracts.timelock");
        (address[] memory borrowMarkets, uint256[] memory borrowRatesSpy) = borrowMarketConfiguration();
        require(borrowMarkets.length != 0, "Batch B: no markets");
        require(borrowMarkets.length == borrowRatesSpy.length, "Batch B: market/rate length mismatch");
        SafeTransaction[] memory transactions = new SafeTransaction[](borrowMarkets.length * 3);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            require(borrowMarkets[i] != address(0) && borrowMarkets[i].code.length != 0, "Batch B: invalid market");
            for (uint256 j; j < i; ++j) {
                require(borrowMarkets[i] != borrowMarkets[j], "Batch B: duplicate market");
            }

            IMarketBase market = IMarketBase(borrowMarkets[i]);
            require(market.paused(FROZEN_TYPE), "Batch B: market not frozen");
            require(!market.paused(PAUSE_TYPE), "Batch B: market paused");
            require(Ownable(address(market)).owner() == timelock, "Batch B: Timelock does not own market");

            address fixedRateIrm = market.irm();
            address liquidationEngine = market.liquidationEngine();
            require(fixedRateIrm.code.length != 0, "Batch B: invalid IRM");
            require(liquidationEngine.code.length != 0, "Batch B: invalid liquidation engine");
            require(IIrm(fixedRateIrm).IRM_TYPE() == IRMType.FIXED_RATE, "Batch B: IRM is not fixed-rate");
            require(FixedRateIrm(fixedRateIrm).market() == address(market), "Batch B: IRM not dedicated");
            require(FixedRateIrm(fixedRateIrm).owner() == timelock, "Batch B: Timelock does not own IRM");
            require(
                IDcfDlbPriorityLiquidationEngine(liquidationEngine).market() == address(market),
                "Batch B: wrong liquidation engine"
            );
            require(Ownable(liquidationEngine).owner() == timelock, "Batch B: Timelock does not own liquidation engine");
            require(
                borrowRatesSpy[i] <= FixedRateIrm(fixedRateIrm).MAX_BORROW_RATE(), "Batch B: rate above IRM maximum"
            );

            (uint256 currentBorrowRate,) = FixedRateIrm(fixedRateIrm).irState();
            require(borrowRatesSpy[i] >= currentBorrowRate, "Batch B: rate below current rate");

            LiquidationConfiguration memory liquidationConfiguration =
                IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();

            uint256 reducedMarketMaxLtv = reduceByFivePercentagePoints(market.maxLtv());
            liquidationConfiguration.maxLiquidationLtv =
                reduceByFivePercentagePoints(liquidationConfiguration.maxLiquidationLtv);
            liquidationConfiguration.ltvForCompleteLiquidation =
                reduceByFivePercentagePoints(liquidationConfiguration.ltvForCompleteLiquidation);
            require(
                reducedMarketMaxLtv <= liquidationConfiguration.maxLiquidationLtv
                    && liquidationConfiguration.maxLiquidationLtv <= liquidationConfiguration.ltvForCompleteLiquidation,
                "Batch B: invalid LTV order"
            );

            transactions[i * 3] =
                _transaction(fixedRateIrm, abi.encodeCall(FixedRateIrm.setBorrowRate, (borrowRatesSpy[i])));
            transactions[i * 3 + 1] =
                _transaction(address(market), abi.encodeCall(IMarketBase.setMaxLtv, (reducedMarketMaxLtv)));
            transactions[i * 3 + 2] = _transaction(
                liquidationEngine,
                abi.encodeCall(
                    IDcfDlbPriorityLiquidationEngineBase.setLiquidationConfiguration, (liquidationConfiguration)
                )
            );
        }

        uint256 correctionDelay = TimelockController(payable(timelock)).getMinDelay();
        if (correctionDelay < 1 hours) correctionDelay = 1 hours;

        _writeTimelockPair(
            "batch-b-irm-and-ltv-update",
            "ERP-OFFBOARD-02 - Batch B Update IRM Rates and Reduce LTVs by Five Percentage Points",
            MAINNET_TIMELOCK_SAFE,
            timelock,
            correctionDelay,
            transactions
        );
    }

    function reduceByFivePercentagePoints(uint256 value) public pure returns (uint256) {
        return value > LTV_REDUCTION ? value - LTV_REDUCTION : 0;
    }

    /// @dev Placeholder configuration for one approved scheduled or terminal step.
    /// Run this script again only after the prior step executes and a fresh current-state simulation passes.
    /// Batch B can contain any number of borrow markets.
    /// Keep `borrowMarkets` and `borrowRatesSpy` the same length and in matching order.
    function borrowMarketConfiguration()
        public
        view
        returns (address[] memory borrowMarkets, uint256[] memory borrowRatesSpy)
    {
        string memory addresses = vm.readFile(ADDRESSES_FILE);
        borrowMarkets = new address[](5);
        borrowRatesSpy = new uint256[](5);

        borrowMarkets[0] = vm.parseJsonAddress(addresses, ".contracts.wbtcBorrowMarket");
        borrowMarkets[1] = vm.parseJsonAddress(addresses, ".contracts.cbbtcBorrowMarket");
        borrowMarkets[2] = vm.parseJsonAddress(addresses, ".contracts.susdeBorrowMarket");
        borrowMarkets[3] = vm.parseJsonAddress(addresses, ".contracts.syrupUsdcBorrowMarket");
        borrowMarkets[4] = vm.parseJsonAddress(addresses, ".contracts.paxgBorrowMarket");

        borrowRatesSpy[0] = 0.2 ether / uint256(365 days); // TODO: WBTC rate
        borrowRatesSpy[1] = 0.2 ether / uint256(365 days); // TODO: cbBTC rate
        borrowRatesSpy[2] = 0.2 ether / uint256(365 days); // TODO: sUSDe rate
        borrowRatesSpy[3] = 0.2 ether / uint256(365 days); // TODO: syrupUSDC rate
        borrowRatesSpy[4] = 0.2 ether / uint256(365 days); // TODO: PAXG rate
    }
}
