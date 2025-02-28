// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ERC20PermitStruct} from "tap-token/tokens/ITapToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {
    SendParam,
    MessagingFee,
    MessagingReceipt,
    OFTReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

contract ERC20Mock is ERC20Permit {
    constructor() ERC20("ERC-20C Mock", "MOCK") ERC20Permit("ERC-20C Mock") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function combineOptions(uint32, uint16, bytes calldata) external pure returns (bytes memory) {
        return "0x";
    }

    function quoteSendPacket(
        SendParam calldata,
        bytes calldata,
        bool,
        bytes calldata,
        bytes calldata /*_oftCmd*/ // @dev unused in the default implementation.
    ) external pure returns (MessagingFee memory msgFee) {
        return MessagingFee({lzTokenFee: 0, nativeFee: 0});
    }

    function getTypedDataHash(ERC20PermitStruct calldata _permitData) public view returns (bytes32) {
        bytes32 permitTypeHash_ =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

        bytes32 structHash_ = keccak256(
            abi.encode(
                permitTypeHash_,
                _permitData.owner,
                _permitData.spender,
                _permitData.value,
                _permitData.nonce,
                _permitData.deadline
            )
        );
        return _hashTypedDataV4(structHash_);
    }
}
