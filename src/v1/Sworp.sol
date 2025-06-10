//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
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
 * A Trustless tool for peer-to-peer NFT assets exchange.
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
     * @param _orderParams holds the request data. see Request struct.
     */
    function createSwapOrder(PublicOrderParams memory _orderParams) external payable nonReentrant returns (uint256) {
        PublicOrder memory _order = PublicOrder({
            orderId: _nextOrderId++,
            requester: msg.sender,
            fulfiller: _orderParams.fulfiller,
            ownedNfts: _orderParams.ownedNfts,
            requestedNfts: _orderParams.requestedNfts,
            ownedNftIds: _orderParams.ownedNftIds,
            offeringToken: _orderParams.offeringToken,
            requestedToken: _orderParams.requestedToken,
            status: OrderStatus.pending
        });

        if (_order.ownedNfts.length != _order.ownedNftIds.length || _order.ownedNfts.length == 0) {
            revert Swapper__BadOrder();
        }

        if (_order.ownedNfts.length > MAX_TRADEABLE_NFT || _order.requestedNfts.length > MAX_TRADEABLE_NFT) {
            revert Swapper__ERC721LimitExceeded(MAX_TRADEABLE_NFT);
        }

        if (_order.requester == _order.fulfiller) {
            revert Swapper__SelfOrder();
        }

        // Contract takes custody of the requester's nfts.
        for (uint256 i; i < _order.ownedNfts.length; i++) {
            Nft memory ownedNft = Nft({contractAddress: _order.ownedNfts[i], tokenId: _order.ownedNftIds[i]});
            if (ownedNft.contractAddress == address(0)) {
                revert Swapper__BadOrder();
            }

            if (!checkERC721InterfaceSupport(ownedNft.contractAddress)) {
                revert Swapper__BadOrder();
            }
            IERC721 _ownedNft = IERC721(ownedNft.contractAddress);

            // Ensure requester own the nfts involved.
            if (_ownedNft.ownerOf(ownedNft.tokenId) != msg.sender) {
                revert Swapper__NotOwnedByRequester(ownedNft.contractAddress, ownedNft.tokenId);
            } else {
                IERC721(ownedNft.contractAddress).safeTransferFrom(msg.sender, address(this), ownedNft.tokenId);
            }
        }

        // Contract takes custody of requester's tokens if involved
        if (_order.offeringToken.amount > 0) {
            // Native token
            if (_order.offeringToken.contractAddress == address(0)) {
                if (msg.value < _order.offeringToken.amount) {
                    revert Swapper__InsufficientFunds(msg.value);
                }
                (bool success,) = payable(address(this)).call{value: _order.offeringToken.amount}("");
                if (!success) {
                    revert Swapper__EthTransferFailed(address(this), _order.offeringToken.amount);
                }
            } else {
                IERC20 _offeringToken = IERC20(_order.offeringToken.contractAddress);
                if (_offeringToken.balanceOf(msg.sender) < _order.offeringToken.amount) {
                    revert Swapper__InsufficientTokenBalance(
                        _order.offeringToken.contractAddress, _order.offeringToken.amount
                    );
                }
                bool success = _offeringToken.transferFrom(msg.sender, address(this), _order.offeringToken.amount);
                if (!success) {
                    revert Swapper__ERC20TransferFailed(
                        _order.offeringToken.contractAddress, address(this), _order.offeringToken.amount
                    );
                }
            }
        }

        // Store the request in the request pool
        orderMarket[_order.orderId] = _order;
        // Add the order to the order pool.
        orderPool.push(_order.orderId);
        //assign index
        _orderIndexTracker[_order.orderId] = orderPool.length;

        emit CreateSwapOrder(_order.requester, _order.orderId);
        return _order.orderId;
    }

    /**
     * @dev Match public order
     * @notice if fulfiller is not set for an order, anyone with the required asset can match the order,
     * @notice Automatically rejects if the fulfiller no longer hold the required nft.
     */
    function matchOrder(uint256 orderId, Nft[] calldata _match)
        external
        payable
        onlyFulfiller(getOrder(orderId))
        nonReentrant
    {
        PublicOrder memory _order = getOrder(orderId);
        if (_order.status != OrderStatus.pending) {
            revert Swapper__BadOrder();
        }
        _order.fulfiller = _order.fulfiller == address(0) ? msg.sender : _order.fulfiller;

        uint256 totalRequestedNfts = _order.requestedNfts.length;
        uint256 totalOwnedNfts = _order.ownedNfts.length;

        orderMarket[_order.orderId].status = OrderStatus.completed;
        orderMarket[_order.orderId].fulfiller = _order.fulfiller;
        // Ensure that the match data is valid.
        bool matched = _verifyMatchData(_order, _match);
        if (!matched) {
            revert Swapper__BadOrderMatch();
        }

        // remove order from the order pool.
        removeOrder(_order.orderId);

        // Handle orders involving fungible tokens transfers.
        _handleTokens(_order);

        // Handle Nft transfers
        for (uint256 i; i < totalRequestedNfts; i++) {
            Nft memory requestedNft = _match[i];
            IERC721 _orderedNft = IERC721(requestedNft.contractAddress);

            // Ensure that the order fulfiller still has the nft involved.
            if (_orderedNft.ownerOf(_match[i].tokenId) != _order.fulfiller) {
                cancelOrder(_order.orderId);
            } else {
                _orderedNft.safeTransferFrom(_order.fulfiller, _order.requester, requestedNft.tokenId);
            }
        }

        for (uint256 i; i < totalOwnedNfts; i++) {
            Nft memory ownedNft = Nft({contractAddress: _order.ownedNfts[i], tokenId: _order.ownedNftIds[i]});
            IERC721 _ownedNft = IERC721(ownedNft.contractAddress);
            _ownedNft.safeTransferFrom(address(this), _order.fulfiller, ownedNft.tokenId);
        }
        emit MatchSwapOrder(_order.fulfiller, _order.orderId);
    }

    /**
     * @dev Allows a requester to cancel their order.
     * @param _orderId is the identifier of the order.
     * @notice A requester can only cancel their request if the fulfiller has not accepted or rejected the request at their end.
     */
    function cancelOrder(uint256 _orderId) public {
        PublicOrder memory _order = orderMarket[_orderId];
        if (_order.status != OrderStatus.pending) {
            revert Swapper__BadOrder();
        }
        orderMarket[_orderId].status = OrderStatus.completed;
        // remove order from the order pool.
        removeOrder(_orderId);
        for (uint256 i; i < _order.ownedNfts.length; i++) {
            Nft memory ownedNft = Nft({contractAddress: _order.ownedNfts[i], tokenId: _order.ownedNftIds[i]});
            IERC721 _requesterNft = IERC721(ownedNft.contractAddress);
            _requesterNft.safeTransferFrom(address(this), _order.requester, ownedNft.tokenId);
        }
        emit CancelSwapOrder(_order.requester, _orderId);
    }

    /**
     *
     * @dev Handle orders involving fungible tokens
     * @notice defaults to eth if a token address is not set.
     */
    function _handleTokens(PublicOrder memory _order) internal {
        // Native token
        if (_order.requestedToken.contractAddress == address(0)) {
            if (msg.value < _order.requestedToken.amount) {
                revert Swapper__InsufficientFunds(msg.value);
            }

            (bool success,) = payable(_order.requester).call{value: _order.requestedToken.amount}("");
            if (!success) {
                revert Swapper__EthTransferFailed(_order.requester, _order.requestedToken.amount);
            }
        }
        // ERC20 tokens
        else {
            IERC20 token = IERC20(_order.requestedToken.contractAddress);

            if (token.balanceOf(msg.sender) < _order.requestedToken.amount) {
                revert Swapper__InsufficientTokenBalance(
                    _order.requestedToken.contractAddress, _order.requestedToken.amount
                );
            }
            bool success = token.transferFrom(msg.sender, _order.requester, _order.requestedToken.amount);
            if (!success) {
                revert Swapper__ERC20TransferFailed(
                    _order.requestedToken.contractAddress, _order.requester, _order.requestedToken.amount
                );
            }
        }

        // transfer offering fungible tokens to fulfiller.
        if (_order.offeringToken.amount > 0) {
            // Native token
            if (_order.offeringToken.contractAddress == address(0)) {
                if (address(this).balance < _order.offeringToken.amount) {
                    revert Swapper__InsufficientFunds(address(this).balance);
                }
                (bool success,) = payable(_order.fulfiller).call{value: _order.offeringToken.amount}("");
                if (!success) {
                    revert Swapper__EthTransferFailed(_order.fulfiller, _order.offeringToken.amount);
                }
            }
            // ERC20 tokens
            else {
                IERC20 token = IERC20(_order.offeringToken.contractAddress);
                if (token.balanceOf(address(this)) < _order.offeringToken.amount) {
                    revert Swapper__InsufficientAllowance(
                        _order.offeringToken.contractAddress, _order.offeringToken.amount
                    );
                }
                bool success = token.transfer(_order.fulfiller, _order.offeringToken.amount);
                if (!success) {
                    revert Swapper__ERC20TransferFailed(
                        _order.offeringToken.contractAddress, _order.fulfiller, _order.offeringToken.amount
                    );
                }
            }
        }
    }

    /**
     *
     * @dev verify that the assets provided by the matcher can beused
     */
    function _verifyMatchData(PublicOrder memory _order, Nft[] calldata _match) internal pure returns (bool) {
        // Verify that the match contract address is valid as required by the order.
        for (uint256 i; i < _order.requestedNfts.length; i++) {
            bool matched;
            for (uint256 j; j < _match.length; j++) {
                // match found
                if (_order.requestedNfts[i] == _match[j].contractAddress) {
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                return false;
            }
        }
        return true;
    }
}
