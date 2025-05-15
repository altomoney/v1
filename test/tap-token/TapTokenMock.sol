// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Tapioca
import {ITapToken} from "tap-token/tokens/ITapToken.sol";
import {TapToken} from "tap-token/tokens/TapToken.sol";
import {ERC20PermitStruct} from "tap-utils/interfaces/common/ICommonData.sol";

contract TapTokenMock is TapToken {
    constructor(ITapToken.TapTokenConstructorData memory _data) TapToken(_data) {}

    function freeMint(address _to, uint256 _amount) external virtual {
        _mint(_to, _amount);
    }

    /**
     * @dev Returns the hash of the struct used by the permit function.
     * @param _permitData Struct containing permit data.
     */
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
