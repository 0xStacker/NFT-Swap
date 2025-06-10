//SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {Test, console} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {SworpV1} from "../src/v1/Sworp.sol";
import {Nft} from "./testNft.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TestToken} from "./testErc20.sol";

contract SwapTestERC20 is Test {
    Nft nft;
    Nft nft2;
    SworpV1 swapper;
    TransparentUpgradeableProxy proxy;
    address user1 = address(123);
    address user2 = address(234);
    address user3 = address(456);
    uint8 minted;
    TestToken token;
    SworpV1.FungibleToken offeringToken;
    SworpV1.FungibleToken requestedToken;

    address[] _ownedNfts;
    address[] _requestedNfts;
    uint256[] _ownedNftIds;
    uint256[] _requestedNftIds;

    enum Location {
        OWNED_NFTS,
        REQUESTED_NFTS
    }

    SworpV1.PublicOrderParams swapRequest1;

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
        token = new TestToken();
        offeringToken.contractAddress = address(token);
        requestedToken.contractAddress = address(token);
        vm.prank(user1);
        token.mint();
        vm.prank(user2);
        token.mint();
    }

    function testImplementationAdmin() public view {
        assertEq(swapper.admin(), address(this), "Admin should be the deployer");
    }

    function _requestSwap(
        address _requestee,
        address[] memory _ownedNft,
        address[] memory _requestedNft,
        uint256[] memory _ownedTokenId,
        SworpV1.FungibleToken memory _offeringToken,
        SworpV1.FungibleToken memory _requestedToken
    ) internal returns (uint256 orderId) {
        swapRequest1.fulfiller = _requestee;
        swapRequest1.ownedNfts = _ownedNft;
        swapRequest1.requestedNfts = _requestedNft;
        swapRequest1.ownedNftIds = _ownedTokenId;
        swapRequest1.requestedToken = _requestedToken;
        swapRequest1.offeringToken = _offeringToken;
        orderId = swapper.createSwapOrder{
            value: _offeringToken.contractAddress == address(0) ? _offeringToken.amount : 0
        }(swapRequest1);
    }

    function _matchOrder(address matcher, uint256 ftAmount, uint256 orderId, SworpV1.Nft[] memory _match, bool _revert)
        internal
    {
        SworpV1.PublicOrder memory order = swapper.getOrder(orderId);
        if (_revert) {
            vm.startPrank(matcher);
            token.approve(address(swapper), ftAmount);
            vm.expectRevert();
            swapper.matchOrder{value: order.offeringToken.contractAddress == address(0) ? ftAmount : 0}(orderId, _match);
            vm.stopPrank();
        } else {
            vm.startPrank(matcher);
            token.approve(address(swapper), ftAmount);
            swapper.matchOrder{value: order.offeringToken.contractAddress == address(0) ? ftAmount : 0}(orderId, _match);
            vm.stopPrank();
        }
    }

    function _mintFromCollection1() internal returns (uint256 tokenId) {
        tokenId = nft.mint();
    }

    function _mintFromCollection2() internal returns (uint256 tokenId) {
        tokenId = nft2.mint();
    }

    function approveSwapper(address _user, actor _actor, address collection) internal {
        vm.startPrank(_user);
        if (_actor == actor.REQUESTER) {
            for (uint256 i; i < _ownedNfts.length; i++) {
                IERC721(collection).approve(address(swapper), _ownedNftIds[i]);
            }
        } else {
            for (uint256 i; i < _requestedNfts.length; i++) {
                IERC721(collection).approve(address(swapper), _requestedNftIds[i]);
            }
        }
        vm.stopPrank();
    }

    function _mintAndPush(address _to, uint8 _collection, uint256 _amount, Location _location) internal {
        for (uint256 i; i < _amount; i++) {
            if (_collection == 1) {
                hoax(_to, 0.1 ether);
                uint256 tokenId = nft.mint();
                if (_location == Location.OWNED_NFTS) {
                    _ownedNfts.push(address(nft));
                    _ownedNftIds.push(tokenId);
                } else {
                    _requestedNfts.push(address(nft));
                    _requestedNftIds.push(tokenId);
                }
            } else {
                hoax(_to, 0.1 ether);
                uint256 tokenId = nft2.mint();
                if (_location == Location.OWNED_NFTS) {
                    _ownedNfts.push(address(nft2));
                    _ownedNftIds.push(tokenId);
                } else {
                    _requestedNfts.push(address(nft2));
                    _requestedNftIds.push(tokenId);
                }
            }
        }
    }

    function assertOwner(Nft _nft, uint256[] memory _tokens, address _owner) internal view returns (bool) {
        for (uint256 i; i < _tokens.length; i++) {
            if (_nft.ownerOf(_tokens[i]) != _owner) {
                return false;
            }
        }
        return true;
    }

    function _logBalances() internal view returns (uint256 user1CurrentBalance, uint256 user2CurrentBalance) {
        user1CurrentBalance = token.balanceOf(user1);
        user2CurrentBalance = token.balanceOf(user2);
        console.log("User 1 balance: ", user1CurrentBalance);
        console.log("User 2 balance: ", user2CurrentBalance);
    }

    function testNftToNftPlusFtSwapPublicOrderWithErc20(
        uint256 creatorAmount,
        uint256 matcherAmount,
        uint256 tokenAmount,
        uint256 _requestAmount
    ) public {
        creatorAmount = bound(creatorAmount, 1, 5);
        matcherAmount = bound(matcherAmount, 1, 5);
        assertLt(creatorAmount, 6);
        assertLt(matcherAmount, 6);
        tokenAmount = bound(tokenAmount, 0.1 ether, 1 ether);
        _requestAmount = bound(_requestAmount, 0.05 ether, tokenAmount - 0.05 ether);
        clearNftData();
        // Requester mint
        _mintAndPush(user1, 1, creatorAmount, Location.OWNED_NFTS);

        // Requestee Mint
        _mintAndPush(user2, 2, matcherAmount, Location.REQUESTED_NFTS);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER, address(nft));

        // Requestee approve swapper
        approveSwapper(user2, actor.REQUESTEE, address(nft2));

        hoax(user1, 1 ether);
        requestedToken.amount = _requestAmount;
        uint256 orderId = _requestSwap(user2, _ownedNfts, _requestedNfts, _ownedNftIds, offeringToken, requestedToken);
        
        uint256 ftAmount = swapper.getOrder(orderId).requestedToken.amount;
        SworpV1.Nft[] memory matchData = new SworpV1.Nft[](matcherAmount);
        for (uint256 i; i < matcherAmount; i++) {
            SworpV1.Nft memory data;
            data.contractAddress = _requestedNfts[i];
            data.tokenId = _requestedNftIds[i];
            matchData[i] = data;
        }
        vm.deal(user2, tokenAmount);
        (uint256 user1InitialBalance, uint256 user2InitialBalance) = _logBalances();
        _matchOrder(user2, ftAmount, orderId, matchData, false);
        bool _ownedNftOwnerCheck = assertOwner(nft, _ownedNftIds, user2);
        bool _requestedNftOwnerCheck = assertOwner(nft2, _requestedNftIds, user1);
        (uint256 user1FinalBalance, uint256 user2FinalBalance) = _logBalances();
        assertEq(user1FinalBalance, user1InitialBalance + ftAmount);
        assertEq(user2FinalBalance, user2InitialBalance - ftAmount);
        assertEq(_ownedNftOwnerCheck, true);
        assertEq(_requestedNftOwnerCheck, true);
    }

    function testNftToFtSwapPublicOrderWithToken(uint256 creatorAmount, uint256 tokenAmount, uint256 _requestTokenAmount)
        public
    {
        creatorAmount = bound(creatorAmount, 1, 5);
        uint256 matcherAmount = 0;
        assertLt(creatorAmount, 6);
        tokenAmount = bound(tokenAmount, 0.1 ether, 1 ether);
        _requestTokenAmount = bound(_requestTokenAmount, 0.05 ether, tokenAmount - 0.05 ether);
        clearNftData();
        // Requester mint
        _mintAndPush(user1, 1, creatorAmount, Location.OWNED_NFTS);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER, address(nft));

        // Requestee approve swapper
        approveSwapper(user2, actor.REQUESTEE, address(nft2));

        hoax(user1, 1 ether);
        requestedToken.amount = _requestTokenAmount;

        uint256 orderId = _requestSwap(user2, _ownedNfts, _requestedNfts, _ownedNftIds, offeringToken, requestedToken);
        uint256 ftAmount = swapper.getOrder(orderId).requestedToken.amount;
        SworpV1.Nft[] memory matchData = new SworpV1.Nft[](matcherAmount);
        for (uint256 i; i < matcherAmount; i++) {
            SworpV1.Nft memory data;
            data.contractAddress = _requestedNfts[i];
            data.tokenId = _requestedNftIds[i];
            matchData[i] = data;
        }
        vm.deal(user2, tokenAmount);
        (uint256 user1InitialBalance, uint256 user2InitialBalance) = _logBalances();
        _matchOrder(user2, ftAmount, orderId, matchData, false);
        bool _ownedNftOwnerCheck = assertOwner(nft, _ownedNftIds, user2);
        bool _requestedNftOwnerCheck = assertOwner(nft2, _requestedNftIds, user1);
        (uint256 user1FinalBalance, uint256 user2FinalBalance) = _logBalances();
        assertEq(user1FinalBalance, user1InitialBalance + ftAmount);
        assertEq(user2FinalBalance, user2InitialBalance - ftAmount);
        assertEq(_ownedNftOwnerCheck, true);
        assertEq(_requestedNftOwnerCheck, true);
    }

    function testNftPlusFtToNftPlusFtWithErc20(
        uint256 creatorAmount,
        uint256 matcherAmount,
        uint256 tokenAmount,
        uint256 _requestAmount
    ) public {
        creatorAmount = bound(creatorAmount, 1, 5);
        matcherAmount = bound(matcherAmount, 1, 5);
        assertLt(creatorAmount, 6);
        assertLt(matcherAmount, 6);
        tokenAmount = bound(tokenAmount, 0.1 ether, 1 ether);
        _requestAmount = bound(_requestAmount, 0.05 ether, tokenAmount - 0.05 ether);
        clearNftData();
        // Requester mint
        _mintAndPush(user1, 1, creatorAmount, Location.OWNED_NFTS);

        // Requestee Mint
        _mintAndPush(user2, 2, matcherAmount, Location.REQUESTED_NFTS);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER, address(nft));

        // Requestee approve swapper
        approveSwapper(user2, actor.REQUESTEE, address(nft2));

        offeringToken.amount = _requestAmount;
        vm.startPrank(user1);
        (uint256 user1InitialBalance, uint256 user2InitialBalance) = _logBalances();
        token.approve(address(swapper), offeringToken.amount);
        uint256 orderId = _requestSwap(user2, _ownedNfts, _requestedNfts, _ownedNftIds, offeringToken, requestedToken);
        vm.stopPrank();
        uint256 ftAmount = swapper.getOrder(orderId).requestedToken.amount;
        SworpV1.Nft[] memory matchData = new SworpV1.Nft[](matcherAmount);
        for (uint256 i; i < matcherAmount; i++) {
            SworpV1.Nft memory data;
            data.contractAddress = _requestedNfts[i];
            data.tokenId = _requestedNftIds[i];
            matchData[i] = data;
        }

        _matchOrder(user2, ftAmount, orderId, matchData, false);
        bool _ownedNftOwnerCheck = assertOwner(nft, _ownedNftIds, user2);
        bool _requestedNftOwnerCheck = assertOwner(nft2, _requestedNftIds, user1);
        (uint256 user1FinalBalance, uint256 user2FinalBalance) = _logBalances();
        assertEq(user1FinalBalance, user1InitialBalance - offeringToken.amount);
        assertEq(user2FinalBalance, user2InitialBalance + offeringToken.amount);
        assertEq(_ownedNftOwnerCheck, true);
        assertEq(_requestedNftOwnerCheck, true);
    }

    // Testing Edge Cases

    function testRevertMatchPublicMixedOrderWithoutEnoughToken(
        uint256 creatorAmount,
        uint256 tokenAmount,
        uint256 _requestTokenAmount
    ) public {
        creatorAmount = bound(creatorAmount, 1, 5);
        uint256 matcherAmount = 0;
        assertLt(creatorAmount, 6);
        tokenAmount = bound(tokenAmount, 0.1 ether, 100 ether);
        _requestTokenAmount = bound(_requestTokenAmount, 0.05 ether, tokenAmount - 0.05 ether);
        clearNftData();
        // Requester mint
        _mintAndPush(user1, 1, creatorAmount, Location.OWNED_NFTS);

        // Requester approves swapper
        approveSwapper(user1, actor.REQUESTER, address(nft));

        // Requestee approve swapper
        approveSwapper(user2, actor.REQUESTEE, address(nft2));

        hoax(user1, 1 ether);
        requestedToken.amount = _requestTokenAmount;

        uint256 orderId = _requestSwap(user2, _ownedNfts, _requestedNfts, _ownedNftIds, offeringToken, requestedToken);
        uint256 ftAmount = _requestTokenAmount - 0.01 ether; // Intentionally setting it lower than requested amount to trigger revert
        SworpV1.Nft[] memory matchData = new SworpV1.Nft[](matcherAmount);
        for (uint256 i; i < matcherAmount; i++) {
            SworpV1.Nft memory data;
            data.contractAddress = _requestedNfts[i];
            data.tokenId = _requestedNftIds[i];
            matchData[i] = data;
        }
        _matchOrder(user2, ftAmount, orderId, matchData, true);
    }

    function clearNftData() internal {
        delete _ownedNfts;
        delete _requestedNfts;
        delete _ownedNftIds;
        delete _requestedNftIds;
    }
}
