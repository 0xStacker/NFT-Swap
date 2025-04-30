//SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
// import {ERC165} from ""


/**
 * @title NFT SWAP
 * @author 0xstacker "github.com/0xStacker
 * A Trustless tool for exchanging NFTs bewteen two parties A and B.
 * Party A sends a swap request to party B indicating they would like to swap
 * their Nft for an Nft owned by party B.
 * Contract takes custody of party A's Nft and sends the request to party B's inbox
 * party B can accept or reject the request. If party B accepts, the swap transaction is executed
 * If party B rejects, party A's nft is returned to their wallet.
 * Party A also has the ability to cancel their request provided it hasn't been accepted/rejected by party B.
 */
contract Swapper is ReentrancyGuard, IERC721Receiver{
    // Universal inbox limit.
    uint8 constant REQUESTEE_INBOX_LIMIT = 10;

    uint8 constant MAX_TRADEABLE_NFT = 15;

    uint256 internal _nextRequestId = 1;

    // General request pool
    mapping(address _requestee => mapping(uint256 _requestId => Request)) public _requestPool;

    mapping(address => mapping(uint256 => uint256 inboxRequestIndex)) inboxRequestIndexTracker;

    // Requestees' inbox
    mapping(address _requestee => uint256[]) public requesteeInbox;

    mapping(address => mapping(uint256 => uint256 outboxRequestIndex)) outboxRequestIndexTracker;

    // Requesters' outbox
    mapping(address _requester => uint256[]) public requesterOutbox;

    // User's accepted requests
    mapping(address _requestee => uint256[]) public userAcceptedRequests;

    // User's rejected requests
    mapping(address _requestee => uint256[]) public userRejectedRequests;

    // User's canceled requests
    mapping(address _user => uint256[]) public userCanceledRequests;

    // User's approved addresses. Only adresses aproved by user can send nft swap requests
    // to prevent spams.
    mapping(address _requestee => mapping(address _requester => bool)) public approvedAddresses;

    // Errors
    error NotOwnedByRequester(address _nft, uint256 _id);
    error NotOwnedByRequestee(address _nft, uint256 _id);
    error SelfRequest();
    error InvalidAddress();
    error NotApproved(address requester);
    error BadRequest();
    error InvalidRequestee(address impersonator);
    error RequesteeInboxFull(uint8 size);

    // Events
    event RequestSwap(address indexed _from, address _to, uint256 _requestId);
    event RequestNftSwapMulti(address indexed _from, address _to, uint256 _requestId);
    event AcceptSwap(uint256 _requestId);
    event RejectSwap(uint256 _requestId);
    event CancelSwap(uint256 _requestId);
    event ClearInbox(address _user);
    event ClearOutbox(address _user);


    struct Nft {
        address contractAddress;
        uint256 tokenId;
    }

    struct RequestIn {
        address requestee;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        uint256[] requestedNftIds;
    }

    struct Request {
        address requester;
        address requestee;
        uint256 requestId;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        uint256[] requestedNftIds;
    }

    constructor() ReentrancyGuard(){}
    
    /// @dev Check if the contract supports the ERC721 interface
    function checkInterfaceSupport(address _nft) internal view returns (bool){
        try IERC721(_nft).supportsInterface(type(IERC721).interfaceId) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }
    
    /**
     * @dev Initiate an nft swap that involves multiple nfts.
     */
    function requestNftSwapMulti(Request memory _request) internal nonReentrant{
        /// DO ZERO CHECK HERE

        if(
            _request.ownedNfts.length != _request.ownedNftIds.length
                && _request.requestedNfts.length != _request.requestedNftIds.length
        ){
            revert BadRequest();
        }

        if (_request.requester == _request.requestee) {
            revert SelfRequest();
        }

        // Ensure that the requestee has approved the requester's address.
        if (!approvedAddresses[_request.requestee][_request.requester]) {
            revert NotApproved(_request.requester);
        }

        // Ensure requester own the nfts involved.
        uint256 totalOwnedNfts = _request.ownedNfts.length;

        for (uint256 i; i < totalOwnedNfts; i++) {
            Nft memory ownedNft = Nft({contractAddress: _request.ownedNfts[i], tokenId: _request.ownedNftIds[i]});
            if (ownedNft.contractAddress == address(0)){
                revert BadRequest();
            }

            if (!checkInterfaceSupport(ownedNft.contractAddress)){
                revert BadRequest();
            }
            IERC721 _ownedNft = IERC721(ownedNft.contractAddress);
            if (_ownedNft.ownerOf(ownedNft.tokenId) != msg.sender) {
                revert NotOwnedByRequester(ownedNft.contractAddress, ownedNft.tokenId);
            }
        }

        // Prevent spams.
        if (requesteeInbox[_request.requestee].length == REQUESTEE_INBOX_LIMIT) {
            revert RequesteeInboxFull(10);
        }
        uint256 nextIndex = _nextRequestId;
        // Store the request in the request pool
        _requestPool[_request.requestee][_request.requestId] = _request;
        inboxRequestIndexTracker[_request.requestee][_request.requestId] = nextIndex;
        outboxRequestIndexTracker[_request.requester][_request.requestId] = nextIndex;
        requesteeInbox[_request.requestee].push(_request.requestId);
        requesterOutbox[msg.sender].push(_request.requestId);
        _nextRequestId++;

        // Transfer all requester's NFTs to the contract
        for (uint256 i; i <= totalOwnedNfts; i++) {
            Nft memory ownedNft = Nft({contractAddress: _request.ownedNfts[i], tokenId: _request.ownedNftIds[i]});
            IERC721(ownedNft.contractAddress).safeTransferFrom(msg.sender, address(this), ownedNft.tokenId);
        }

        emit RequestNftSwapMulti(_request.requester, _request.requestee, _request.requestId);
    }

    /**
     * @dev Initiate a swap request to a user.
     * @param _inRequest @dev holds the request data. see RequestIn struct.
     * @notice Requester must own the nfts they are requesting to swap.
     * @notice Requester can cancel their request at any time before it is accepted or rejected.
     * contract takes requester's nft into custody, gives the request an id and sends it to requestee's inbox.
     */

    function requestNftSwap(RequestIn calldata _inRequest) external nonReentrant{
        Request memory _request = Request({
            requestId: _nextRequestId,
            requester: msg.sender,
            requestee: _inRequest.requestee,
            ownedNfts: _inRequest.ownedNfts,
            requestedNfts: _inRequest.requestedNfts,
            ownedNftIds: _inRequest.ownedNftIds,
            requestedNftIds: _inRequest.requestedNftIds
        });

        if(
            _request.ownedNfts.length != _request.ownedNftIds.length
                && _request.requestedNfts.length != _request.requestedNftIds.length
        ){
            revert BadRequest();
        }

        if (_request.ownedNfts.length > 1 || _request.requestedNfts.length > 1) {
            requestNftSwapMulti(_request);
        } else {
            // Avoid looping unless its necessary
            Nft memory requestedNft =
                Nft({contractAddress: _request.requestedNfts[0], tokenId: _request.requestedNftIds[0]});
            Nft memory ownedNft = Nft({contractAddress: _request.ownedNfts[0], tokenId: _request.ownedNftIds[0]});
            if (requestedNft.contractAddress == address(0) || ownedNft.contractAddress == address(0)) {
                revert InvalidAddress();
            }

            if (_request.requester == _request.requestee) {
                revert SelfRequest();
            }

            // Ensure that the requestee has approved the requester's address.
            if (!approvedAddresses[_request.requestee][_request.requester]) {
                revert NotApproved(_request.requester);
            }

            // Ensure requester own the nfts involved.
            IERC721 _ownedNft = IERC721(ownedNft.contractAddress);
            if (_ownedNft.ownerOf(ownedNft.tokenId) != msg.sender) {
                revert NotOwnedByRequester(ownedNft.contractAddress, ownedNft.tokenId);
            }

            // Prevent spams.
            if (requesteeInbox[_request.requestee].length == REQUESTEE_INBOX_LIMIT) {
                revert RequesteeInboxFull(10);
            }
            uint256 nextIndex = _nextRequestId;
            _requestPool[_request.requestee][_request.requestId] = _request;
            inboxRequestIndexTracker[_request.requestee][_request.requestId] = nextIndex;
            outboxRequestIndexTracker[_request.requester][_request.requestId] = nextIndex;
            requesteeInbox[_request.requestee].push(_request.requestId);
            requesterOutbox[msg.sender].push(_request.requestId);
            _nextRequestId++;
            _ownedNft.safeTransferFrom(msg.sender, address(this), ownedNft.tokenId);
            emit RequestSwap(_request.requester, _request.requestee, _request.requestId);
        }
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

        if (_request.ownedNfts.length > 1 || _request.requestedNfts.length > 1) {
            revert("Bad request");
        } else {
            Nft memory requestedNft =
                Nft({contractAddress: _request.requestedNfts[0], tokenId: _request.requestedNftIds[0]});
            Nft memory ownedNft = Nft({contractAddress: _request.ownedNfts[0], tokenId: _request.ownedNftIds[0]});
            IERC721 _requestedNft = IERC721(requestedNft.contractAddress);
            IERC721 _requesterNft = IERC721(ownedNft.contractAddress);
            uint256 _requestedNftId = requestedNft.tokenId;
            uint256 _requesterNftId = ownedNft.tokenId;

            // Terminate exchange if party B no longer holds the NFT requested by party A
            if (_requestedNft.ownerOf(_requestedNftId) != msg.sender) {
                rejectRequest(_requestId);
                userCanceledRequests[_requester].push(_request.requestId);
                userCanceledRequests[_requestee].push(_request.requestId);
            } else {
                delete _requestPool[_requestee][_requestId]; //__ Add an accepted and rejected flag to request struct__//
                removeRequest(location.inbox, _requestee, _requestId);
                userAcceptedRequests[_requestee].push(_request.requestId);
                
                // remove request from requester pending and add it to accepted list
                removeRequest(location.outbox, _requester, _requestId);
                
                userAcceptedRequests[_requester].push(_request.requestId);
                _requestedNft.safeTransferFrom(msg.sender, _requester, _requestedNftId);
                _requesterNft.safeTransferFrom(address(this), _requestee, _requesterNftId);
                emit AcceptSwap(_requestId);
            }
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

        if (_request.ownedNfts.length > 1 || _request.requestedNfts.length > 1) {
            revert("Bad request");
        } else {
            Nft memory ownedNft = Nft({contractAddress: _request.ownedNfts[0], tokenId: _request.ownedNftIds[0]});
            IERC721 _requesterNft = IERC721(ownedNft.contractAddress);
            address _requester = _request.requester;
            address _requestee = _request.requestee;
            delete _requestPool[_request.requestee][_requestId];
            // remove request from pending and add it to rejected
            removeRequest(location.inbox, _requestee, _requestId);
            // remove request from sender's outbox
            removeRequest(location.outbox, _requester, _requestId);
            userRejectedRequests[_requestee].push(_request.requestId);
            userRejectedRequests[_requester].push(_request.requestId);
            // Return requester's NFT
            _requesterNft.safeTransferFrom(address(this), _request.requester, ownedNft.tokenId);
            emit RejectSwap(_requestId);
        }
    }

    enum location {
        outbox,
        inbox
    }

    /**
     * @dev remove a request from inbox or outbox of a user.
     * @param _from is the location to delete from (inbox or outbox).
     * @param _user is the user's address.
     * @param _requestId is the unique identifier for the request.
     */
    function removeRequest(location _from, address _user, uint256 _requestId) internal {
        if (_from == location.outbox) {
            require(outboxRequestIndexTracker[_user][_requestId] != 0, "Item not in outbox");
            uint256 itemIndex = --outboxRequestIndexTracker[_user][_requestId];
            uint256 lastItem = requesterOutbox[_user][requesterOutbox[_user].length - 1];
            requesterOutbox[_user][itemIndex] = lastItem;
            requesterOutbox[_user].pop();
            outboxRequestIndexTracker[_user][_requestId] = 0;
        } else {
            require(inboxRequestIndexTracker[_user][_requestId] != 0, "Item not in inbox");
            uint256 itemIndex = --inboxRequestIndexTracker[_user][_requestId];
            uint256 lastItem = requesteeInbox[_user][requesteeInbox[_user].length - 1];
            requesteeInbox[_user][itemIndex] = lastItem;
            requesteeInbox[_user].pop();
            inboxRequestIndexTracker[_user][_requestId] = 0;
        }
    }

    /**
     * @dev Allows a requester to cancel their request.
     * @param _requestId is the identifier of the request.
     * @notice A requester can only cancel their request if the requestee has not accepted or rejected the request at their end.
     */
    function cancelRequest(address _to, uint256 _requestId) external {
        Request memory _request = _requestPool[_to][_requestId];
        if (_isEmpty(_request)) {
            revert BadRequest();
        }

        if (_request.ownedNfts.length > 1 || _request.requestedNfts.length > 1) {
            revert("Bad request");
        } else {
            Nft memory ownedNft = Nft({contractAddress: _request.ownedNfts[0], tokenId: _request.ownedNftIds[0]});
            address _requester = _request.requester;
            address _requestee = _request.requestee;
            IERC721 _requesterNft = IERC721(ownedNft.contractAddress);
            delete _requestPool[_requestee][_requestId];
            // uint[] memory _requesterOutbox = requesterOutbox[_requester];
            // uint[] memory _requesteeInbox = requesteeInbox[_request.requestee];
            delete requesterOutbox[_requester];
            removeRequest(location.outbox, _requester, _requestId);
            delete requesteeInbox[_requestee];
            removeRequest(location.inbox, _requestee, _requestId);
            userCanceledRequests[_requester].push(_request.requestId);
            userCanceledRequests[_requestee].push(_request.requestId);
            // Return requester's NFT
            _requesterNft.safeTransferFrom(address(this), _request.requester, ownedNft.tokenId);
            emit CancelSwap(_requestId);
        }
    }

    // Getter for user inbox.
    function fetchInbox(address _user) external view returns (uint256[] memory) {
        return requesteeInbox[_user];
    }

    // Getter for user outbox.
    function fetchOutbox(address _user) external view returns (uint256[] memory) {
        return requesterOutbox[_user];
    }

    // Getter for user accepted requests
    function fetchAccepted(address _user) external view returns (uint256[] memory) {
        return userAcceptedRequests[_user];
    }

    // Getter for user rejected requests
    function fetchRejected(address _user) external view returns (uint256[] memory) {
        return userRejectedRequests[_user];
    }

    // Getter for user canceled requests.
    function fetchCanceled(address _user) external view returns (uint256[] memory) {
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

    function getRequest(uint256 _requestId) external view returns (Request memory) {
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
