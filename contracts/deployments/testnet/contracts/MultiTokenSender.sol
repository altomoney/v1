// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MultiTokenSender is Ownable {
    mapping(address => bool) public whitelist;

    event TokensSent(address[] tokens, address recipient, uint256[] amounts);
    event WhitelistUpdated(address account, bool status);

    constructor(address _owner) Ownable(_owner) {
        whitelist[_owner] = true;
    }

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "Caller is not whitelisted");
        _;
    }

    function updateWhitelist(address _account, bool _status) external onlyOwner {
        whitelist[_account] = _status;
        emit WhitelistUpdated(_account, _status);
    }

    function sendTokens(address[] calldata _tokens, address _recipient, uint256[] calldata _amounts)
        external
        payable
        onlyWhitelisted
    {
        require(_tokens.length == _amounts.length, "Tokens and amounts arrays must have the same length");
        require(_recipient != address(0), "Invalid recipient address");

        uint256 totalEthNeeded;

        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint256 amount = _amounts[i];
            require(amount > 0, "Amount must be greater than 0");

            if (token == address(0)) {
                // Handle ETH transfer
                totalEthNeeded += amount;
            } else {
                // Handle ERC20 transfer
                IERC20 tokenContract = IERC20(token);
                uint256 contractBalance = tokenContract.balanceOf(address(this));
                require(contractBalance >= amount, "Insufficient token balance in contract");
                require(tokenContract.transfer(_recipient, amount), "Token transfer failed");
            }
        }

        // Handle accumulated ETH transfers
        if (totalEthNeeded > 0) {
            require(msg.value == totalEthNeeded, "Incorrect ETH amount sent");
            (bool success,) = _recipient.call{value: totalEthNeeded}("");
            require(success, "ETH transfer failed");
        } else if (msg.value > 0) {
            revert("ETH sent but no ETH transfers requested");
        }

        emit TokensSent(_tokens, _recipient, _amounts);
    }

    function getContractBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}
