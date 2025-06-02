//SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import {ERC721} from "@openzeppelin/token/ERC721/ERC721.sol";

contract Nft is ERC721("NFT", "NFT") {
    uint256 tokenId;

    function mint() external returns (uint256) {
        tokenId += 1;
        _safeMint(msg.sender, tokenId);
        return tokenId;
    }
}
