// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAdvancedPermissionsUsmFeeStrategy} from "./interfaces/IAdvancedPermissionsUsmFeeStrategy.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AdvancedPermissionsFeeStrategy
 * @author GPM
 * @author Adapted from Aave (https://github.com/aave/gho-core/)
 * @custom:contact security@altofoundation.org
 * @notice Fee strategy to calculate buy/sell fees for Advanced Permissions USMs.
 * @dev Per-direction fee resolution (buy vs sell) uses the same precedence: address override, then fee-only user
 *      role mapping, then the contract default (`_buyFee` / `_sellFee`).
 */
contract AdvancedPermissionsFeeStrategy is IAdvancedPermissionsUsmFeeStrategy, AccessControl {
    using Math for uint256;

    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    uint256 internal constant PERCENTAGE_PRECISION = 10000;

    uint256 internal constant MAXIMUM_FEE_PERCENT = 5000;

    /// @dev default buy fee
    uint256 internal _buyFee;
    /// @dev default sell fee
    uint256 internal _sellFee;
    /// @dev overridden buy fee for a specific originator
    mapping(address => OverriddenFeeData) internal _overrideBuyFee;
    /// @dev overridden sell fee for a specific originator
    mapping(address => OverriddenFeeData) internal _overrideSellFee;
    /// @dev buy fee for a specific role hash
    mapping(bytes32 roleHash => OverriddenFeeData) internal _buyFeeByRoleHash;
    /// @dev sell fee for a specific role hash
    mapping(bytes32 roleHash => OverriddenFeeData) internal _sellFeeByRoleHash;
    /// @dev buy fee-only role assigned per user; has no access-control effect
    mapping(address => bytes32) internal _userBuyFeeRole;
    /// @dev sell fee-only role assigned per user; has no access-control effect
    mapping(address => bytes32) internal _userSellFeeRole;

    /**
     * @dev Constructor
     * @dev Fees must be lower than 5000 bps (e.g. 50.00%)
     * @param buyFee The fee paid when buying the underlying asset in exchange for Stable Token, expressed in bps
     * @param sellFee The fee paid when selling the underlying asset in exchange for Stable Token, expressed in bps
     * @param admin The address of the admin who can configure the fee strategy
     */
    constructor(uint256 buyFee, uint256 sellFee, address admin) {
        require(buyFee < MAXIMUM_FEE_PERCENT, "INVALID_BUY_FEE");
        require(sellFee < MAXIMUM_FEE_PERCENT, "INVALID_SELL_FEE");
        require(admin != address(0), "ZERO_ADDRESS_NOT_VALID");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CONFIGURATOR_ROLE, admin);
        _buyFee = buyFee;
        _sellFee = sellFee;
        emit FeeSet(0, buyFee, 0, sellFee);
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function setFee(uint256 buyFee, uint256 sellFee) external onlyRole(CONFIGURATOR_ROLE) {
        require(buyFee < MAXIMUM_FEE_PERCENT, "INVALID_BUY_FEE");
        require(sellFee < MAXIMUM_FEE_PERCENT, "INVALID_SELL_FEE");
        emit FeeSet(_buyFee, buyFee, _sellFee, sellFee);
        _buyFee = buyFee;
        _sellFee = sellFee;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function overrideBuyFee(address originator, OverriddenFeeData memory overriddenFeeData)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        if (overriddenFeeData.isOverridden) {
            require(overriddenFeeData.fee < MAXIMUM_FEE_PERCENT, "INVALID_BUY_FEE");
        }
        emit OverrideBuyFeeSet(originator, overriddenFeeData);
        _overrideBuyFee[originator] = overriddenFeeData;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function overrideSellFee(address originator, OverriddenFeeData memory overriddenFeeData)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        if (overriddenFeeData.isOverridden) {
            require(overriddenFeeData.fee < MAXIMUM_FEE_PERCENT, "INVALID_SELL_FEE");
        }
        emit OverrideSellFeeSet(originator, overriddenFeeData);
        _overrideSellFee[originator] = overriddenFeeData;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function setBuyFeeByRoleHash(bytes32 roleHash, OverriddenFeeData memory overriddenFeeData)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        require(roleHash != bytes32(0), "INVALID_ROLE_HASH");
        if (overriddenFeeData.isOverridden) {
            require(overriddenFeeData.fee < MAXIMUM_FEE_PERCENT, "INVALID_BUY_FEE");
        }
        emit BuyFeeByRoleHashSet(roleHash, overriddenFeeData);
        _buyFeeByRoleHash[roleHash] = overriddenFeeData;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function setSellFeeByRoleHash(bytes32 roleHash, OverriddenFeeData memory overriddenFeeData)
        external
        onlyRole(CONFIGURATOR_ROLE)
    {
        require(roleHash != bytes32(0), "INVALID_ROLE_HASH");
        if (overriddenFeeData.isOverridden) {
            require(overriddenFeeData.fee < MAXIMUM_FEE_PERCENT, "INVALID_SELL_FEE");
        }
        emit SellFeeByRoleHashSet(roleHash, overriddenFeeData);
        _sellFeeByRoleHash[roleHash] = overriddenFeeData;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function setUserBuyFeeRole(address originator, bytes32 feeRole) external onlyRole(CONFIGURATOR_ROLE) {
        emit UserBuyFeeRoleSet(originator, feeRole);
        _userBuyFeeRole[originator] = feeRole;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function setUserSellFeeRole(address originator, bytes32 feeRole) external onlyRole(CONFIGURATOR_ROLE) {
        emit UserSellFeeRoleSet(originator, feeRole);
        _userSellFeeRole[originator] = feeRole;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getUserBuyFeeRole(address originator) external view returns (bytes32) {
        return _userBuyFeeRole[originator];
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getUserSellFeeRole(address originator) external view returns (bytes32) {
        return _userSellFeeRole[originator];
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getDefaultBuyFee() external view returns (uint256) {
        return _buyFee;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getDefaultSellFee() external view returns (uint256) {
        return _sellFee;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getBuyFeeForUser(address originator) public view returns (uint256) {
        OverriddenFeeData storage overrideFee = _overrideBuyFee[originator];
        if (overrideFee.isOverridden) {
            return overrideFee.fee;
        }
        OverriddenFeeData storage roleFee = _buyFeeByRoleHash[_userBuyFeeRole[originator]];
        if (roleFee.isOverridden) {
            return roleFee.fee;
        }
        return _buyFee;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getSellFeeForUser(address originator) public view returns (uint256) {
        OverriddenFeeData storage overrideFee = _overrideSellFee[originator];
        if (overrideFee.isOverridden) {
            return overrideFee.fee;
        }
        OverriddenFeeData storage roleFee = _sellFeeByRoleHash[_userSellFeeRole[originator]];
        if (roleFee.isOverridden) {
            return roleFee.fee;
        }
        return _sellFee;
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getBuyFee(uint256 grossAmount, address originator) external view returns (uint256) {
        uint256 fee = getBuyFeeForUser(originator);
        return grossAmount.mulDiv(fee, PERCENTAGE_PRECISION, Math.Rounding.Ceil);
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getSellFee(uint256 grossAmount, address originator) external view returns (uint256) {
        uint256 fee = getSellFeeForUser(originator);
        return grossAmount.mulDiv(fee, PERCENTAGE_PRECISION, Math.Rounding.Ceil);
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getGrossAmountFromTotalBought(uint256 totalAmount, address originator) external view returns (uint256) {
        uint256 fee = getBuyFeeForUser(originator);
        if (totalAmount == 0) {
            return 0;
        } else if (fee == 0) {
            return totalAmount;
        } else {
            return totalAmount.mulDiv(PERCENTAGE_PRECISION, PERCENTAGE_PRECISION + fee, Math.Rounding.Floor);
        }
    }

    /// @inheritdoc IAdvancedPermissionsUsmFeeStrategy
    function getGrossAmountFromTotalSold(uint256 totalAmount, address originator) external view returns (uint256) {
        uint256 fee = getSellFeeForUser(originator);
        if (totalAmount == 0) {
            return 0;
        } else if (fee == 0) {
            return totalAmount;
        } else {
            return totalAmount.mulDiv(PERCENTAGE_PRECISION, PERCENTAGE_PRECISION - fee, Math.Rounding.Ceil);
        }
    }
}
