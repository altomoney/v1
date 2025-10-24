// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IMarket, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AltoMintMarket} from "@alto/lending/AltoMintMarket.sol";
import {IDUSD} from "@alto/tokens/interfaces/IDUSD.sol";
import {IFeeClaimer, MarketType, TokenBalance} from "@alto/utils/interfaces/IFeeClaimer.sol";

/// @title FeeClaimer
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice A contract that claims fees and collateral from Mint markets and Borrow markets
contract FeeClaimer is Ownable2Step, IFeeClaimer {
    using AssetShareConversionMath for uint256;

    /// @inheritdoc IFeeClaimer
    mapping(address => bool) public feeClaimer;

    /// @inheritdoc IFeeClaimer
    address[] public activeMintMarkets;

    /// @inheritdoc IFeeClaimer
    address[] public activeBorrowMarkets;

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
        for (uint256 i = 0; i < activeBorrowMarkets.length; i++) {
            address collateralToken = IMarket(activeBorrowMarkets[i]).collateralToken();
            uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));
            if (collateralBalance > 0) {
                IERC20(collateralToken).transfer(feeRecipient, collateralBalance);
            }
        }

        // transfers collateral from Mint markets to fee recipient
        for (uint256 i = 0; i < activeMintMarkets.length; i++) {
            address collateralToken = IMarket(activeMintMarkets[i]).collateralToken();
            uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(this));
            if (collateralBalance > 0) {
                IERC20(collateralToken).transfer(feeRecipient, collateralBalance);
            }
        }
    }

    /// @inheritdoc IFeeClaimer
    function claimableFees() external view returns (TokenBalance[] memory) {
        uint256 withdrawableDusd = 0;

        // calculates total withdrawable DUSD from Borrow markets and mint markets
        for (uint256 i = 0; i < activeBorrowMarkets.length; i++) {
            withdrawableDusd += _withdrawableBorrowTokenFromBorrowMarket(IMarket(activeBorrowMarkets[i]));
        }
        for (uint256 i = 0; i < activeMintMarkets.length; i++) {
            withdrawableDusd += _withdrawableBorrowTokenFromMintMarket(AltoMintMarket(activeMintMarkets[i]));
        }

        address[] memory distinctCollateralTokens = new address[](activeBorrowMarkets.length + activeMintMarkets.length);

        uint256 distinctCollateralTokensCount = 0;

        // gets the distinct collateral tokens from Borrow markets and Mint markets
        for (uint256 i = 0; i < activeBorrowMarkets.length; i++) {
            address collateralToken = IMarket(activeBorrowMarkets[i]).collateralToken();
            if (!_containsElement(distinctCollateralTokens, collateralToken)) {
                distinctCollateralTokens[distinctCollateralTokensCount] = collateralToken;
                distinctCollateralTokensCount++;
            }
        }
        for (uint256 i = 0; i < activeMintMarkets.length; i++) {
            address collateralToken = IMarket(activeMintMarkets[i]).collateralToken();
            if (!_containsElement(distinctCollateralTokens, collateralToken)) {
                distinctCollateralTokens[distinctCollateralTokensCount] = collateralToken;
                distinctCollateralTokensCount++;
            }
        }

        // creates a list of TokenBalance structs for the distinct collateral tokens
        // last element will be for DUSD, so we add 1 to the length
        TokenBalance[] memory collateralTokenPairs = new TokenBalance[](distinctCollateralTokensCount + 1);
        uint256 collateralTokenPairsCount = 0;

        // adds the collateral from Mint markets to the list
        for (uint256 i = 0; i < activeMintMarkets.length; i++) {
            address collateralToken = IMarket(activeMintMarkets[i]).collateralToken();
            uint256 collateralToWithdraw = IMarket(activeMintMarkets[i]).position(address(this)).collateralAssets;
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
        for (uint256 i = 0; i < activeBorrowMarkets.length; i++) {
            address collateralToken = IMarket(activeBorrowMarkets[i]).collateralToken();
            uint256 collateralToWithdraw = IMarket(activeBorrowMarkets[i]).position(address(this)).collateralAssets;
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
        for (uint256 i = 0; i < activeBorrowMarkets.length; i++) {
            uint256 withdrawableBorrowAssets = _withdrawableBorrowTokenFromBorrowMarket(IMarket(activeBorrowMarkets[i]));

            if (withdrawableBorrowAssets > 0) {
                IMarket(activeBorrowMarkets[i]).removeSupply(withdrawableBorrowAssets, 0, address(this), address(this));
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
        for (uint256 i = 0; i < activeMintMarkets.length; i++) {
            uint256 withdrawableBorrowAssets =
                _withdrawableBorrowTokenFromMintMarket(AltoMintMarket(activeMintMarkets[i]));

            if (withdrawableBorrowAssets > 0) {
                AltoMintMarket(activeMintMarkets[i]).claimInterest(withdrawableBorrowAssets);
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
        for (uint256 i = 0; i < activeMintMarkets.length; i++) {
            uint256 collateralToWithdraw = IMarket(activeMintMarkets[i]).position(address(this)).collateralAssets;
            if (collateralToWithdraw > 0) {
                IMarket(activeMintMarkets[i]).removeCollateral(collateralToWithdraw, address(this), address(this), "");
            }
        }

        for (uint256 i = 0; i < activeBorrowMarkets.length; i++) {
            uint256 collateralToWithdraw = IMarket(activeBorrowMarkets[i]).position(address(this)).collateralAssets;
            if (collateralToWithdraw > 0) {
                IMarket(activeBorrowMarkets[i]).removeCollateral(collateralToWithdraw, address(this), address(this), "");
            }
        }
    }

    /// @inheritdoc IFeeClaimer
    function updateMarkets(MarketType _marketType, address _market, bool _toAdd) external onlyOwner {
        address[] storage markets = _marketType == MarketType.MINT ? activeMintMarkets : activeBorrowMarkets;

        if (_toAdd) {
            if (_containsElement(markets, _market)) {
                revert FeeClaimerInvalidInput();
            }
            markets.push(_market);
        } else {
            if (!_containsElement(markets, _market)) {
                revert FeeClaimerInvalidInput();
            }
            _removeElement(markets, _market);
        }

        emit UpdateMarkets(_market, _marketType, _toAdd);
    }

    /// @notice Checks if the market is already in the list
    /// @param _array The array to check
    /// @param _element The element to check
    /// @return Whether the element is already in the array
    function _containsElement(address[] memory _array, address _element) internal pure returns (bool) {
        for (uint256 i = 0; i < _array.length; i++) {
            if (_array[i] == _element) {
                return true;
            }
        }
        return false;
    }

    /// @notice Removes the market from the list
    /// @dev Noop if the market is not in the list
    /// @param _array The array to remove the element from
    /// @param _element The element to remove
    function _removeElement(address[] storage _array, address _element) internal {
        uint256 length = _array.length;
        for (uint256 i = 0; i < length; i++) {
            if (_array[i] == _element) {
                _array[i] = _array[length - 1];
                _array.pop();
                return;
            }
        }
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
}
