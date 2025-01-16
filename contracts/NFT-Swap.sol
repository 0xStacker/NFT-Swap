//SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;
import {IERC721} from ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

contract Swapper{

    struct Request{
        address to;
        address ownedNft;
        uint ownedNftId;
        address requestedNft;
        uint requestedNftId;
    }

    mapping(address => Request[]) receivedRequests;
    mapping(address => Request[]) sentRequests;

    error NotOwnedByRequester(address _nft, uint _id);
    error NotOwnedByRequestee(address _nft, uint _id);
    error AlreadyRequested();

    function requestNftSwap(Request calldata _request) external{
        IERC721 _ownedNft = IERC721(_request.ownedNft);
        if (_ownedNft.ownerOf(_request.ownedNftId) != msg.sender){
            revert NotOwnedByRequester(_request.ownedNft, _request.ownedNftId);
        }

        IERC721 _requestedNft = IERC721(_request.requestedNft);
        if (_requestedNft.ownerOf(_request.requestedNftId) != _request.to){
            revert NotOwnedByRequestee(_request.requestedNft, _request.requestedNftId);
        }


    }

}
