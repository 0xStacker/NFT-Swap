//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {ISworpErrors} from "./ISworpErrors.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";

abstract contract SworpUtils is ISworpErrors {
    // Inbox limit.
    uint8 internal constant FULFILLER_INBOX_LIMIT = 10;

    // Maximum number of nfts that can be included in a single transaction.
    uint8 internal constant MAX_TRADEABLE_NFT = 5;

    // Admin address.
    address internal _admin;

    // Order id counter.
    uint256 internal _nextOrderId;

    // pending pool contains all pending orders.

    uint256[] public orderPool;

    // order market contains all the created orders
    mapping(uint256 => PublicOrder) orderMarket;

    // Keeps track of order index in pool for removal
    mapping(uint256 => uint256) internal _orderIndexTracker;

    // Supported ERC20 tokens
    mapping(address => bool) private _supportedTokens;
    address[] internal _supportedTokensReturnable;

    // User's approved addresses. Only adresses aproved by user can send nft swap requests.
    mapping(address => mapping(address => bool)) public approvedAddresses;

    // NOTICE: completed order status mean the order has been accepted, rejected or canceled.
    enum OrderStatus {
        pending,
        completed
    }

    struct Nft {
        address contractAddress;
        uint256 tokenId;
    }

    struct FungibleToken {
        address contractAddress;
        uint256 amount;
    }

    /**
     * @dev Struct to collect the request data for orders.
     * @notice If fulfiller is not set, and requestedNftIds are not specified,
     *  the order is public and can be fulfilled by anyone with the right asset.
     * @notice If fulfiller is set, the order is private and can only be fulfilled by the specified fulfiller.
     * @notice The order can be a combination of NFTs and fungible tokens as shown below:
     * NFT => NFT
     * NFT => FT
     * NFT => FT + NFT
     * NFT + FT => NFT + FT
     * NFT + FT => NFT
     *
     */
    struct PublicOrderParams {
        address fulfiller;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        FungibleToken offeringToken;
        FungibleToken requestedToken;
    }

    // Finalized order data after order has been given an id.
    struct PublicOrder {
        address requester;
        address fulfiller;
        uint256 orderId;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        FungibleToken requestedToken;
        FungibleToken offeringToken;
        OrderStatus status;
    }

    struct DirectSwapOrderIn {
        address fulfiller;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        uint256[] requestedNftIds;
        FungibleToken requestedToken;
        FungibleToken offeringToken;
    }

    // Struct to collect the request data for cross-chain orders.
    struct xChainOrderIn {
        uint64 dstChainId;
        address fulfiller;
        address[] ownedNfts;
        address[] requestedNfts;
        uint256[] ownedNftIds;
        uint256[] requestedNftIds;
    }

    // Struct to hold the finalized cross-chain order data.
    struct xChainOrder {
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

    modifier onlyFulfiller(PublicOrder memory _order) {
        if (_order.fulfiller != address(0) && msg.sender != _order.fulfiller) {
            revert Swapper__InvalidMatcher(_order.fulfiller);
        }
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != _admin) {
            revert Swapper__NotAdmin(msg.sender);
        }
        _;
    }

    /**
     * @dev Add an ERC20 token to the list of tokens that can be used in orders.
     */
    function whitelistToken(address _token) external onlyAdmin {
        _supportedTokens[_token] = true;
        _supportedTokensReturnable.push(_token);
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
     * @param _orderId is the unique identifier for the request.
     */
    function removeOrder(uint256 _orderId) internal virtual {
        // Locate order index
        uint256 orderIndex = _orderIndexTracker[_orderId];
        require(orderIndex != 0, "Item not in pending");
        uint256 itemIndex = --orderIndex;
        uint256 lastItem = orderPool[orderPool.length - 1];
        // Swap the order with the last item in the array and remove the last item
        orderPool[itemIndex] = lastItem;
        orderPool.pop();
        _orderIndexTracker[lastItem] = ++itemIndex;
        _orderIndexTracker[_orderId] = 0;
    }

    function setAdmin(address _newAdmin) external virtual onlyAdmin {
        _admin = _newAdmin;
    }

    function admin() external view returns (address) {
        return _admin;
    }

    /**
     * @dev Prevent an address from sending a request
     * @param _user is the user address whose approval is to be revoked.
     */
    function revokeSworpApproval(address _user) external {
        approvedAddresses[msg.sender][_user] = false;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function fetchPendingOrders() external view returns (uint256[] memory) {
        return orderPool;
    }

    /**
     * @dev Get the order details.
     */
    function getOrder(uint256 _orderId) public view returns (PublicOrder memory) {
        return orderMarket[_orderId];
    }
}
