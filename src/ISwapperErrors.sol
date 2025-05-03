// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface ISwapperErrors {
    error Swapper__NotOwnedByRequester(address _nft, uint256 _id);
    error Swapper__NotOwnedByRequestee(address _nft, uint256 _id);
    error Swapper__SelfRequest();
    error Swapper__InvalidAddress();
    error Swapper__NotApproved(address requester);
    error Swapper__BadRequest();
    error Swapper__InvalidRequestee(address impersonator);
    error Swapper__RequesteeInboxFull(uint8 size);
    error Swapper__NotAdmin(address _user);
}