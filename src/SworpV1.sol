//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ISwapperErrors} from "./ISworpErrors.sol";
import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
/**
 * @title NFT SWAP
 * @author 0xstacker "github.com/0xStacker
 * A Trustless tool for exchanging NFTs bewteen two parties A and B.
 * Party A (requester) creates a swap order and sends to party B (fulfiller) indicating they would like to swap
 * their Nft(s) for an Nft(s) owned by party B.
 * Contract takes custody of party A's Nft(s) and sends the request to party B's inbox
 * party B can accept or reject the request. If party B accepts, the swap transaction is executed
 * If party B rejects, party A's nft is returned to their wallet.
 * Party A also has the ability to cancel their request provided it hasn't been accepted/rejected by party B.
 * The contract allows for multiple nfts to be involved in a single transaction.
 * Transactions involving a 1 to 1 nft swap are free.
 */

contract SworpV1 is Initializable, ReentrancyGuardUpgradeable, IERC721Receiver, ISwapperErrors {
    // Universal inbox limit.
    uint8 internal constant FULFILLER_INBOX_LIMIT = 10;

    // Maximum number of nfts that can be included in a single transaction.
    uint8 internal constant MAX_TRADEABLE_NFT = 15;

    // Fees for creating an order involving multiple nfts. 1 to 1 orders are free.
    uint256 internal constant FEE_PER_NFT = 0.0005 ether;

    // Admin address.
    address private _admin;

    // Order id counter.
    uint256 internal _nextOrderId;

    // General request pool
    mapping(address _fulfiller => mapping(uint256 _orderId => Request)) public _orderPool;

    // Keep track of order index inside user inbox for easier removal after completion.
    mapping(address => mapping(uint256 => uint256 inboxOrderIndex)) public inboxOrderIndexTracker;

    // Keep track of order index inside user outbox for easier removal after completion.
    mapping(address => mapping(uint256 => uint256 outboxOrderIndex)) private outboxOrderIndexTracker;

    // Assign index to the next request in the inbox
    mapping(address => uint256 nextIndex) private inboxNextIndexTracker;

    // Assign index to the next request in the outbox
    mapping(address => uint256) private outboxNextIndexTracker;

    // fulfillers' inbox
    mapping(address _fulfiller => uint256[]) public fulfillerInbox;

    // Requesters' outbox
    mapping(address _requester => uint256[]) public requesterOutbox;

    // User's accepted requests
    mapping(address _fulfiller => uint256[]) public userAcceptedRequests;

    // User's rejected requests
    mapping(address _fulfiller => uint256[]) public userRejectedRequests;

    // User's canceled requests
    mapping(address _user => uint256[]) public userCanceledRequests;

    // User's approved addresses. Only adresses aproved by user can send nft swap requests.

    mapping(address _fulfiller => mapping(address _requester => bool)) public approvedAddresses;

    // NOTICE: completed order status mean the order has been accepted or rejected.
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

    // Struct to hold the request data.
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

    constructor() {
        _disableInitializers();
    }

    function initialize(address _adminAddress) external initializer {
        __ReentrancyGuard_init();
        _admin = _adminAddress;
        _nextOrderId = 1;
    }

    receive() external payable {}

    /// @dev Checks if a given contract address supports the standard ERC721 interface
    function checkERC721InterfaceSupport(address _nft) internal view returns (bool) {
        try IERC721(_nft).supportsInterface(type(IERC721).interfaceId) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    /**
     * @dev Initiate an nft swap order that involves multiple nfts.
     * @param _order holds the request data. see Request struct.
     */
    function createSwapOrderMulti(Request memory _order) internal nonReentrant {
        if (
            _order.ownedNfts.length != _order.ownedNftIds.length
                || _order.requestedNfts.length != _order.requestedNftIds.length
        ) {
            revert Swapper__BadOrder();
        }

        if (_order.requester == _order.fulfiller) {
            revert Swapper__SelfOrder();
        }

        // Ensure that the fulfiller has approved the requester's address.
        if (!approvedAddresses[_order.fulfiller][_order.requester]) {
            revert Swapper__NotApproved(_order.requester);
        }

        // Ensure requester own the nfts involved.
        uint256 totalOwnedNfts = _order.ownedNfts.length;

        if (fulfillerInbox[_order.fulfiller].length == FULFILLER_INBOX_LIMIT) {
            revert Swapper__FulfillerInboxFull(10);
        }

        // Contract takes custody of the requester's nfts.
        for (uint256 i; i < totalOwnedNfts; i++) {
            Nft memory ownedNft = Nft({contractAddress: _order.ownedNfts[i], tokenId: _order.ownedNftIds[i]});
            if (ownedNft.contractAddress == address(0)) {
                revert Swapper__BadOrder();
            }

            if (!checkERC721InterfaceSupport(ownedNft.contractAddress)) {
                revert Swapper__BadOrder();
            }
            IERC721 _ownedNft = IERC721(ownedNft.contractAddress);
            if (_ownedNft.ownerOf(ownedNft.tokenId) != msg.sender) {
                revert Swapper__NotOwnedByRequester(ownedNft.contractAddress, ownedNft.tokenId);
            } else {
                IERC721(ownedNft.contractAddress).safeTransferFrom(msg.sender, address(this), ownedNft.tokenId);
            }
        }

        // Store the request in the request pool
        _orderPool[_order.fulfiller][_order.orderId] = _order;
        inboxOrderIndexTracker[_order.fulfiller][_order.orderId] = ++inboxNextIndexTracker[_order.fulfiller];
        outboxOrderIndexTracker[_order.requester][_order.orderId] = ++outboxNextIndexTracker[_order.requester];
        fulfillerInbox[_order.fulfiller].push(_order.orderId);
        requesterOutbox[msg.sender].push(_order.orderId);

        emit CreateSwapOrderMulti(_order.requester, _order.fulfiller, _order.orderId);
    }

    /**
     * @dev Accept an incoming request that involves multiple nfts.
     * @param _order holds the request data. see Request struct.
     * @notice Only the fulfiller provided in the request data can accept the request
     * @notice Automatically rejects if the fulfiller no longer hold the required nft.
     */
    function fufilSwapOrderMulti(Request memory _order) internal onlyFulfiller(_order) {
        uint256 totalRequestedNfts = _order.requestedNfts.length;
        uint256 totalOwnedNfts = _order.ownedNfts.length;

        _orderPool[_order.fulfiller][_order.orderId].status = OrderStatus.completed;

        // remove request from inbox and add it to their accepted list
        removeOrder(Location.inbox, _order.fulfiller, _order.orderId);
        userAcceptedRequests[_order.fulfiller].push(_order.orderId);
        // remove request from requester outbox and add it to their accepted list
        removeOrder(Location.outbox, _order.requester, _order.orderId);
        userAcceptedRequests[_order.requester].push(_order.orderId);

        // Fufil swap order
        for (uint256 i; i < totalRequestedNfts; i++) {
            Nft memory requestedNft =
                Nft({contractAddress: _order.requestedNfts[i], tokenId: _order.requestedNftIds[i]});
            IERC721 _orderedNft = IERC721(requestedNft.contractAddress);

            // Ensure that the order fulfiller still has the nft involved.
            if (_orderedNft.ownerOf(requestedNft.tokenId) != msg.sender) {
                rejectOrder(_order.orderId);
                userCanceledRequests[_order.requester].push(_order.orderId);
                userCanceledRequests[_order.fulfiller].push(_order.orderId);
            } else {
                _orderedNft.safeTransferFrom(msg.sender, _order.requester, requestedNft.tokenId);
            }
        }

        for (uint256 i; i < totalOwnedNfts; i++) {
            Nft memory ownedNft = Nft({contractAddress: _order.ownedNfts[i], tokenId: _order.ownedNftIds[i]});
            IERC721 _ownedNft = IERC721(ownedNft.contractAddress);
            _ownedNft.safeTransferFrom(address(this), _order.fulfiller, ownedNft.tokenId);
        }
        emit FufillSwapOrder(_order.orderId);
    }

    /**
     * @dev Initiate a swap request to a user.
     * @param _inRequest holds the request data. see RequestIn struct.
     * @notice Requester must own the nfts they are requesting to swap.
     * @notice Requester can cancel their request at any time before it is accepted or rejected.
     * contract takes requester's nft into custody, gives the request an id and sends it to fulfiller's inbox.
     */
    function createSwapOrder(RequestIn calldata _inRequest) external payable {
        // Configure order data (Assign requestId).
        Request memory _order = Request({
            orderId: _nextOrderId++,
            requester: msg.sender,
            fulfiller: _inRequest.fulfiller,
            ownedNfts: _inRequest.ownedNfts,
            requestedNfts: _inRequest.requestedNfts,
            ownedNftIds: _inRequest.ownedNftIds,
            requestedNftIds: _inRequest.requestedNftIds,
            status: OrderStatus.pending
        });

        // Ensure order data is valid.
        if (
            _order.ownedNfts.length != _order.ownedNftIds.length
                || _order.requestedNfts.length != _order.requestedNftIds.length
        ) {
            revert Swapper__BadOrder();
        }

        // Handle orders involving miultiple nfts.
        if (_order.ownedNfts.length > 1 || _order.requestedNfts.length > 1) {
            // Charge fee per nfts involved in the order.
            uint8 totalNftsInvolved = uint8(_order.ownedNfts.length + _order.requestedNfts.length);
            if (msg.value < FEE_PER_NFT * totalNftsInvolved) {
                revert Swapper__InsufficientOrderFee(msg.value);
            }
            createSwapOrderMulti(_order);
        } else {
            // Avoid looping unless its necessary
            Nft memory requestedNft =
                Nft({contractAddress: _order.requestedNfts[0], tokenId: _order.requestedNftIds[0]});
            Nft memory ownedNft = Nft({contractAddress: _order.ownedNfts[0], tokenId: _order.ownedNftIds[0]});
            if (requestedNft.contractAddress == address(0) || ownedNft.contractAddress == address(0)) {
                revert Swapper__InvalidAddress();
            }

            if (_order.requester == _order.fulfiller) {
                revert Swapper__SelfOrder();
            }

            // Ensure that the fulfiller has approved the requester's address.
            if (!approvedAddresses[_order.fulfiller][_order.requester]) {
                revert Swapper__NotApproved(_order.requester);
            }

            if (!checkERC721InterfaceSupport(ownedNft.contractAddress)) {
                revert Swapper__BadOrder();
            }

            // Ensure requester own the nfts involved.
            IERC721 _ownedNft = IERC721(ownedNft.contractAddress);
            if (_ownedNft.ownerOf(ownedNft.tokenId) != msg.sender) {
                revert Swapper__NotOwnedByRequester(ownedNft.contractAddress, ownedNft.tokenId);
            }

            // Prevent spams.
            if (fulfillerInbox[_order.fulfiller].length == FULFILLER_INBOX_LIMIT) {
                revert Swapper__FulfillerInboxFull(10);
            }

            // Create and store swap order
            outboxNextIndexTracker[_order.requester]++;
            inboxNextIndexTracker[_order.fulfiller]++;
            _orderPool[_order.fulfiller][_order.orderId] = _order;
            inboxOrderIndexTracker[_order.fulfiller][_order.orderId] = inboxNextIndexTracker[_order.fulfiller];
            outboxOrderIndexTracker[_order.requester][_order.orderId] = outboxNextIndexTracker[_order.requester];
            fulfillerInbox[_order.fulfiller].push(_order.orderId);
            requesterOutbox[msg.sender].push(_order.orderId);
            _ownedNft.safeTransferFrom(msg.sender, address(this), ownedNft.tokenId);
            // refund sent fee
            if (msg.value > 0) {
                payable(msg.sender).transfer(msg.value);
            }
            emit CreateSwapOrder(_order.requester, _order.fulfiller, _order.orderId);
        }
    }

    /**
     * @dev Accept an incoming request
     * @param _orderId is the identifier for the request to be accepted.
     * @notice Only the fulfiller provided in the request data can accept the request
     * @notice Automatically rejects if the fulfiller no longer hold the required nft.
     */
    function fufilSwapOrder(uint256 _orderId) external onlyFulfiller(getOrder(_orderId)) {
        Request memory _order = _orderPool[msg.sender][_orderId];
        if (_order.status == OrderStatus.completed) {
            revert Swapper__BadOrder();
        }

        address _requester = _order.requester;
        address _fulfiller = _order.fulfiller;

        // Handle orders involving multiple nfts.
        if (_order.ownedNfts.length > 1 || _order.requestedNfts.length > 1) {
            fufilSwapOrderMulti(_order);
        } else {
            Nft memory requestedNft =
                Nft({contractAddress: _order.requestedNfts[0], tokenId: _order.requestedNftIds[0]});
            Nft memory ownedNft = Nft({contractAddress: _order.ownedNfts[0], tokenId: _order.ownedNftIds[0]});
            IERC721 _requestedNft = IERC721(requestedNft.contractAddress);
            IERC721 _requesterNft = IERC721(ownedNft.contractAddress);
            uint256 _requestedNftId = requestedNft.tokenId;
            uint256 _requesterNftId = ownedNft.tokenId;

            // Terminate order if party B no longer holds the NFT requested by party A
            if (_requestedNft.ownerOf(_requestedNftId) != msg.sender) {
                rejectOrder(_orderId);
                userCanceledRequests[_requester].push(_order.orderId);
                userCanceledRequests[_fulfiller].push(_order.orderId);
            } else {
                _orderPool[_fulfiller][_orderId].status = OrderStatus.completed;

                // Remove order from fulfiller inbox and add it to accepted list
                removeOrder(Location.inbox, _fulfiller, _orderId);
                userAcceptedRequests[_fulfiller].push(_order.orderId);

                // remove order from requester outbox and add it to accepted list
                removeOrder(Location.outbox, _requester, _orderId);

                userAcceptedRequests[_requester].push(_order.orderId);

                // Fufil swap order
                _requestedNft.safeTransferFrom(msg.sender, _requester, _requestedNftId);
                _requesterNft.safeTransferFrom(address(this), _fulfiller, _requesterNftId);
                emit FufillSwapOrder(_orderId);
            }
        }
    }

    /**
     * @dev Reject an incoming request.
     * @param _orderId is the identifier for the request.
     */
    function rejectOrder(uint256 _orderId) public {
        Request memory _order = _orderPool[msg.sender][_orderId];
        if (_order.status == OrderStatus.completed) {
            revert Swapper__BadOrder();
        }

        address _requester = _order.requester;
        address _fulfiller = _order.fulfiller;
        _orderPool[_order.fulfiller][_orderId].status = OrderStatus.completed;
        // remove order from fulfiller's inbox and add it to their rejected list
        removeOrder(Location.inbox, _fulfiller, _orderId);
        // remove order from requester's outbox and add it to their rejected list
        removeOrder(Location.outbox, _requester, _orderId);

        userRejectedRequests[_fulfiller].push(_order.orderId);
        userRejectedRequests[_requester].push(_order.orderId);
        // Return requester's NFT
        for (uint256 i; i < _order.ownedNfts.length; i++) {
            Nft memory ownedNft = Nft({contractAddress: _order.ownedNfts[i], tokenId: _order.ownedNftIds[i]});
            IERC721 _requesterNft = IERC721(ownedNft.contractAddress);
            _requesterNft.safeTransferFrom(address(this), _order.requester, ownedNft.tokenId);
        }
        emit RejectSwapOrder(_orderId);
    }

    /**
     * @dev remove a request from inbox or outbox of a user by swapping it with the last item in the array, then popping the last item.
     * @param _from is the Location to delete from (inbox or outbox).
     * @param _user is the user's address.
     * @param _orderId is the unique identifier for the request.
     */
    function removeOrder(Location _from, address _user, uint256 _orderId) internal {
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

    /**
     * @dev Allows a requester to cancel their request.
     * @param _orderId is the identifier of the request.
     * @notice A requester can only cancel their request if the fulfiller has not accepted or rejected the request at their end.
     */
    function cancelOrder(address _to, uint256 _orderId) external {
        Request memory _order = _orderPool[_to][_orderId];
        if (_order.status == OrderStatus.completed) {
            revert Swapper__BadOrder();
        }
        address _requester = _order.requester;
        address _fulfiller = _order.fulfiller;
        _orderPool[_fulfiller][_orderId].status = OrderStatus.completed;
        removeOrder(Location.outbox, _requester, _orderId);
        removeOrder(Location.inbox, _fulfiller, _orderId);
        userCanceledRequests[_requester].push(_order.orderId);
        userCanceledRequests[_fulfiller].push(_order.orderId);
        // Return requester's NFT(s)
        for (uint256 i; i < _order.ownedNfts.length; i++) {
            Nft memory ownedNft = Nft({contractAddress: _order.ownedNfts[i], tokenId: _order.ownedNftIds[i]});
            IERC721 _requesterNft = IERC721(ownedNft.contractAddress);
            _requesterNft.safeTransferFrom(address(this), _order.requester, ownedNft.tokenId);
        }
        emit CancelSwapOrder(_orderId);
    }

    // Admin fee withdrawal
    function withdrawFees(address payable _fundsReceipieint, uint256 _amount) external onlyAdmin {
        require(_amount <= address(this).balance, "Insufficient balance");
        (bool success,) = _fundsReceipieint.call{value: _amount}("");
        require(success, "Withdrawal failed");
    }

    function setAdmin(address _newAdmin) external onlyAdmin {
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

    /**
     * @dev Get the order details.
     */
    function getOrder(uint256 _orderId) public view returns (Request memory) {
        return _orderPool[msg.sender][_orderId];
    }

    /**
     * @dev Checks if an order is empty.
     * @param _order is the request to be checked.
     */
    function _isEmpty(Request memory _order) internal pure returns (bool) {
        if (_order.orderId == 0 && _order.requester == address(0)) {
            return true;
        } else {
            return false;
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
