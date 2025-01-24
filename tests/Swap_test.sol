// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import "remix_tests.sol"; // this import is automatically injected by Remix.
import "remix_accounts.sol";
import "hardhat/console.sol";
import {RequestLib} from "../contracts/Swapper.sol";

interface IERC721{
    function mint() external;
    function approve(address _to, uint _tokenId) external;
    function ownerOf(uint _tokenId) external returns(address);
}

interface Iswapper{
    function requestNftSwap(RequestLib.RequestIn calldata _inRequest) external;
    function acceptRequest(uint _requestId) external;
    function rejectRequest(uint _requestId) external;
    function cancelRequest(uint _requestId) external;
    function approve(address _user) external;
    function revokeApproval(address _user) external;
}

contract SwapTestSuit{
    uint requestId;
    address nftAddy = 0x1c91347f2A44538ce62453BEBd9Aa907C662b4bD;
    IERC721 _nft = IERC721(nftAddy);
    address swapperAddress = 0x93f8dddd876c7dBE3323723500e83E202A7C96CC;
    Iswapper swapper = Iswapper(swapperAddress);    
    uint nextMintId;

    function _mintAndApprove() internal{
        nextMintId += 1;
        _nft.mint();
        _nft.approve(address(swapper), nextMintId + 1);       
    }

    /// #sender: account-0
    function mintToAcc1() public{
        _mintAndApprove();
        Assert.equal(_nft.ownerOf(nextMintId), msg.sender, "Wrong Owner");
    }

    /// #sender: account-1
    function mintToAcc2() public{
        _mintAndApprove();
        Assert.equal(_nft.ownerOf(nextMintId), msg.sender, "Wrong Owner");
    }
    

    /// #sender: account-0
    function sendRequest() public {
        swapper.requestNftSwap(RequestLib.getReq(TestsAccounts.getAccount(1),nftAddy,1,nftAddy,2
        ));
        requestId += 1;
        Assert.equal(_nft.ownerOf(1), swapperAddress, "Contract should have custody");}
    
    /// #sender: account-1
    function acceptRequest_() external{
        swapper.acceptRequest(requestId);
        Assert.equal(_nft.ownerOf(1), TestsAccounts.getAccount(1), "Swap Failed");
        Assert.equal(_nft.ownerOf(2), TestsAccounts.getAccount(0), "Swap Failed");
    }    
}