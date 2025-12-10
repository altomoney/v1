// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

interface ITestnetMarketBatch {
    function getMarketReport() external view returns (TestnetMarketBatchReport memory);
}

struct TestnetMarketBatchReport {
    address market;
    address marketImplementation;
    address marketIrm;
    address marketOracle;
    address liquidationEngine;
}
