//SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;
import {IERC721} from ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

/**
    * @dev Trustless NFT swapping implementation bewteen two parties A and B.
    * Party A sends a swap request to party B indicating they would like to swap
    * their Nft for an Nft owned by party B.
    * Contract takes custody of party A's Nft and sends the request to party B's inbox
    * party B can accept or reject the request. If party B accepts, the swap transaction is executed
    * If party B rejects, party A's nft is returned to their wallet.
    * Party A also has the ability to cancel their request provided it hasn't been accepted/rejected by party B.
    */

contract Swapper{
    // Universal inbox limit.
    uint8 constant REQUESTEE_INBOX_LIMIT = 3; 
    uint internal _nextRequestId = 1;
    
    // Takes in request data
    struct RequestIn{
        address requester;
        address requestee;
        address ownedNft;
        uint ownedNftId;
        address requestedNft;
        uint requestedNftId;
    }

    // Formatted request data. 
    struct Request{
        uint requestId;
        address requester;
        address requestee;
        address ownedNft;
        uint ownedNftId;
        address requestedNft;
        uint requestedNftId;
    }

    // General request pool
    mapping(address _requestee => mapping (uint _requestId => Request)) public _requestPool;
    
    // Users' inbox
    mapping(address _requestee => Request[]) public userPendingRequests;
    
    // User's accepted request 
    mapping(address _requestee => Request[]) public userAcceptedRequests;
    
    // User's rejected request
    mapping(address _requestee => Request[]) public userRejectedRequests;
      
    // Errors
    error NotOwnedByRequester(address _nft, uint _id);
    error NotOwnedByRequestee(address _nft, uint _id);
    error AlreadyRequested();
    error InvalidAddress();
    error BadRequest();
    error InvalidRequestee(address impersonator);
    error RequesteeInboxFull(uint8 size);

    /**
    * @dev Send a swap request to a user.
    * @param _inRequest holds the request data. see RequestIn struct.
    * @notice Ensures that both requester and requestee owns the nfts required for the transaction.
    * contract takes requester's nft into custody, gives the request an id and sends it to requestee's inbox.
    */

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

    /**
    * @dev Accept an incoming request
    * @param _requestId is the identifier for the request to be accepted.
    * @notice Only the requestee provided in the request data can accept the request
    * @notice Automatically rejects if the requestee no longer hold the required nft.
    */
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
        
    
        if(_requestedNft.ownerOf(_request.requestedNftId) != msg.sender){
            rejectRequest(_requestId);
        }
        else{
            _requestedNft.safeTransferFrom(msg.sender, address(this), _request.requestedNftId);
            _requesterNft.safeTransferFrom(address(this), _request.requestee, _request.ownedNftId);
            _requestedNft.safeTransferFrom(address(this), _request.requester, _request.requestedNftId);
            delete _requestPool[_request.requestee][_requestId];
            Request[] memory userPending = userPendingRequests[_request.requestee];
            
            // remove request from pending and add it to accepted.
            delete userPendingRequests[_request.requestee];
            for (uint8 i; i < userPending.length; i++){
                if (userPending[i].requestId != _requestId){
                    userPendingRequests[_request.requestee].push(userPending[i]);
                }
            }
            userAcceptedRequests[msg.sender].push(_request);
        }


    }

    /**
    *@dev Reject an incoming request.
    */

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
        
        // remove request from pending and add it to rejected 
        delete userPendingRequests[_request.requestee];
        for (uint8 i; i < userPending.length; i++){
            if (userPending[i].requestId != _requestId){
                userPendingRequests[_request.requestee].push(userPending[i]);
            }
        }
        userRejectedRequests[msg.sender].push(_request);
    }

    // Checks if a request object is empty.
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
