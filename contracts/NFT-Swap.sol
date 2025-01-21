//SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol";

contract Nft is ERC721("NFT", "NFT"){
    uint tokenId = 1;
    
    function mint() external {
        _safeMint(msg.sender, tokenId);
        tokenId += 1;
    }

}
