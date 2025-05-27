//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import {ISworpErrors} from "./ISworpErrors.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

abstract contract SworpUtils is ISworpErrors {
    // Inbox limit.
    uint8 internal constant FULFILLER_INBOX_LIMIT = 10;

    // Maximum number of nfts that can be included in a single transaction.
    uint8 internal constant MAX_TRADEABLE_NFT = 15;

    // Fees for creating an order involving multiple nfts. 1 to 1 orders are free.
    uint256 internal constant FEE_PER_NFT = 0.0005 ether;

    // Admin address.
    address internal _admin;

    // Order id counter.
    uint256 internal _nextOrderId;

    // General request pool
    mapping(address => mapping(uint256 => Request)) public _orderPool;

    // Keep track of order index inside user inbox for easier removal after completion.
    mapping(address => mapping(uint256 => uint256)) public inboxOrderIndexTracker;

    // Keep track of order index inside user outbox for easier removal after completion.
    mapping(address => mapping(uint256 => uint256)) internal outboxOrderIndexTracker;

    // Assign index to the next request in the inbox
    mapping(address => uint256) internal inboxNextIndexTracker;

    // Assign index to the next request in the outbox
    mapping(address => uint256) internal outboxNextIndexTracker;

    // fulfillers' inbox
    mapping(address => uint256[]) public fulfillerInbox;

    // Requesters' outbox
    mapping(address => uint256[]) public requesterOutbox;

    // User's accepted requests
    mapping(address => uint256[]) public userAcceptedRequests;

    // User's rejected requests
    mapping(address => uint256[]) public userRejectedRequests;

    // User's canceled requests
    mapping(address => uint256[]) public userCanceledRequests;

    // User's approved addresses. Only adresses aproved by user can send nft swap requests.

    mapping(address => mapping(address => bool)) public approvedAddresses;

    // NOTICE: completed order status mean the order has been accepted, rejected or canceled.
    enum OrderStatus {
        pending,
        completed
    }

    // Location enum allows us to keep track of where to remove a given order from.
    enum Location {
        outbox,
        inbox
    }

    struct Nft {
        address contractAddress;
        uint256 tokenId;
    }

    // Struct to collect the request data.
    struct RequestIn {
        address fulfiller;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        uint256[] requestedNftIds;
    }

    // Finalized order data after order has been given an id.
    struct Request {
        address requester;
        address fulfiller;
        uint256 orderId;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        uint256[] requestedNftIds;
        OrderStatus status;
    }

    // Struct to collect the request data for cross-chain orders.
    struct xChainOrderIn{
        uint64 dstChainId;
        address fulfiller;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        uint256[] requestedNftIds;
    }

    // Struct to hold the finalized cross-chain order data.
    struct xChainOrder{
        address requester;
        address fulfiller;
        uint256 orderId;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        uint256[] requestedNftIds;
        OrderStatus status;
    }

    // Modifiers

    modifier onlyFulfiller(Request memory _order) {
        if (msg.sender != _order.fulfiller) {
            revert Swapper__InvalidFulfiller(msg.sender);
        }
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != _admin) {
            revert Swapper__NotAdmin(msg.sender);
        }
        _;
    }


    /// @dev Checks if a given contract address supports the standard ERC721 interface
    function checkERC721InterfaceSupport(address _nft) internal view returns (bool) {
        try IERC721(_nft).supportsInterface(type(IERC721).interfaceId) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    /**
     * @dev remove a request from inbox or outbox of a user by swapping it with the last item in the array, then popping the last item.
     * @param _from is the Location to delete from (inbox or outbox).
     * @param _user is the user's address.
     * @param _orderId is the unique identifier for the request.
     */
    function removeOrder(Location _from, address _user, uint256 _orderId) internal virtual{
        if (_from == Location.outbox) {
            // Locate order index
            uint256 orderIndex = outboxOrderIndexTracker[_user][_orderId];
            require(orderIndex != 0, "Item not in outbox");
            uint256 itemIndex = --orderIndex;
            uint256 lastItem = requesterOutbox[_user][requesterOutbox[_user].length - 1];
            // Swap the order with the last item in the array and remove the last item
            requesterOutbox[_user][itemIndex] = lastItem;
            requesterOutbox[_user].pop();
            outboxOrderIndexTracker[_user][lastItem] = ++itemIndex;
            outboxOrderIndexTracker[_user][_orderId] = 0;
            outboxNextIndexTracker[_user]--;
        } else {
            // Locate order index
            uint256 orderIndex = inboxOrderIndexTracker[_user][_orderId];
            require(orderIndex != 0, "Item not in inbox");
            uint256 itemIndex = --orderIndex;
            uint256 lastItem = fulfillerInbox[_user][fulfillerInbox[_user].length - 1];
            // Swap the order with the last item in the array and remove the last item
            fulfillerInbox[_user][itemIndex] = lastItem;
            fulfillerInbox[_user].pop();
            inboxOrderIndexTracker[_user][lastItem] = ++itemIndex;
            inboxOrderIndexTracker[_user][_orderId] = 0;
            inboxNextIndexTracker[_user]--;
        }
    }

    function setAdmin(address _newAdmin) external virtual onlyAdmin {
        _admin = _newAdmin;
    }

    function admin() external view returns (address) {
        return _admin;
    }


    // Getter for user inbox.
    function fetchOrderInbox(address _user) external view returns (uint256[] memory) {
        return fulfillerInbox[_user];
    }

    // Getter for user outbox.
    function fetchOrderOutbox(address _user) external view returns (uint256[] memory) {
        return requesterOutbox[_user];
    }

    // Getter for user accepted requests
    function fetchAcceptedOrders(address _user) external view returns (uint256[] memory) {
        return userAcceptedRequests[_user];
    }

    // Getter for user rejected requests
    function fetchRejectedOrders(address _user) external view returns (uint256[] memory) {
        return userRejectedRequests[_user];
    }

    // Getter for user canceled requests.
    function fetchCanceledOrders(address _user) external view returns (uint256[] memory) {
        return userCanceledRequests[_user];
    }

    /**
     * @dev Get the order details.
     */
    function getOrder(uint256 _orderId) public view returns (Request memory) {
        return _orderPool[msg.sender][_orderId];
    }

}