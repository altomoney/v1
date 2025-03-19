// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {TestnetOracle} from "test/utils/mocks/TestnetOracle.sol";

struct TestnetOracles {
    address stETHOracle;
    address usdoOracle;
    address usdcOracle;
    address tapOracle;
}

/// @title TestnetOraclesBatch
/// @notice Deploy testnet oracles
/// @dev Batches performs 1-tx deployments via constructor deployment pattern and contains on-chain reports of deployed contracts
contract TestnetOraclesBatch {
    TestnetOracles public oracles;

    constructor() {
        oracles = TestnetOracles({
            stETHOracle: address(new TestnetOracle("stETH/USD", "stETH/USD", 50000, msg.sender, 8)),
            tapOracle: address(new TestnetOracle("TAP/USD", "TAP/USD", 10000000, msg.sender, 8)),
            usdoOracle: address(new TestnetOracle("USDO/USD", "USDO/USD", 1e8, msg.sender, 8)),
            usdcOracle: address(new TestnetOracle("USDC/USD", "USDC/USD", 1e8, msg.sender, 8))
        });
    }

    function getOraclesReport() public view returns (TestnetOracles memory) {
        return oracles;
    }
}
