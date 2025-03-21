//SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {Test, console} from "forge-std/Test.sol";
import {Swapper} from "../src/Swapper.sol";
import {Nft} from "../src/NFT-Swap.sol";

contract SwapTest is Test {
    Nft nft;
    Swapper swapper;
    address user1 = address(123);
    address user2 = address(234);
    address user3 = address(456);

    Swapper.RequestIn swapRequest1;

    function setUp() public {
        nft = new Nft();
        swapper = new Swapper();
    }

    function _requestSwap(
        address _requestee,
        address _ownedNft,
        address _requestedNft,
        uint256 _ownedTokenId,
        uint256 _requestedTokenId
    ) internal {
        swapRequest1.requestee = _requestee;
        swapRequest1.ownedNft = _ownedNft;
        swapRequest1.requestedNft = _requestedNft;
        swapRequest1.requestedNftId = _requestedTokenId;
        swapRequest1.ownedNftId = _ownedTokenId;
        swapper.requestNftSwap(swapRequest1);
    }

    function _mintFromCollection() internal {
        nft.mint();
    }

    function testRequestSwapAndAccept() public {
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
        vm.startPrank(user2);
        nft.approve(address(swapper), 2);
        swapper.acceptRequest(swapper.fetchInbox(user2)[0].requestId);
        vm.stopPrank();
        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.ownerOf(2), user1);
        assertEq(swapper.fetchInbox(user2).length, 0);
        assertEq(swapper.fetchOutbox(user1).length, 0);
        assertEq(swapper.fetchAccepted(user2).length, 1);
        assertEq(swapper.fetchAccepted(user1).length, 1);
    }

    function testRequestSwapAndReject() public {
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
        vm.startPrank(user2);
        swapper.rejectRequest(swapper.fetchInbox(user2)[0].requestId);
        vm.stopPrank();
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user2);
        assertEq(swapper.fetchInbox(user2).length, 0);
        assertEq(swapper.fetchOutbox(user1).length, 0);
        assertEq(swapper.fetchRejected(user2).length, 1);
        assertEq(swapper.fetchRejected(user1).length, 1);
    }

    function testRevertRequestNFtSwapWhenEitherPartyDontHaveNft() public {
        vm.prank(user1);
        _mintFromCollection();
        vm.prank(user3);
        _mintFromCollection();
        vm.prank(user1);
        assertEq(nft.ownerOf(1), user1);
        vm.prank(user2);
        swapper.approve(user1);
        vm.prank(user1);
        nft.approve(address(swapper), 1);
        vm.prank(user1);
        vm.expectRevert();
        _requestSwap(user2, address(nft), address(nft), 1, 2);
    }

    function testRevertWhenPartyBTransferNftAmidstSwap() public {
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
        vm.startPrank(user2);
        nft.transferFrom(user2, user3, 2);
        swapper.acceptRequest(1);
        vm.stopPrank();
        assertEq(nft.ownerOf(1), user1);
        assertEq(swapper.fetchInbox(user2).length, 0);
        assertEq(swapper.fetchOutbox(user1).length, 0);
        assertEq(swapper.fetchCanceled(user2).length, 1);
        assertEq(swapper.fetchCanceled(user1).length, 1);
    }

    function testCancelRequest() public {
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
        assertEq(swapper.fetchInbox(user2).length, 1);
        assertEq(swapper.fetchOutbox(user1).length, 1);
        vm.startPrank(user1);
        Swapper.Request memory requestToCancel = swapper.fetchOutbox(user1)[0];
        swapper.cancelRequest(requestToCancel.requestee, requestToCancel.requestId);
        vm.stopPrank();
        assertEq(nft.ownerOf(1), user1);
        assertEq(swapper.fetchInbox(user2).length, 0);
        assertEq(swapper.fetchInbox(user1).length, 0);
        assertEq(swapper.fetchCanceled(user2).length, 1);
        assertEq(swapper.fetchCanceled(user1).length, 1);
    }

    function testRevertRevokeApproval() public {
        vm.startPrank(user1);
        _mintFromCollection();
        _mintFromCollection();
        vm.stopPrank();
        vm.startPrank(user2);
        _mintFromCollection();
        _mintFromCollection();
        vm.stopPrank();
        vm.prank(user1);
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user1);
        assertEq(nft.ownerOf(3), user2);
        assertEq(nft.ownerOf(4), user2);
        vm.prank(user2);
        swapper.approve(user1);
        vm.startPrank(user1);
        nft.approve(address(swapper), 1);
        nft.approve(address(swapper), 2);
        vm.stopPrank();
        vm.prank(user1);
        _requestSwap(user2, address(nft), address(nft), 1, 3);
        vm.prank(user2);
        swapper.revokeApproval(user1);
        vm.expectRevert();
        vm.prank(user1);
        _requestSwap(user2, address(nft), address(nft), 2, 4);
    }

    function testRejectAll() public {
        vm.startPrank(user1);
        _mintFromCollection();
        _mintFromCollection();
        _mintFromCollection();
        _mintFromCollection();
        vm.stopPrank();
        vm.startPrank(user2);
        _mintFromCollection();
        _mintFromCollection();
        _mintFromCollection();
        _mintFromCollection();
        vm.stopPrank();
        vm.prank(user2);
        swapper.approve(user1);
        vm.startPrank(user1);
        nft.approve(address(swapper), 1);
        nft.approve(address(swapper), 2);
        nft.approve(address(swapper), 3);
        nft.approve(address(swapper), 4);
        vm.stopPrank();
        vm.startPrank(user1);
        _requestSwap(user2, address(nft), address(nft), 1, 5);
        _requestSwap(user2, address(nft), address(nft), 2, 6);
        _requestSwap(user2, address(nft), address(nft), 3, 7);
        _requestSwap(user2, address(nft), address(nft), 4, 8);
        vm.stopPrank();
        assertEq(swapper.fetchInbox(user2).length, 4);
        vm.startPrank(user2);
        nft.approve(address(swapper), 5);
        swapper.acceptRequest(1);
        swapper.rejectRequest(2);
        swapper.fetchOutbox(user1);
        swapper.rejectAll();
        vm.stopPrank();
        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.ownerOf(2), user1);
        assertEq(swapper.fetchInbox(user2).length, 0);
        assertEq(swapper.fetchOutbox(user1).length, 0);
        assertEq(swapper.fetchAccepted(user2).length, 1);
        assertEq(swapper.fetchRejected(user2).length, 1);
    }
}
