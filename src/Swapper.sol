//SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 *  @title NFT SWAP
 * A Trustless tool for exchanging NFTs bewteen two parties A and B.
 * Party A sends a swap request to party B indicating they would like to swap
 * their Nft for an Nft owned by party B.
 * Contract takes custody of party A's Nft and sends the request to party B's inbox
 * party B can accept or reject the request. If party B accepts, the swap transaction is executed
 * If party B rejects, party A's nft is returned to their wallet.
 * Party A also has the ability to cancel their request provided it hasn't been accepted/rejected by party B.
 * @author 0xstacker "github.com/0xStacker
 */
contract Swapper {
    // Universal inbox limit.
    uint8 constant REQUESTEE_INBOX_LIMIT = 10;

    uint256 internal _nextRequestId = 1;

    // Formatted request data.

    // General request pool
    mapping(address _requestee => mapping(uint256 _requestId => Request)) public _requestPool;

    // Requestees' inbox
    mapping(address _requestee => Request[]) public requesteeInbox;

    // Requesters' outbox
    mapping(address _requester => Request[]) public requesterOutbox;

    // User's accepted requests
    mapping(address _requestee => Request[]) public userAcceptedRequests;

    // User's rejected requests
    mapping(address _requestee => Request[]) public userRejectedRequests;

    // User's canceled requests
    mapping(address _user => Request[]) public userCanceledRequests;

    // User's approved addresses. Only adresses aproved by user can send nft swap requests
    // to prevent spams.
    mapping(address _requestee => mapping(address _requester => bool)) public approvedAddresses;

    // Errors
    error NotOwnedByRequester(address _nft, uint256 _id);
    error NotOwnedByRequestee(address _nft, uint256 _id);
    error SelfRequest();
    error InvalidAddress();
    error NotApproved();
    error BadRequest();
    error InvalidRequestee(address impersonator);
    error RequesteeInboxFull(uint8 size);

    // Events
    event RequestSwap(uint256 _requestId);
    event AcceptSwap(uint256 _requestId);
    event RejectSwap(uint256 _requestId);
    event CancelSwap(uint256 _requestId);
    event ClearInbox(address _user);
    event ClearOutbox(address _user);

    /**
     * @dev Send a swap request to a user.
     * @param _inRequest holds the request data. see RequestIn struct.
     * @notice Ensures that both requester and requestee owns the nfts required for the tx.
     * contract takes requester's nft into custody, gives the request an id and sends it to requestee's inbox.
     */
    struct RequestIn {
        address requestee;
        address ownedNft;
        address requestedNft;
        uint256 ownedNftId;
        uint256 requestedNftId;
    }

    struct Request {
        address requester;
        address requestee;
        address ownedNft;
        address requestedNft;
        uint256 ownedNftId;
        uint256 requestedNftId;
        uint256 requestId;
    }

    function requestNftSwap(RequestIn calldata _inRequest) external {
        Request memory _request = Request({
            requestId: _nextRequestId,
            requester: msg.sender,
            requestee: _inRequest.requestee,
            ownedNft: _inRequest.ownedNft,
            ownedNftId: _inRequest.ownedNftId,
            requestedNft: _inRequest.requestedNft,
            requestedNftId: _inRequest.requestedNftId
        });

        if (_request.requestedNft == address(0) || _request.ownedNft == address(0)) {
            revert InvalidAddress();
        }

        if (_request.requester == _request.requestee) {
            revert SelfRequest();
        }

        // Ensure that the requestee has approved the requester's address.
        if (!approvedAddresses[_request.requestee][_request.requester]) {
            revert NotApproved();
        }

        // Ensure both requester and requestee own the nfts involved.
        IERC721 _ownedNft = IERC721(_request.ownedNft);
        if (_ownedNft.ownerOf(_request.ownedNftId) != msg.sender) {
            revert NotOwnedByRequester(_request.ownedNft, _request.ownedNftId);
        }

        IERC721 _requestedNft = IERC721(_request.requestedNft);
        if (_requestedNft.ownerOf(_request.requestedNftId) != _request.requestee) {
            revert NotOwnedByRequestee(_request.requestedNft, _request.requestedNftId);
        }

        // Prevent spams.
        if (requesteeInbox[_request.requestee].length == REQUESTEE_INBOX_LIMIT) {
            revert RequesteeInboxFull(10);
        }

        _ownedNft.safeTransferFrom(msg.sender, address(this), _request.ownedNftId);
        _requestPool[_request.requestee][_request.requestId] = _request;
        requesteeInbox[_request.requestee].push(_request);
        requesterOutbox[msg.sender].push(_request);
        emit RequestSwap(_request.requestId);
    }

    /**
     * @dev Accept an incoming request
     * @param _requestId is the identifier for the request to be accepted.
     * @notice Only the requestee provided in the request data can accept the request
     * @notice Automatically rejects if the requestee no longer hold the required nft.
     */
    function acceptRequest(uint256 _requestId) external {
        Request memory _request = _requestPool[msg.sender][_requestId];
        if (_isEmpty(_request)) {
            revert BadRequest();
        }

        address _requester = _request.requester;
        address _requestee = _request.requestee;
        IERC721 _requestedNft = IERC721(_request.requestedNft);
        IERC721 _requesterNft = IERC721(_request.ownedNft);

        // Terminate exchange if party B no longer holds the NFT requested by party A
        if (_requestedNft.ownerOf(_request.requestedNftId) != msg.sender) {
            rejectRequest(_requestId);
            userCanceledRequests[_requester].push(_request);
            userCanceledRequests[_requestee].push(_request);
            emit CancelSwap(_requestId);
        } else {
            _requestedNft.safeTransferFrom(msg.sender, address(this), _request.requestedNftId);
            _requesterNft.safeTransferFrom(address(this), _requestee, _request.ownedNftId);
            _requestedNft.safeTransferFrom(address(this), _requester, _request.requestedNftId);
            delete _requestPool[_requestee][_requestId];
            Request[] memory userPending = requesteeInbox[_requestee];
            Request[] memory requesterPending = requesterOutbox[_requester];
            // remove request from requestee pending and add it to accepted list.
            delete requesteeInbox[_requestee];
            removeRequest(location.inbox, _requestee, userPending, _requestId);
            userAcceptedRequests[_requestee].push(_request);
            // remove request from requester pending and add it to accepted list
            delete requesterOutbox[_requester];
            removeRequest(location.outbox, _requester, requesterPending, _requestId);
            userAcceptedRequests[_requester].push(_request);
            emit AcceptSwap(_requestId);
        }
    }

    /**
     * @dev Reject an incoming request.
     * @param _requestId is the identifier for the request.
     */
    function rejectRequest(uint256 _requestId) public {
        Request memory _request = _requestPool[msg.sender][_requestId];
        if (_isEmpty(_request)) {
            revert BadRequest();
        }

        IERC721 _requesterNft = IERC721(_request.ownedNft);
        // Return requester's NFT
        _requesterNft.safeTransferFrom(address(this), _request.requester, _request.ownedNftId);
        address _requester = _request.requester;
        address _requestee = _request.requestee;

        delete _requestPool[_request.requestee][_requestId];
        Request[] memory userPending = requesteeInbox[_requestee];

        // remove request from pending and add it to rejected
        delete requesteeInbox[_request.requestee];
        removeRequest(location.inbox, _requestee, userPending, _requestId);

        // remove request from sender's outbox
        Request[] memory _requesterOutbox = requesterOutbox[_requester];
        delete requesterOutbox[_requester];
        removeRequest(location.outbox, _requester, _requesterOutbox, _requestId);
        userRejectedRequests[_requestee].push(_request);
        userRejectedRequests[_requester].push(_request);
        emit RejectSwap(_requestId);
    }

    enum location {
        outbox,
        inbox
    }

    /**
     * @dev remove a request from inbox or outbox of a user.
     * @param _from is the location to delete from (inbox or outbox).
     * @param _user is the user's address.
     * @param _cache is the cached list of the user's inbox or outbox.
     * @param _requestId is the unique identifier for the request.
     */
    function removeRequest(location _from, address _user, Request[] memory _cache, uint256 _requestId) internal {
        if (_from == location.outbox) {
            for (uint8 i; i < _cache.length; i++) {
                if (_cache[i].requestId != _requestId) {
                    requesterOutbox[_user].push(_cache[i]);
                }
            }
        } else {
            for (uint8 i; i < _cache.length; i++) {
                if (_cache[i].requestId != _requestId) {
                    requesteeInbox[_user].push(_cache[i]);
                }
            }
        }
    }

    /**
     * @dev Allows a requester to cancel their request.
     * @param _requestId is the identifier of the request.
     * @notice A requester can only cancel their request if the requestee has not accepted or rejected the request at their end.
     */
    function cancelRequest(uint256 _requestId) external {
        Request memory _request = _requestPool[msg.sender][_requestId];
        if (_isEmpty(_request)) {
            revert BadRequest();
        }
        address _requester = _request.requester;
        address _requestee = _request.requestee;
        IERC721 _requesterNft = IERC721(_request.ownedNft);
        delete _requestPool[msg.sender][_requestId];
        // Return requester's NFT
        _requesterNft.safeTransferFrom(address(this), _request.requester, _request.ownedNftId);
        Request[] memory _requesterOutbox = requesterOutbox[_requester];
        Request[] memory _requesteeInbox = requesteeInbox[_request.requestee];
        delete requesterOutbox[_requester];
        removeRequest(location.outbox, _requester, _requesterOutbox, _requestId);
        delete requesteeInbox[_requestee];
        removeRequest(location.inbox, _requestee, _requesteeInbox, _requestId);
        userCanceledRequests[_requester].push(_request);
        userCanceledRequests[_requestee].push(_request);
    }

    function rejectAll() external {
        Request[] memory _userInbox = requesteeInbox[msg.sender];
        for (uint256 i; i < _userInbox.length; i++) {
            Request memory _request = _requestPool[msg.sender][_userInbox[i].requestId];
            IERC721 _requesterNft = IERC721(_request.ownedNft);
            // Return requester's NFT
            _requesterNft.safeTransferFrom(address(this), _request.requester, _request.ownedNftId);
            address _requester = _request.requester;
            delete _requestPool[_request.requestee][_request.requestId];
            removeRequest(location.outbox, _requester, requesterOutbox[_requester], _request.requestId);
        }
        delete requesteeInbox[msg.sender];
        emit ClearInbox(msg.sender);
    }

    // Getter for user inbox.
    function fetchInbox(address _user) external view returns (Request[] memory) {
        return requesteeInbox[_user];
    }

    // Getter for user outbox.
    function fetchOutbox(address _user) external view returns (Request[] memory) {
        return requesterOutbox[_user];
    }

    // Getter for user accepted requests
    function fetchAccepted(address _user) external view returns (Request[] memory) {
        return userAcceptedRequests[_user];
    }

    // Getter for user rejected requests
    function fetchRejected(address _user) external view returns (Request[] memory) {
        return userRejectedRequests[_user];
    }

    // Getter for user canceled requests.
    function fetchCanceled(address _user) external view returns (Request[] memory) {
        return userCanceledRequests[_user];
    }

    /**
     * @dev Allow a user to be able to send a swap request.
     * @param _user is the user address to be approved.
     */
    function approve(address _user) external {
        approvedAddresses[msg.sender][_user] = true;
    }

    /**
     * @dev Prevent an address from sending a request
     * @param _user is the user address whose approval is to be revoked.
     */
    function revokeApproval(address _user) external {
        approvedAddresses[msg.sender][_user] = false;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function getRequest(uint _requestId) external view returns(Request memory){
        return _requestPool[msg.sender][_requestId];
    }

    /**
     * @dev Checks if a request object is empty.
     * @param _request is the request to be checked.
     */
    function _isEmpty(Request memory _request) internal pure returns (bool) {
        Request memory empty;
        if (_request.requestId == empty.requestId && _request.requester == empty.requester) {
            return true;
        } else {
            return false;
        }
    }
}
