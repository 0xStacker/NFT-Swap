//SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {Test, console} from "forge-std/Test.sol";
import {Swapper} from "../src/Swapper.sol";
import {Nft} from "../src/NFT-Swap.sol";

contract SwapTest is Test{
    Nft nft;
    Swapper swapper;
    address user1 = address(123);
    address user2 = address(234);
    address user3 = address(456);

    Swapper.RequestIn swapRequest1; 
    function setUp() public{
        nft = new Nft();
        swapper = new Swapper();
    }

    function _requestSwap(address _requestee, address _ownedNft, address _requestedNft,
     uint _ownedTokenId, uint _requestedTokenId) internal{
        swapRequest1.requestee = _requestee;
        swapRequest1.ownedNft = _ownedNft;
        swapRequest1.requestedNft = _requestedNft;
        swapRequest1.requestedNftId = _requestedTokenId;
        swapRequest1.ownedNftId = _ownedTokenId;
        swapper.requestNftSwap(swapRequest1);
    }

    function _mintFromCollection() internal{
        nft.mint();
    }

    function testRequestSwap() public{
        vm.prank(user1);
        _mintFromCollection();
        vm.prank(user2);
        _mintFromCollection();
        vm.prank(user1);
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user2);
        vm.prank(user2);
        swapper.approve(user1);
        vm.prank(user1);
        nft.approve(address(swapper), 1);
        vm.prank(user1);
        _requestSwap(user2, address(nft), address(nft), 1, 2);
        assertEq(nft.ownerOf(1), address(swapper));
        assertEq(swapper.fetchInbox(user2).length, 1);
    }
}