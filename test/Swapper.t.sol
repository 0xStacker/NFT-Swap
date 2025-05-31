//SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {Test, console} from "forge-std/Test.sol";
import {SworpV1} from "../src/v1/Sworp.sol";
import {Nft} from "./testNft.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SwapTest is Test {
    Nft nft;
    Nft nft2;
    SworpV1 swapper;
    TransparentUpgradeableProxy proxy;
    address user1 = address(123);
    address user2 = address(234);
    address user3 = address(456);
    uint8 minted;
    SworpV1.FungibleToken token;
    address[] _ownedNfts;
    address[] _requestedNfts;
    uint256[] _ownedNftIds;
    uint256[] _requestedNftIds;

    address[] _ownedNfts2;
    address[] _requestedNfts2;
    uint256[] _ownedNftIds2;
    uint256[] _requestedNftIds2;

    address[] _ownedNfts3;
    address[] _requestedNfts3;
    uint256[] _ownedNftIds3;
    uint256[] _requestedNftIds3;

    SworpV1.RequestIn swapRequest1;

    enum actor {
        REQUESTER,
        REQUESTEE
    }

    function setUp() public {
        nft = new Nft();
        nft2 = new Nft();
        swapper = new SworpV1();
        proxy = new TransparentUpgradeableProxy(
            address(swapper), address(this), abi.encodeWithSignature("initialize(address)", address(this))
        );
        swapper = SworpV1(payable(address(proxy)));
    }

    function testImplementationAdmin() public view {
        assertEq(swapper.admin(), address(this), "Admin should be the deployer");
    }

    function _requestSwap(
        address _requestee,
        address[] memory _ownedNft,
        address[] memory _requestedNft,
        uint256[] memory _ownedTokenId,
        uint256[] memory _requestedTokenId,
        SworpV1.FungibleToken memory _token
    ) internal {
        swapRequest1.fulfiller = _requestee;
        swapRequest1.ownedNfts = _ownedNft;
        swapRequest1.requestedNfts = _requestedNft;
        swapRequest1.ownedNftIds = _ownedTokenId;
        swapRequest1.requestedNftIds = _requestedTokenId;
        swapRequest1.token = _token;
        swapper.createSwapOrder{value: 0.1 ether}(swapRequest1);
    }

    function _mintFromCollection1() internal {
        nft.mint();
    }

    function _mintFromCollection2() internal {
        nft2.mint();
    }

    function approveSwapper(address _user, actor _actor) internal {
        vm.startPrank(_user);
        if (_actor == actor.REQUESTER) {
            for (uint256 i; i < _ownedNfts.length; i++) {
                nft.approve(address(swapper), _ownedNftIds[i]);
            }
        } else {
            for (uint256 i; i < _requestedNfts2.length; i++) {
                nft2.approve(address(swapper), _requestedNftIds2[i]);
            }
        }
        vm.stopPrank();
    }

    function testRequestSwap() public {
        // Requester Mint
        vm.prank(user1);
        _mintFromCollection1();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);

        // Requestee Mint
        vm.prank(user2);
        _mintFromCollection2();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(minted);

        // Requestee approves requester
        vm.prank(user2);
        swapper.sworpApprove(user1);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER);

        // Create swap order
        hoax(user1, 1 ether);
        _requestSwap(user2, _ownedNfts, _requestedNfts2, _ownedNftIds, _requestedNftIds2, token);

        // Verify swap order
        assertEq(nft.ownerOf(1), address(swapper));
        assertEq(swapper.fetchOrderInbox(user2).length, 1);
        assertEq(swapper.fetchOrderOutbox(user1).length, 1);
    }

    function testRequestSwapAndAccept() public {
        clearNftData();
        // Requester Mint
        vm.prank(user1);
        _mintFromCollection1();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);

        // Requestee Mint
        vm.prank(user2);
        _mintFromCollection2();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(minted);

        // Requestee approves requester
        vm.prank(user2);
        swapper.sworpApprove(user1);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER);

        // Create swap order
        hoax(user1, 1 ether);
        _requestSwap(user2, _ownedNfts, _requestedNfts2, _ownedNftIds, _requestedNftIds2, token);
        assertEq(nft.ownerOf(1), address(swapper));

        // Fufil swap order
        approveSwapper(user2, actor.REQUESTEE);
        vm.startPrank(user2);
        swapper.fufilSwapOrder(swapper.fetchOrderInbox(user2)[0]);
        vm.stopPrank();
        // Verify swap order
        assertEq(nft.ownerOf(1), user2);
        assertEq(nft2.ownerOf(1), user1);
        assertEq(swapper.fetchOrderInbox(user2).length, 0);
        assertEq(swapper.fetchOrderOutbox(user1).length, 0);
        assertEq(swapper.fetchAcceptedOrders(user2).length, 1);
        assertEq(swapper.fetchAcceptedOrders(user1).length, 1);
    }

    function testRequestSwapAndReject() public {
        clearNftData();

        // Requester Mint
        vm.prank(user1);
        _mintFromCollection1();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);

        // Requestee Mint
        vm.prank(user2);
        _mintFromCollection2();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(minted);

        // Requestee approves requester
        vm.prank(user2);
        swapper.sworpApprove(user1);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER);

        // Create swap order
        hoax(user1, 1 ether);
        _requestSwap(user2, _ownedNfts, _requestedNfts2, _ownedNftIds, _requestedNftIds2, token);
        assertEq(nft.ownerOf(1), address(swapper));

        // Fufil swap order
        vm.startPrank(user2);
        swapper.rejectOrder(swapper.fetchOrderInbox(user2)[0]);
        vm.stopPrank();

        // Verify swap order
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft2.ownerOf(1), user2);
        assertEq(swapper.fetchRejectedOrders(user2).length, 1);
        assertEq(swapper.fetchRejectedOrders(user1).length, 1);
    }

    function testRevertWhenPartyBTransferNftAmidstSwap() public {
        clearNftData();
        // Requester Mint
        vm.prank(user1);
        _mintFromCollection1();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);
        // Requestee Mint
        vm.prank(user2);
        _mintFromCollection2();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(minted);

        // Requestee approves requester
        vm.prank(user2);
        swapper.sworpApprove(user1);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER);

        hoax(user1, 1 ether);
        _requestSwap(user2, _ownedNfts, _requestedNfts2, _ownedNftIds, _requestedNftIds2, token);
        assertEq(nft.ownerOf(1), address(swapper));
        assertEq(swapper.fetchOrderInbox(user2).length, 1);

        // User 2 transfers NFT 2 to user 3
        vm.startPrank(user2);
        nft2.transferFrom(user2, user3, 1);

        // User 2 attempts to fufil swap order
        swapper.fufilSwapOrder(swapper.fetchOrderInbox(user2)[0]);
        vm.stopPrank();

        // Verify swap order
        assertEq(nft.ownerOf(1), user1);
        assertEq(swapper.fetchOrderInbox(user2).length, 0);
        assertEq(swapper.fetchOrderOutbox(user1).length, 0);
        assertEq(swapper.fetchCanceledOrders(user2).length, 1);
        assertEq(swapper.fetchCanceledOrders(user1).length, 1);
    }

    function testCancelRequest() public {
        clearNftData();
        // Requester Mint
        vm.prank(user1);
        _mintFromCollection1();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);

        // Requestee Mint
        vm.prank(user2);
        _mintFromCollection2();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(minted);

        // Requestee approves requester
        vm.prank(user2);
        swapper.sworpApprove(user1);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER);

        // Create swap order
        hoax(user1, 1 ether);
        _requestSwap(user2, _ownedNfts, _requestedNfts2, _ownedNftIds, _requestedNftIds2, token);
        assertEq(swapper.fetchOrderInbox(user2).length, 1);
        assertEq(swapper.fetchOrderOutbox(user1).length, 1);

        // Cancel swap order
        vm.startPrank(user1);
        uint256 requestToCancel = swapper.fetchOrderOutbox(user1)[0];
        swapper.cancelOrder(user2, requestToCancel);
        vm.stopPrank();

        // Verify swap order
        assertEq(nft.ownerOf(1), user1);
        assertEq(swapper.fetchOrderInbox(user2).length, 0);
        assertEq(swapper.fetchOrderInbox(user1).length, 0);
        assertEq(swapper.fetchCanceledOrders(user2).length, 1);
        assertEq(swapper.fetchCanceledOrders(user1).length, 1);
    }

    function testRevertRevokeApproval() public {
        clearNftData();

        // Requester Mint
        vm.prank(user1);
        _mintFromCollection1();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);

        // Requestee Mint
        vm.prank(user2);
        _mintFromCollection2();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(minted);

        // Requester Mint 2
        vm.prank(user1);
        _mintFromCollection1();

        // Requestee Mint 2
        vm.prank(user2);
        _mintFromCollection2();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(minted);

        // Requestee approves requester
        vm.prank(user2);
        swapper.sworpApprove(user1);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER);

        // Create swap order
        hoax(user1, 1 ether);
        _requestSwap(user2, _ownedNfts, _requestedNfts2, _ownedNftIds, _requestedNftIds2, token);

        vm.prank(user2);
        swapper.revokeSworpApproval(user1);
        _ownedNfts.pop();
        _ownedNftIds.pop();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);
        vm.expectRevert();
        hoax(user1, 1 ether);
        _requestSwap(user2, _ownedNfts, _requestedNfts2, _ownedNftIds, _requestedNftIds2, token);
    }

    function testSwapAndAcceptMulti() public {
        clearNftData();

        // Requester 1 Mint 1
        vm.prank(user1);
        _mintFromCollection1();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);

        // Requestee Mint
        vm.prank(user2);
        _mintFromCollection2();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(minted);

        // Requester 2 mint 1
        vm.prank(user3);
        _mintFromCollection1();
        _ownedNfts3.push(address(nft));
        _ownedNftIds3.push(++minted);

        // Requestee Mint 2
        vm.prank(user2);
        _mintFromCollection2();

        // Requester 1 Mint 2
        vm.prank(user1);
        _mintFromCollection1();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);

        // Requestee approves requester
        vm.startPrank(user2);
        swapper.sworpApprove(user1);
        swapper.sworpApprove(user3);
        vm.stopPrank();

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER);
        vm.prank(user3);
        for (uint256 i; i < _ownedNfts3.length; i++) {
            nft.approve(address(swapper), _ownedNftIds3[i]);
        }

        // Create swap orders
        hoax(user1, 1 ether);
        _requestSwap(user2, _ownedNfts, _requestedNfts2, _ownedNftIds, _requestedNftIds2, token);
        approveSwapper(user2, actor.REQUESTEE);
        _requestedNfts2.pop();
        _requestedNftIds2.pop();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(2);
        approveSwapper(user2, actor.REQUESTEE);
        hoax(user3, 1 ether);
        _requestSwap(user2, _ownedNfts3, _requestedNfts2, _ownedNftIds3, _requestedNftIds2, token);

        // fufil orders

        uint256[] memory inbox = swapper.fetchOrderInbox(user2);
        vm.startPrank(user2);
        for (uint256 i; i < inbox.length; i++) {
            swapper.fufilSwapOrder(inbox[i]);
        }
        vm.stopPrank();

        // Verify swap
        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.ownerOf(3), user2);
        assertEq(nft.ownerOf(2), user2);
    }

    function testNftSwapWithEth() public {
        clearNftData();
        // Requester Mint
        vm.prank(user1);
        _mintFromCollection1();
        _ownedNfts.push(address(nft));
        _ownedNftIds.push(++minted);

        // Requestee Mint
        vm.prank(user2);
        _mintFromCollection2();
        _requestedNfts2.push(address(nft2));
        _requestedNftIds2.push(minted);

        // Requestee approves requester
        vm.prank(user2);
        swapper.sworpApprove(user1);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER);

        // Create swap order
        hoax(user1, 1 ether);
        token.amount = 0.1 ether;
        _requestSwap(user2, _ownedNfts, _requestedNfts2, _ownedNftIds, _requestedNftIds2, token);
        assertEq(nft.ownerOf(1), address(swapper));
        uint256 user1bal = user1.balance;
        console.log("previous user 1 bal", user1bal);
        // Fufil swap order
        approveSwapper(user2, actor.REQUESTEE);
        deal(user2, 1 ether);
        vm.startPrank(user2);
        uint256 user2bal = user2.balance;
        console.log("previous user 2 bal:", user2bal);
        swapper.fufilSwapOrder{value: 0.1 ether}(swapper.fetchOrderInbox(user2)[0]);
        vm.stopPrank();
        // Verify swap order
        console.log("new user1 bal: ", user1.balance);
        console.log("new user2 bal: ", user2.balance);
        assertEq(user1.balance, user1bal + token.amount);
        assertEq(user2.balance, user2bal - token.amount);
        assertEq(nft.ownerOf(1), user2);
        assertEq(nft2.ownerOf(1), user1);
        assertEq(swapper.fetchOrderInbox(user2).length, 0);
        assertEq(swapper.fetchOrderOutbox(user1).length, 0);
        assertEq(swapper.fetchAcceptedOrders(user2).length, 1);
        assertEq(swapper.fetchAcceptedOrders(user1).length, 1);
    }

    function clearNftData() internal {
        delete _ownedNfts;
        delete _requestedNfts;
        delete _ownedNftIds;
        delete _requestedNftIds;
        delete _ownedNfts2;
        delete _ownedNftIds2;
        delete _requestedNfts2;
        delete _requestedNftIds2;
        delete _ownedNfts3;
        delete _ownedNftIds3;
        delete _requestedNfts3;
        delete _requestedNftIds3;
        minted = 0;
    }
}
