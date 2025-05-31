//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {SworpUtils} from "../SworpUtils.sol";

/**
 * /$$$$$$  /$$      /$$  /$$$$$$  /$$$$$$$  /$$$$$$$                     /$$
 *  /$$__  $$| $$  /$ | $$ /$$__  $$| $$__  $$| $$__  $$                  /$$$$
 * | $$  \__/| $$ /$$$| $$| $$  \ $$| $$  \ $$| $$  \ $$       /$$    /$$|_  $$
 * |  $$$$$$ | $$/$$ $$ $$| $$  | $$| $$$$$$$/| $$$$$$$/      |  $$  /$$/  | $$
 *  \____  $$| $$$$_  $$$$| $$  | $$| $$__  $$| $$____/        \  $$/$$/   | $$
 *  /$$  \ $$| $$$/ \  $$$| $$  | $$| $$  \ $$| $$              \  $$$/    | $$
 * |  $$$$$$/| $$/   \  $$|  $$$$$$/| $$  | $$| $$               \  $/    /$$$$$$
 *  \______/ |__/     \__/ \______/ |__/  |__/|__/                \_/    |______/
 *
 *
 * @title Sworp
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
contract SworpV1 is Initializable, ReentrancyGuardUpgradeable, SworpUtils {
    constructor() {
        _disableInitializers();
    }

    function initialize(address _adminAddress) external initializer {
        __ReentrancyGuard_init();
        _admin = _adminAddress;
        _nextOrderId = 1;
    }

    receive() external payable {}

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
        if (_order.status != OrderStatus.pending) {
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
        if (_order.status != OrderStatus.pending) {
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
     * @dev Allows a requester to cancel their request.
     * @param _orderId is the identifier of the request.
     * @notice A requester can only cancel their request if the fulfiller has not accepted or rejected the request at their end.
     */
    function cancelOrder(address _to, uint256 _orderId) external {
        Request memory _order = _orderPool[_to][_orderId];
        if (_order.status != OrderStatus.pending) {
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
}
