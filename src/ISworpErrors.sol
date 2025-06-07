// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface ISworpErrors {
    error Swapper__NotOwnedByRequester(address nft, uint256 id);
    error Swapper__NotOwnedByRequestee(address nft, uint256 id);
    error Swapper__SelfOrder();
    error Swapper__InvalidAddress();
    error Swapper__NotApproved(address requester);
    error Swapper__BadOrder();
    error Swapper__ERC721LimitExceeded(uint limit);
    error Swapper__BadOrderMatch();
    error Swapper__InvalidMatcher(address matcher);
    error Swapper__NotAdmin(address user);
    error Swapper__InsufficientFunds(uint256 funds);
    error Swapper__InsufficientAllowance(address token, uint256 amount);
    error Swapper__InsufficientTokenBalance(address token, uint256 amount);
    error Swapper__EthTransferFailed(address to, uint256 amount);
    error Swapper__ERC20TransferFailed(address token, address to, uint256 amount);

    event CreateSwapOrder(address indexed creator, uint256 orderId);
    event MatchSwapOrder(address matcher, uint256 orderId);
    event CancelSwapOrder(address creator, uint256 orderId);
}
