// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ErpOffboard02Json, SafeTransaction} from "./ErpOffboard02Json.sol";
import {OwnerFixedRateIrmFactory} from "@alto/deployments/ethereum-mainnet/OwnerFixedRateIrmFactory.sol";
import {IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {FROZEN_TYPE, PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice Generates the Timelock batches that deploy and attach a fixed-rate IRM to each Batch B borrow market.
contract BatchBFixedRateIrmScript is ErpOffboard02Json {
    string public constant ADDRESSES_FILE =
        "contracts/deployments/ethereum-mainnet/output/ethereum-mainnet-1-1765364975/addresses.json";

    // Placeholder used by tests and by `run()`. Set it after the production factory is deployed.
    // Operational callers can instead pass the deployed address directly to `run(address)`.
    address public OWNER_FIXED_RATE_IRM_FACTORY = address(0);

    function setOwnerFixedRateIrmFactory(address factory) external {
        require(factory != address(0) && factory.code.length != 0, "Batch B: invalid factory");
        OWNER_FIXED_RATE_IRM_FACTORY = factory;
    }

    function run() external {
        _run(OWNER_FIXED_RATE_IRM_FACTORY);
    }

    function run(address factoryAddress) external {
        _run(factoryAddress);
    }

    function _run(address factoryAddress) private {
        require(block.chainid == 1, "Batch B: Ethereum mainnet only");
        require(factoryAddress != address(0) && factoryAddress.code.length != 0, "Batch B: set factory address");

        string memory addresses = vm.readFile(ADDRESSES_FILE);
        address timelock = vm.parseJsonAddress(addresses, ".contracts.timelock");
        (address[] memory borrowMarkets, uint256[] memory borrowRatesSpy) = borrowMarketConfiguration();
        require(borrowMarkets.length != 0, "Batch B: no markets");
        require(borrowMarkets.length == borrowRatesSpy.length, "Batch B: market/rate length mismatch");

        OwnerFixedRateIrmFactory factory = OwnerFixedRateIrmFactory(factoryAddress);
        require(factory.owner() == timelock, "Batch B: Timelock does not own factory");
        require(factory.pendingOwner() == address(0), "Batch B: factory ownership transfer pending");

        uint256 initialNonce = factory.nonce();
        SafeTransaction[] memory transactions = new SafeTransaction[](borrowMarkets.length * 2);

        for (uint256 i; i < borrowMarkets.length; ++i) {
            address market = borrowMarkets[i];
            require(market != address(0) && market.code.length != 0, "Batch B: invalid market");
            require(borrowRatesSpy[i] <= 8 ether / uint256(365 days), "Batch B: rate above IRM maximum");
            require(Ownable(market).owner() == timelock, "Batch B: Timelock does not own market");
            require(IMarketBase(market).paused(FROZEN_TYPE), "Batch B: market not frozen");
            require(!IMarketBase(market).paused(PAUSE_TYPE), "Batch B: market paused");

            for (uint256 j; j < i; ++j) {
                require(market != borrowMarkets[j], "Batch B: duplicate market");
            }

            address predictedIrm = factory.predictIrmAddress(borrowRatesSpy[i], timelock, initialNonce + i);
            require(predictedIrm.code.length == 0, "Batch B: predicted IRM already deployed");
            transactions[i] = _transaction(
                address(factory), abi.encodeCall(OwnerFixedRateIrmFactory.deploy, (market, borrowRatesSpy[i], timelock))
            );
        }

        for (uint256 i; i < borrowMarkets.length; ++i) {
            address fixedRateIrm = factory.predictIrmAddress(borrowRatesSpy[i], timelock, initialNonce + i);
            transactions[borrowMarkets.length + i] =
                _transaction(borrowMarkets[i], abi.encodeCall(IMarketBase.setIrm, (fixedRateIrm, false)));
        }

        _writeTimelockPair(
            "batch-b-fixed-rate-irm",
            "ERP-OFFBOARD-02 - Batch B Deploy and Attach Fixed-Rate IRMs",
            MAINNET_TIMELOCK_SAFE,
            timelock,
            TimelockController(payable(timelock)).getMinDelay(),
            transactions
        );
    }

    /// @dev Placeholder configuration only. Batch B can contain any number of borrow markets.
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

        borrowRatesSpy[0] = 0.1 ether / uint256(365 days);
        borrowRatesSpy[1] = 0.1 ether / uint256(365 days);
        borrowRatesSpy[2] = 0.1 ether / uint256(365 days);
        borrowRatesSpy[3] = 0.1 ether / uint256(365 days);
        borrowRatesSpy[4] = 0.1 ether / uint256(365 days);
    }
}
