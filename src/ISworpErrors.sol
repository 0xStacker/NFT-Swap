// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface ISworpErrors {
    error Swapper__NotOwnedByRequester(address nft, uint256 id);
    error Swapper__NotOwnedByRequestee(address nft, uint256 id);
    error Swapper__SelfOrder();
    error Swapper__InvalidAddress();
    error Swapper__NotApproved(address requester);
    error Swapper__BadOrder();
    error Swapper__BadOrderMatch();
    error Swapper__InvalidFulfiller(address impersonator);
    error Swapper__FulfillerInboxFull(uint8 size);
    error Swapper__NotAdmin(address user);
    error Swapper__InsufficientOrderFee(uint256 fee);
    error Swapper__InsufficientAllowance(address token, uint256 amount);
    error Swapper__InsufficientTokenBalance(address token, uint256 amount);
    error Swapper__EthTransferFailed(address to, uint256 amount);
    error Swapper__ERC20TransferFailed(address token, address to, uint256 amount);

    event CreateSwapOrder(address indexed from, address to, uint256 orderId);
    event CreateSwapOrderMulti(address indexed from, address to, uint256 orderId);
    event FufillSwapOrder(uint256 orderId);
    event RejectSwapOrder(uint256 orderId);
    event CancelSwapOrder(uint256 orderId);
}
