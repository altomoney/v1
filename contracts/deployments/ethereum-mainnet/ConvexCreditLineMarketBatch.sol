// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoConvexCreditLineMarket} from "@alto/lending/credit-market/AltoConvexCreditLineMarket.sol";
import {
    CreditMarketInitParams,
    ConvexCreditLineInitParams
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {BaseMarketInitParams} from "@alto/lending/interfaces/IMarket.sol";
import {FixedRateIrm} from "@alto/lending/irm/FixedRateIrm.sol";
import {AltoCreditMarketLpOracle} from "@alto/oracles/AltoCreditMarketLpOracle/AltoCreditMarketLpOracle.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {UnsafeUpgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {ConvexCreditLineMarketContracts} from "@alto/deployments/ethereum-mainnet/IDeployAltoEthereumMainnet.sol";

struct ConvexCreditLineMarketBatchParams {
    address owner;
    address dusd;
    address feeRecipient;
    address collateralToken;
    address creditAccount;
    uint256 irmInterestRate;
    uint256 maxLtv;
    uint256 creditLimit;
    uint256 foreclosureLtv;
    uint256 initialBorrowOpeningFee;
    address convexBooster;
    uint256 convexPoolId;
    address rewardRecipient;
    address[] rewardTokens;
    address freezer;
    address emergencyController;
}

/// @notice Deploys and initializes the frxUSD/DUSD Convex credit-line market components atomically.
/// @dev The batch temporarily owns the market only while emergency-controller permissions are configured.
contract ConvexCreditLineMarketBatch {
    ConvexCreditLineMarketContracts private report;

    constructor(ConvexCreditLineMarketBatchParams memory params) {
        address marketIrm = address(new FixedRateIrm(params.irmInterestRate, params.owner));
        address marketOracle = address(new AltoCreditMarketLpOracle());
        address marketImplementation = address(new AltoConvexCreditLineMarket());

        bytes memory initData = abi.encodeCall(
            AltoConvexCreditLineMarket.initialize,
            (ConvexCreditLineInitParams({
                    creditMarketInitParams: CreditMarketInitParams({
                        baseMarketInitParams: BaseMarketInitParams({
                            borrowToken: params.dusd,
                            collateralToken: params.collateralToken,
                            irm: marketIrm,
                            owner: address(this),
                            emergencyAdmin: params.freezer,
                            oracle: marketOracle,
                            maxLtv: params.maxLtv,
                            feeRecipient: params.feeRecipient,
                            liquidationEngine: address(0)
                        }),
                        creditAccount: params.creditAccount,
                        creditLimit: params.creditLimit,
                        foreclosureLtv: params.foreclosureLtv,
                        initialBorrowOpeningFee: params.initialBorrowOpeningFee
                    }),
                    convexBooster: params.convexBooster,
                    convexPoolId: params.convexPoolId,
                    rewardRecipient: params.rewardRecipient,
                    rewardTokens: params.rewardTokens
                }))
        );
        address market = UnsafeUpgrades.deployUUPSProxy(marketImplementation, initData);

        IPausable(market).setPauser(params.emergencyController, PAUSE_TYPE, true);
        IPausable(market).setPauser(params.emergencyController, FROZEN_TYPE, true);
        AltoOwnable2StepUpgradeable(market).transferOwnershipSkip2Step(params.owner);

        report = ConvexCreditLineMarketContracts({
            market: market, marketImplementation: marketImplementation, marketIrm: marketIrm, marketOracle: marketOracle
        });
    }

    function getReport() external view returns (ConvexCreditLineMarketContracts memory) {
        return report;
    }
}
