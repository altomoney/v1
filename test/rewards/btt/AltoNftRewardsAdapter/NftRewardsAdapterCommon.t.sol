// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AltoNftRewardsAdapter} from "@alto/rewards/adapters/AltoNftRewardsAdapter.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockPearlClubNft is ERC721 {
    uint256 private _currentTokenId = 1;

    constructor() ERC721("Pearl Club NFT", "PEARL") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function mintRange(address to, uint256 startId, uint256 endId) external {
        for (uint256 i = startId; i <= endId; i++) {
            _mint(to, i);
        }
    }
}

abstract contract NftRewardsAdapterCommon is Test {
    AltoNftRewardsAdapter public adapter;
    MockPearlClubNft public pearlClubNft;

    address public constant OWNER = address(0x1);
    address public constant ALICE = address(0x2);
    address public constant BOB = address(0x3);
    address public constant CHARLIE = address(0x4);

    uint256 public constant INITIAL_BONUS_DISCOUNT = 0.05 ether; // 5%
    uint256 public constant INITIAL_PAYMENT_TOKEN_SHARE = 0.03 ether; // 3%

    function setUp() public virtual {
        // Deploy mock NFT contract
        pearlClubNft = new MockPearlClubNft();

        // Mint some NFTs for testing
        pearlClubNft.mint(ALICE, 1);
        pearlClubNft.mint(BOB, 2);
        pearlClubNft.mint(CHARLIE, 3);
        pearlClubNft.mintRange(OWNER, 4, 700); // Owner has multiple NFTs

        // Deploy adapter contract
        vm.prank(OWNER);
        adapter = new AltoNftRewardsAdapter(address(pearlClubNft), INITIAL_BONUS_DISCOUNT, INITIAL_PAYMENT_TOKEN_SHARE);
    }
}
