// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface ISwapperErrors {
    error Swapper__NotOwnedByRequester(address _nft, uint256 _id);
    error Swapper__NotOwnedByRequestee(address _nft, uint256 _id);
    error Swapper__SelfOrder();
    error Swapper__InvalidAddress();
    error Swapper__NotApproved(address requester);
    error Swapper__BadOrder();
    error Swapper__InvalidFulfiller(address impersonator);
    error Swapper__FulfillerInboxFull(uint8 size);
    error Swapper__NotAdmin(address _user);
    error Swapper__InsufficientOrderFee(uint256 _fee);

    event CreateSwapOrder(address indexed _from, address _to, uint256 _requestId);
    event CreateSwapOrderMulti(address indexed _from, address _to, uint256 _requestId);
    event FufillSwapOrder(uint256 _requestId);
    event RejectSwapOrder(uint256 _requestId);
    event CancelSwapOrder(uint256 _requestId);
}
