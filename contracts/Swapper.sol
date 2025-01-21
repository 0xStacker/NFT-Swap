//SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;
import {IERC721} from ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

contract Swapper{
    uint8 constant REQUESTEE_INBOX_LIMIT = 3; 
    uint internal _nextRequestId = 1;
    
    struct RequestIn{
        address requester;
        address requestee;
        address ownedNft;
        uint ownedNftId;
        address requestedNft;
        uint requestedNftId;
    }

    struct Request{
        uint requestId;
        address requester;
        address requestee;
        address ownedNft;
        uint ownedNftId;
        address requestedNft;
        uint requestedNftId;
    }


    mapping(address _requestee => mapping (uint _requestId => Request)) public _requestPool;
    mapping(address _requestee => Request[]) public userPendingRequests;
    mapping(address _requestee => Request[]) public userAcceptedRequests;
    mapping(address _requestee => Request[]) public userRejectedRequests;
      

    error NotOwnedByRequester(address _nft, uint _id);
    error NotOwnedByRequestee(address _nft, uint _id);
    error AlreadyRequested();
    error InvalidAddress();
    error BadRequest();
    error InvalidRequestee(address impersonator);
    error RequesteeInboxFull(uint8 size);


    function requestNftSwap(RequestIn calldata _inRequest) external{
        Request memory _request = Request({
            requestId: _nextRequestId,
            requester: _inRequest.requester,
            requestee: _inRequest.requestee,
            ownedNft: _inRequest.ownedNft,
            ownedNftId: _inRequest.ownedNftId,
            requestedNft: _inRequest.requestedNft,
            requestedNftId: _inRequest.requestedNftId
        });

        if (_request.requestedNft == address(0) || _request.ownedNft == address(0)){
            revert InvalidAddress();
        }
        IERC721 _ownedNft = IERC721(_request.ownedNft);
        if (_ownedNft.ownerOf(_request.ownedNftId) != msg.sender){
            revert NotOwnedByRequester(_request.ownedNft, _request.ownedNftId);
        }

        IERC721 _requestedNft = IERC721(_request.requestedNft);
        if (_requestedNft.ownerOf(_request.requestedNftId) != _request.requestee){
            revert NotOwnedByRequestee(_request.requestedNft, _request.requestedNftId);
        }

        if (userPendingRequests[_request.requestee].length == REQUESTEE_INBOX_LIMIT){
            revert RequesteeInboxFull(10);
        }

        _ownedNft.safeTransferFrom(msg.sender, address(this), _request.ownedNftId);
        
        _requestPool[_request.requestee][_request.requestId] = _request;
        userPendingRequests[_request.requestee].push(_request);
    }


    function acceptRequest(uint _requestId) external {
        Request memory _request = _requestPool[msg.sender][_requestId];
        if (_isEmpty(_request)){
            revert BadRequest();
        }
        if (_request.requestee != msg.sender){
            revert InvalidRequestee(msg.sender);
        }

        IERC721 _requestedNft = IERC721(_request.requestedNft);
        IERC721 _requesterNft = IERC721(_request.ownedNft);
        
        // Automatically reject. 
        // Requester can also cancel the request from their end.
        if(_requestedNft.ownerOf(_request.requestedNftId) != msg.sender){
            rejectRequest(_requestId);
        }
        else{
            _requestedNft.safeTransferFrom(msg.sender, address(this), _request.requestedNftId);
            _requesterNft.safeTransferFrom(address(this), _request.requestee, _request.ownedNftId);
            _requestedNft.safeTransferFrom(address(this), _request.requester, _request.requestedNftId);
            delete _requestPool[_request.requestee][_requestId];
            Request[] memory userPending = userPendingRequests[_request.requestee];
            delete userPendingRequests[_request.requestee];
            for (uint8 i; i < userPending.length; i++){
                if (userPending[i].requestId != _requestId){
                    userPendingRequests[_request.requestee].push(userPending[i]);
                }
            }
        }


    }

    function rejectRequest(uint _requestId) public{
        Request memory _request = _requestPool[msg.sender][_requestId];
        if (_isEmpty(_request)){
            revert BadRequest();
        }
        if (_request.requestee != msg.sender){
            revert InvalidRequestee(msg.sender);
        }
        
        IERC721 _requesterNft = IERC721(_request.ownedNft);
        _requesterNft.safeTransferFrom(address(this), _request.requester, _request.ownedNftId);
        
        delete _requestPool[_request.requestee][_requestId];
        Request[] memory userPending = userPendingRequests[_request.requestee];
        delete userPendingRequests[_request.requestee];
        for (uint8 i; i < userPending.length; i++){
            if (userPending[i].requestId != _requestId){
                userPendingRequests[_request.requestee].push(userPending[i]);
            }
        }

    }


    function _isEmpty(Request memory _request) internal pure returns(bool){
        Request memory empty;
        if(
            _request.requestId == empty.requestId && _request.requester == empty.requester
        ){
            return true;
        }
        else{
            return false;
        }
    }
}
