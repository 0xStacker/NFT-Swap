//SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;
import {IERC721} from ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from ".deps/github/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

library RequestLib{

    struct RequestIn{
    address requestee;
    address ownedNft;
    uint ownedNftId;
    address requestedNft;
    uint requestedNftId;}

    struct Request{
    uint requestId;
    address requester;
    address requestee;
    address ownedNft;
    uint ownedNftId;
    address requestedNft;
    uint requestedNftId;}

    function getReq(address r, address o, uint oid, address rr, uint rrid) external pure returns(RequestIn memory){
        return RequestIn(r, o, oid, rr, rrid);}

    /** 
    * @dev Checks if a request object is empty.
    * @param _request is the request to be checked.
    */
    function _isEmpty(Request memory _request) internal pure returns(bool){
        Request memory empty;
        if(
            _request.requestId == empty.requestId && _request.requester == empty.requester
        ){
            return true;
        }
        else{
            return false;}}
}

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
    uint8 constant REQUESTEE_INBOX_LIMIT = 10; 
    uint internal _nextRequestId = 1;

    // Formatted request data. 

    // General request pool
    mapping(address _requestee => mapping (uint _requestId => RequestLib.Request)) public _requestPool;
    
    // Requestees' inbox
    mapping(address _requestee => RequestLib.Request[]) public requesteeInbox;
    
    // Requesters' outbox
    mapping(address _requester => RequestLib.Request[]) public requesterOutbox;
    
    // User's accepted requests
    mapping(address _requestee => RequestLib.Request[]) public userAcceptedRequests;
    
    // User's rejected requests
    mapping(address _requestee => RequestLib.Request[]) public userRejectedRequests;

    // User's canceled requests
    mapping(address _user => RequestLib.Request[]) public userCanceledRequests;

    // User approved addresses.
    mapping(address _requestee => mapping(address _requester => bool)) public approvedAddresses;

    // Errors
    error NotOwnedByRequester(address _nft, uint _id);
    error NotOwnedByRequestee(address _nft, uint _id);
    error AlreadyRequested();
    error SelfRequest();
    error InvalidAddress();
    error NotApproved();
    error BadRequest();
    error InvalidRequestee(address impersonator);
    error RequesteeInboxFull(uint8 size);
    /**
    * @dev Send a swap request to a user.
    * @param _inRequest holds the request data. see RequestIn struct.
    * @notice Ensures that both requester and requestee owns the nfts required for the tx.
    * contract takes requester's nft into custody, gives the request an id and sends it to requestee's inbox.
    */

    

    function requestNftSwap(RequestLib.RequestIn calldata _inRequest) external{
        RequestLib.Request memory _request = RequestLib.Request({
            requestId: _nextRequestId,
            requester: msg.sender,
            requestee: _inRequest.requestee,
            ownedNft: _inRequest.ownedNft,
            ownedNftId: _inRequest.ownedNftId,
            requestedNft: _inRequest.requestedNft,
            requestedNftId: _inRequest.requestedNftId
        });
        
        if (_request.requestedNft == address(0) || _request.ownedNft == address(0)){
            revert InvalidAddress();}

        if (_request.requester == _request.requestee){
            revert SelfRequest();}

        // Ensure that the requestee has approved the requester's address.
        if (!approvedAddresses[_request.requestee][_request.requester]){
            revert NotApproved();
        }

        // Ensure both requester and requestee own the nfts involved.
        IERC721 _ownedNft = IERC721(_request.ownedNft);
        if (_ownedNft.ownerOf(_request.ownedNftId) != msg.sender){
            revert NotOwnedByRequester(_request.ownedNft, _request.ownedNftId);
        }

        IERC721 _requestedNft = IERC721(_request.requestedNft);
        if (_requestedNft.ownerOf(_request.requestedNftId) != _request.requestee){
            revert NotOwnedByRequestee(_request.requestedNft, _request.requestedNftId);
        }

        // Prevent spams from unapproved addresses.
        if (requesteeInbox[_request.requestee].length == REQUESTEE_INBOX_LIMIT){
            revert RequesteeInboxFull(10);
        }

        _ownedNft.safeTransferFrom(msg.sender, address(this), _request.ownedNftId);
        
        _requestPool[_request.requestee][_request.requestId] = _request;
        requesteeInbox[_request.requestee].push(_request);
        requesterOutbox[msg.sender].push(_request); 
    }

    /**
    * @dev Accept an incoming request
    * @param _requestId is the identifier for the request to be accepted.
    * @notice Only the requestee provided in the request data can accept the request
    * @notice Automatically rejects if the requestee no longer hold the required nft.
    */
    using RequestLib for RequestLib.Request;
    function acceptRequest(uint _requestId) external {
        RequestLib.Request memory _request = _requestPool[msg.sender][_requestId];
        if (_request._isEmpty()){
            revert BadRequest();
        }
        if (_request.requestee != msg.sender){
            revert InvalidRequestee(msg.sender);
        }

        address _requester = _request.requester;
        address _requestee = _request.requestee;
        IERC721 _requestedNft = IERC721(_request.requestedNft);
        IERC721 _requesterNft = IERC721(_request.ownedNft);
        
    
        if(_requestedNft.ownerOf(_request.requestedNftId) != msg.sender){
            rejectRequest(_requestId);
            userCanceledRequests[_requester].push(_request);
            userCanceledRequests[_requestee].push(_request);
        }

        else{
            _requestedNft.safeTransferFrom(msg.sender, address(this), _request.requestedNftId);
            _requesterNft.safeTransferFrom(address(this), _requestee, _request.ownedNftId);
            _requestedNft.safeTransferFrom(address(this), _requester, _request.requestedNftId);
            delete _requestPool[_requestee][_requestId];
            RequestLib.Request[] memory userPending = requesteeInbox[_requestee];
            RequestLib.Request[] memory requesterPending = requesterOutbox[_requester];
            // remove request from requestee pending and add it to accepted list.
            delete requesteeInbox[_requestee];
            removeRequest(location.inbox, _requestee, userPending, _requestId);
            userAcceptedRequests[_requestee].push(_request);
            // remove request from requester pending and add it to accepted list
            delete requesterOutbox[_requester];
            removeRequest(location.outbox, _requester, requesterPending, _requestId);
            userAcceptedRequests[_requester].push(_request);
        }
    }

    enum location {outbox, inbox}

    /**
    * @dev remove a request from inbox or outbox of a user.
    * @param _from is the location to delete from (inbox or outbox).
    * @param _user is the user's address.
    * @param _cache is the cached list of the user's inbox or outbox.
    * @param _requestId is the unique identifier for the request.
    */

    function removeRequest(location _from, address _user, RequestLib.Request[] memory _cache, uint _requestId) internal{
        if (_from == location.outbox){
            for (uint8 i; i < _cache.length; i++){
                if (_cache[i].requestId != _requestId){
                    requesterOutbox[_user].push(_cache[i]);}
                    }
                }
        else{
            for (uint8 i; i < _cache.length; i++){
                if (_cache[i].requestId != _requestId){
                    requesteeInbox[_user].push(_cache[i]);}
                    }
                }
            }

    /**
    * @dev Reject an incoming request.
    * @param _requestId is the identifier for the request.
    */

    function rejectRequest(uint _requestId) public{
        RequestLib.Request memory _request = _requestPool[msg.sender][_requestId];
        if (_request._isEmpty()){
            revert BadRequest();
        }
        if (_request.requestee != msg.sender){
            revert InvalidRequestee(msg.sender);
        }
        
        IERC721 _requesterNft = IERC721(_request.ownedNft);
        _requesterNft.safeTransferFrom(address(this), _request.requester, _request.ownedNftId);
        address _requester = _request.requester;
        address _requestee = _request.requestee;
        
        delete _requestPool[_request.requestee][_requestId];
        RequestLib.Request[] memory userPending = requesteeInbox[_requestee];
        
        // remove request from pending and add it to rejected 
        delete requesteeInbox[_request.requestee];
        removeRequest(location.inbox, _requestee, userPending, _requestId);

        // remove request from sender's outbox
        RequestLib.Request[] memory _requesterOutbox = requesterOutbox[_requester];
        delete requesterOutbox[_requester];
        removeRequest(location.outbox, _requester, _requesterOutbox, _requestId);
        userRejectedRequests[_requestee].push(_request);
        userRejectedRequests[_requester].push(_request);
    }

    /**
    * @dev Allows a requester to cancel their request.
    * @param _requestId is the identifier of the request.
    * @notice A requester can only cancel their request if the requestee has not accepted or rejected the request at their end.
    */
    function cancelRequest(uint _requestId) external {
        RequestLib.Request memory _request = _requestPool[msg.sender][_requestId];
        if (_request._isEmpty()){
            revert BadRequest();
        }
        if (_request.requester != msg.sender){
            revert InvalidRequestee(msg.sender);
        }

        address _requester = _request.requester;
        address _requestee = _request.requestee;
        RequestLib.Request[] memory _requesterOutbox = requesterOutbox[msg.sender];
        RequestLib.Request[] memory _requesteeInbox = requesteeInbox[_request.requestee];

        delete requesterOutbox[_requester];
        removeRequest(location.outbox, _requester, _requesterOutbox, _requestId);
        delete requesteeInbox[_requestee];
        removeRequest(location.inbox, _requestee, _requesteeInbox, _requestId);
        userCanceledRequests[_requester].push(_request);
        userCanceledRequests[_requestee].push(_request);
    }

    // Getter for user inbox.
    function fetchInbox(address _user) external view returns(RequestLib.Request[] memory){
        return requesteeInbox[_user];
    }

    // Getter for user outbox.
    function fetchOutbox(address _user) external view returns(RequestLib.Request[] memory){
        return requesterOutbox[_user];
    }

    // Getter for user accepted requests
    function fetchAccepted(address _user) external view returns(RequestLib.Request[] memory){
        return userAcceptedRequests[_user];
    }

    // Getter for user rejected requests
    function fetchRejected(address _user) external view returns(RequestLib.Request[] memory){
        return userRejectedRequests[_user];
    }

    // Getter for user canceled requests.
    function fetchCanceled(address _user) external view returns(RequestLib.Request[] memory){
        return userCanceledRequests[_user];
    }

    /**
    * @dev Allow a user to be able to send a swap request.
    * @param _user is the user address to be approved.
    */
    function approve(address _user) external{
        approvedAddresses[msg.sender][_user] = true;
    }

    /**
    * @dev Prevent an address from sending a request
    * @param _user is the user address whose approval is to be revoked.
    */
    function revokeApproval(address _user) external{
        approvedAddresses[msg.sender][_user] = false;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4){
        return IERC721Receiver.onERC721Received.selector;}
        }
