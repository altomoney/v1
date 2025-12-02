// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IMarket, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IFeeClaimer, MarketType, TokenBalance} from "@alto/utils/interfaces/IFeeClaimer.sol";

/// @title FeeClaimer
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice A contract that claims fees and collateral from Mint markets and Borrow markets
contract FeeClaimer is Ownable2Step, IFeeClaimer {
    using AssetShareConversionMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IFeeClaimer
    mapping(address => bool) public feeClaimer;

    /// @dev Active mint markets stored as EnumerableSet for O(1) operations
    EnumerableSet.AddressSet private _activeMintMarkets;

    /// @dev Active borrow markets stored as EnumerableSet for O(1) operations
    EnumerableSet.AddressSet private _activeBorrowMarkets;

    /// @inheritdoc IFeeClaimer
    address public feeRecipient;

    /// @inheritdoc IFeeClaimer
    address public dusd;

    /// @notice constructor
    /// @param _owner The owner of the contract
    /// @param _dusd The address of the DUSD contract
    /// @param _feeRecipient The address to which fees claimed will be transferred to
    constructor(address _owner, address _dusd, address _feeRecipient) Ownable(_owner) {
        if (_dusd == address(0) || _feeRecipient == address(0)) {
            revert FeeClaimerInvalidInput();
        }

        dusd = _dusd;
        emit SetDusd(address(0), _dusd);

        feeRecipient = _feeRecipient;
        emit SetFeeRecipient(address(0), _feeRecipient);
    }

    modifier onlyOwnerOrFeeClaimer() {
        if (msg.sender != owner() && !feeClaimer[msg.sender]) {
            revert FeeClaimerUnauthorized();
        }
        _;
    }

    /// @inheritdoc IFeeClaimer
    function activeMintMarkets(uint256 index) external view returns (address) {
        return _activeMintMarkets.at(index);
    }

    /// @inheritdoc IFeeClaimer
    function activeBorrowMarkets(uint256 index) external view returns (address) {
        return _activeBorrowMarkets.at(index);
    }

    /// @notice Returns the number of active mint markets
    /// @return The number of active mint markets
    function activeMintMarketsLength() external view returns (uint256) {
        return _activeMintMarkets.length();
    }

    /// @notice Returns the number of active borrow markets
    /// @return The number of active borrow markets
    function activeBorrowMarketsLength() external view returns (uint256) {
        return _activeBorrowMarkets.length();
    }

    /// @inheritdoc IFeeClaimer
    function setFeeClaimer(address _claimer, bool _status) external onlyOwner {
        feeClaimer[_claimer] = _status;
        emit SetFeeClaimer(_claimer, _status);
    }

    /// @inheritdoc IFeeClaimer
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) {
            revert FeeClaimerInvalidInput();
        }

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc IFeeClaimer
    function setDusd(address _dusd) external onlyOwner {
        if (_dusd == address(0)) {
            revert FeeClaimerInvalidInput();
        }

        emit SetDusd(dusd, _dusd);
        dusd = _dusd;
    }

    /// @inheritdoc IFeeClaimer
    function updateMarkets(MarketType _marketType, address _market, bool _toAdd) external onlyOwner {
        EnumerableSet.AddressSet storage markets =
            _marketType == MarketType.MINT ? _activeMintMarkets : _activeBorrowMarkets;

        bool success = _toAdd ? markets.add(_market) : markets.remove(_market);

        if (!success) {
            revert FeeClaimerInvalidInput();
        }

        emit UpdateMarkets(_market, _marketType, _toAdd);
    }

    /// @inheritdoc IFeeClaimer
    function claimFees() external onlyOwnerOrFeeClaimer {
        // claims borrow tokens from borrow markets
        _claimBorrowTokenFromBorrowMarkets();

        // claims borrow tokens from mint markets
        _claimBorrowTokenFromMintMarkets();

        // claims collateral from Borrow markets and Mint markets
        _claimCollateral();
    }

    /// @inheritdoc IFeeClaimer
    function transferFees() external onlyOwnerOrFeeClaimer {
        // borrow token in borrow market and mint markets will be DUSD
        // transfers DUSD to fee recipient
        uint256 dusdBalance = IDUSD(dusd).balanceOf(address(this));
        if (dusdBalance > 0) {
            IDUSD(dusd).transfer(feeRecipient, dusdBalance);
        }

        // transfers collateral from Borrow markets to fee recipient
        uint256 borrowMarketsLen = _activeBorrowMarkets.length();
        for (uint256 i = 0; i < borrowMarketsLen; i++) {
            address collateralToken = IMarket(_activeBorrowMarkets.at(i)).collateralToken();
            uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));
            if (collateralBalance > 0) {
                IERC20(collateralToken).transfer(feeRecipient, collateralBalance);
            }
        }

        // transfers collateral from Mint markets to fee recipient
        uint256 mintMarketsLen = _activeMintMarkets.length();
        for (uint256 i = 0; i < mintMarketsLen; i++) {
            address collateralToken = IMarket(_activeMintMarkets.at(i)).collateralToken();
            uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));
            if (collateralBalance > 0) {
                IERC20(collateralToken).transfer(feeRecipient, collateralBalance);
            }
        }
    }

    /// @inheritdoc IFeeClaimer
    function claimableFees() external view returns (TokenBalance[] memory) {
        uint256 withdrawableDusd = 0;

        uint256 borrowMarketsLen = _activeBorrowMarkets.length();
        uint256 mintMarketsLen = _activeMintMarkets.length();

        // calculates total withdrawable DUSD from Borrow markets and mint markets
        for (uint256 i = 0; i < borrowMarketsLen; i++) {
            withdrawableDusd += _withdrawableBorrowTokenFromBorrowMarket(IMarket(_activeBorrowMarkets.at(i)));
        }
        for (uint256 i = 0; i < mintMarketsLen; i++) {
            withdrawableDusd += _withdrawableBorrowTokenFromMintMarket(AltoMintMarket(_activeMintMarkets.at(i)));
        }

        address[] memory distinctCollateralTokens = new address[](borrowMarketsLen + mintMarketsLen);

        uint256 distinctCollateralTokensCount = 0;

        // gets the distinct collateral tokens from Borrow markets and Mint markets
        for (uint256 i = 0; i < borrowMarketsLen; i++) {
            address collateralToken = IMarket(_activeBorrowMarkets.at(i)).collateralToken();
            if (!_containsElement(distinctCollateralTokens, distinctCollateralTokensCount, collateralToken)) {
                distinctCollateralTokens[distinctCollateralTokensCount] = collateralToken;
                distinctCollateralTokensCount++;
            }
        }
        for (uint256 i = 0; i < mintMarketsLen; i++) {
            address collateralToken = IMarket(_activeMintMarkets.at(i)).collateralToken();
            if (!_containsElement(distinctCollateralTokens, distinctCollateralTokensCount, collateralToken)) {
                distinctCollateralTokens[distinctCollateralTokensCount] = collateralToken;
                distinctCollateralTokensCount++;
            }
        }

        // creates a list of TokenBalance structs for the distinct collateral tokens
        // last element will be for DUSD, so we add 1 to the length
        TokenBalance[] memory collateralTokenPairs = new TokenBalance[](distinctCollateralTokensCount + 1);
        uint256 collateralTokenPairsCount = 0;

        // adds the collateral from Mint markets to the list
        for (uint256 i = 0; i < mintMarketsLen; i++) {
            address market = _activeMintMarkets.at(i);
            address collateralToken = IMarket(market).collateralToken();
            uint256 collateralToWithdraw = IMarket(market).position(address(this)).collateralAssets;
            bool found = false;

            for (uint256 j = 0; j < collateralTokenPairs.length; j++) {
                // if the collateral token is already in the list, update the balance
                if (collateralTokenPairs[j].token == collateralToken) {
                    collateralTokenPairs[j].balance += collateralToWithdraw;
                    found = true;
                    break;
                }
            }

            // if the collateral token is not in the list, add it to the list
            if (!found) {
                collateralTokenPairs[collateralTokenPairsCount] = TokenBalance(collateralToken, collateralToWithdraw);
                collateralTokenPairsCount++;
            }
        }

        // adds the collateral from Borrow markets to the list
        for (uint256 i = 0; i < borrowMarketsLen; i++) {
            address market = _activeBorrowMarkets.at(i);
            address collateralToken = IMarket(market).collateralToken();
            uint256 collateralToWithdraw = IMarket(market).position(address(this)).collateralAssets;
            bool found = false;
            for (uint256 j = 0; j < collateralTokenPairs.length; j++) {
                // if the collateral token is already in the list, update the balance
                if (collateralTokenPairs[j].token == collateralToken) {
                    collateralTokenPairs[j].balance += collateralToWithdraw;
                    found = true;
                    break;
                }
            }
            // if the collateral token is not in the list, add it to the list
            if (!found) {
                collateralTokenPairs[collateralTokenPairsCount] = TokenBalance(collateralToken, collateralToWithdraw);
                collateralTokenPairsCount++;
            }
        }

        // adds the DUSD to the list
        collateralTokenPairs[collateralTokenPairsCount] = TokenBalance(dusd, withdrawableDusd);

        return collateralTokenPairs;
    }

    /// @notice Claims the fees from Borrow markets
    function _claimBorrowTokenFromBorrowMarkets() internal {
        uint256 len = _activeBorrowMarkets.length();
        for (uint256 i = 0; i < len; i++) {
            IMarket market = IMarket(_activeBorrowMarkets.at(i));
            uint256 withdrawableBorrowAssets = _withdrawableBorrowTokenFromBorrowMarket(market);

            if (withdrawableBorrowAssets > 0) {
                market.removeSupply(withdrawableBorrowAssets, 0, address(this), address(this));
            }
        }
    }

    /// @notice Calculates the withdrawable borrow assets by this contract from a Borrow market
    /// @dev If due to high utilization rate, the withdrawable borrow assets is greater than the borrow token balance of the market,
    /// the withdrawable borrow assets is set to the borrow token balance of the market
    /// @param _borrowMarket The Borrow market to calculate the withdrawable borrow assets from
    /// @return The withdrawable borrow assets
    function _withdrawableBorrowTokenFromBorrowMarket(IMarket _borrowMarket) internal view returns (uint256) {
        uint256 borrowSupplyShares = _borrowMarket.position(address(this)).supplyShares;
        Balance memory totalSupply = _borrowMarket.totalSupply();

        uint256 withdrawableBorrowAssets =
            borrowSupplyShares.convertToAssetsDown(totalSupply.assets, totalSupply.shares);

        uint256 borrowTokenBalanceOfMarket = IERC20(_borrowMarket.borrowToken()).balanceOf(address(_borrowMarket));

        // this is to prevent the case where the withdrawable borrow assets is greater
        // than the borrow token balance of the market due to high utilization rate
        if (withdrawableBorrowAssets > borrowTokenBalanceOfMarket) {
            withdrawableBorrowAssets = borrowTokenBalanceOfMarket;
        }

        return withdrawableBorrowAssets;
    }

    /// @notice Claims the fees from Mint markets
    function _claimBorrowTokenFromMintMarkets() internal {
        uint256 len = _activeMintMarkets.length();
        for (uint256 i = 0; i < len; i++) {
            AltoMintMarket market = AltoMintMarket(_activeMintMarkets.at(i));
            uint256 withdrawableBorrowAssets = _withdrawableBorrowTokenFromMintMarket(market);

            if (withdrawableBorrowAssets > 0) {
                market.claimInterest(withdrawableBorrowAssets);
            }
        }
    }

    /// @notice Calculates the withdrawable borrow assets by this contract from a Mint market
    /// @dev If mint market doesn't have enough minting capacity,
    ///the withdrawable borrow assets is set to the mintable borrow assets
    /// @param _mintMarket The Mint market to calculate the withdrawable borrow assets from
    /// @return The withdrawable borrow assets
    function _withdrawableBorrowTokenFromMintMarket(AltoMintMarket _mintMarket) internal view returns (uint256) {
        uint256 withdrawableBorrowAssets = _mintMarket.claimableFeesAssets();

        (uint256 minted, uint256 ceiling) = IDUSD(dusd).minterConfig(address(_mintMarket));

        uint256 mintableBorrowAssets = ceiling - minted;

        // this is to prevent the case where the withdrawable borrow assets is greater
        // than the mintable borrow assets due to mint market not having enough minting capacity
        if (withdrawableBorrowAssets > mintableBorrowAssets) {
            withdrawableBorrowAssets = mintableBorrowAssets;
        }

        return withdrawableBorrowAssets;
    }

    /// @notice Claims the collateral from Borrow markets and Mint markets
    function _claimCollateral() internal {
        uint256 mintMarketsLen = _activeMintMarkets.length();
        for (uint256 i = 0; i < mintMarketsLen; i++) {
            address market = _activeMintMarkets.at(i);
            uint256 collateralToWithdraw = IMarket(market).position(address(this)).collateralAssets;
            if (collateralToWithdraw > 0) {
                IMarket(market).removeCollateral(collateralToWithdraw, address(this), address(this), "");
            }
        }

        uint256 borrowMarketsLen = _activeBorrowMarkets.length();
        for (uint256 i = 0; i < borrowMarketsLen; i++) {
            address market = _activeBorrowMarkets.at(i);
            uint256 collateralToWithdraw = IMarket(market).position(address(this)).collateralAssets;
            if (collateralToWithdraw > 0) {
                IMarket(market).removeCollateral(collateralToWithdraw, address(this), address(this), "");
            }
        }
    }

    /// @notice Checks if the element is in the array (only checks up to `length` elements)
    /// @dev Used for building distinct collateral token list in claimableFees view function
    /// @param _array The array to check
    /// @param _length The number of elements to check
    /// @param _element The element to check
    /// @return Whether the element is in the array
    function _containsElement(address[] memory _array, uint256 _length, address _element) internal pure returns (bool) {
        for (uint256 i = 0; i < _length; i++) {
            if (_array[i] == _element) {
                return true;
            }
        }
        return false;
    }
}
