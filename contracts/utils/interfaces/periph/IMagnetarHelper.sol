// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {RebaseLibrary, Rebase} from "@boringcrypto/boring-solidity/contracts/libraries/BoringRebase.sol";
import {ISingularity} from "src/tap-utils/interfaces/bar/ISingularity.sol";
import {ITapiocaOracle} from "tap-utils/interfaces/periph/ITapiocaOracle.sol";
import {IMarket} from "tap-utils/interfaces/bar/IMarket.sol";
import {IBigBang} from "tap-utils/interfaces/bar/IBigBang.sol";

/*

████████╗ █████╗ ██████╗ ██╗ ██████╗  ██████╗ █████╗ 
╚══██╔══╝██╔══██╗██╔══██╗██║██╔═══██╗██╔════╝██╔══██╗
   ██║   ███████║██████╔╝██║██║   ██║██║     ███████║
   ██║   ██╔══██║██╔═══╝ ██║██║   ██║██║     ██╔══██║
   ██║   ██║  ██║██║     ██║╚██████╔╝╚██████╗██║  ██║
   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
   
*/

struct MarketInfo {
    address collateral;
    address asset;
    ITapiocaOracle oracle;
    bytes oracleData;
    uint256 totalCollateralShare;
    uint256 userCollateralShare;
    Rebase totalBorrow;
    uint256 userBorrowPart;
    uint256 currentExchangeRate;
    uint256 spotExchangeRate;
    uint256 oracleExchangeRate;
    uint256 totalBorrowCap; // TODO Check all the Yield box related fields removed
    uint256 totalCollateralAmount;
    uint256 collateralizationRate;
    uint256 liquidationCollateralizationRate;
    uint256 minLiquidatorReward;
    uint256 maxLiquidatorReward;
    uint256 liquidationBonusAmount;
    uint256 minBorrowAmount;
    uint256 minCollateralAmount;
}

struct SingularityInfo {
    MarketInfo market;
    Rebase totalAsset;
    uint256 userAssetFraction;
    ISingularity.AccrueInfo accrueInfo;
    uint256 utilization;
    uint256 minimumTargetUtilization;
    uint256 maximumTargetUtilization;
    uint256 minimumInterestPerSecond;
    uint256 maximumInterestPerSecond;
    uint256 interestElasticity;
    uint256 startingInterestPerSecond;
    uint256 minLendAmount;
}

struct BigBangInfo {
    MarketInfo market;
    IBigBang.AccrueInfo accrueInfo;
    uint256 minDebtRate;
    uint256 maxDebtRate;
    uint256 debtRateAgainstEthMarket;
    address mainBBMarket;
    uint256 mainBBDebtRate;
    uint256 currentDebtRate;
}

interface IMagnetarHelper {

    /**
     * @notice returns Singularity markets' information.
     * @param who user to return for.
     * @param markets the list of Singularity markets to query for.
     */
    function singularityMarketInfo(address who, ISingularity[] calldata markets)
        external
        view
        returns (SingularityInfo[] memory);

    /**
     * @notice returns BigBang markets' information.
     * @param who user to return for.
     * @param markets the list of BigBang markets to query for.
     */
    function bigBangMarketInfo(address who, IBigBang[] calldata markets) external view returns (BigBangInfo[] memory);

    /**
     * @notice Calculate the collateral amount off the shares.
     * @param market the Singularity or BigBang address.
     * @param share The shares.
     * @return amount The amount.
     */
    function getCollateralAmountForShare(IMarket market, uint256 share) external view returns (uint256 amount);

    /**
     * @notice Calculate the collateral shares that are needed for `borrowPart,
     *       taking the current exchange rate into account.
     * @param market the Singularity or BigBang address
     * @param borrowPart The borrow part.
     * @return collateralShares The collateral shares.
     */
    function getCollateralSharesForBorrowPart(
        IMarket market,
        uint256 borrowPart,
        uint256 collateralizationRatePrecision,
        uint256 exchangeRatePrecision,
        bool roundAmounUp,
        bool roundSharesUp
    ) external view returns (uint256 collateralShares);

    /**
     * @notice Return the equivalent of borrow part in asset amount.
     * @param market the Singularity or BigBang address.
     * @param borrowPart The amount of borrow part to convert.
     * @param roundUp If true, the result is rounded up.
     * @return amount The equivalent of borrow part in asset amount.
     */
    function getAmountForBorrowPart(IMarket market, uint256 borrowPart, bool roundUp)
        external
        view
        returns (uint256 amount);

    /**
     * @notice Return the equivalent of amount in borrow part.
     * @param market the Singularity or BigBang address.
     * @param amount The amount to convert.
     * @param roundUp If true, the result is rounded up.
     * @return part The equivalent of amount in borrow part.
     */
    function getBorrowPartForAmount(IMarket market, uint256 amount, bool roundUp)
        external
        view
        returns (uint256 part);

    /**
     * @notice Compute the amount of `singularity.assetId` from `fraction`
     *       `fraction` can be `singularity.accrueInfo.feeFraction` or `singularity.balanceOf`.
     * @param singularity the singularity address.
     * @param fraction The fraction.
     * @return amount The amount.
     */
    function getAmountForAssetFraction(ISingularity singularity, uint256 fraction)
        external
        view
        returns (uint256 amount);

    /**
     * @notice Compute the fraction of `singularity.assetId` from `amount`
     *       `fraction` can be `singularity.accrueInfo.feeFraction` or `singularity.balanceOf`.
     * @param singularity the singularity address.
     * @param amount The amount.
     * @param roundUp true/false for rounding up shares.
     * @return fraction The fraction.
     */
    function getFractionForAmount(ISingularity singularity, uint256 amount, bool roundUp)
        external
        view
        returns (uint256 fraction);
}
