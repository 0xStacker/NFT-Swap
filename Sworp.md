# Solidity API

## RequestLib

### Contract
RequestLib : contracts/Swapper.sol

 --- 
### Functions:
### getReq

```solidity
function getReq(address r, address o, uint256 oid, address rr, uint256 rrid) external pure returns (struct RequestLib.RequestIn)
```

### _isEmpty

```solidity
function _isEmpty(struct RequestLib.Request _request) internal pure returns (bool)
```

_Checks if a request object is empty._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _request | struct RequestLib.Request | is the request to be checked. |

## Swapper

_Trustless NFT swapping implementation bewteen two parties A and B.
Party A sends a swap request to party B indicating they would like to swap
their Nft for an Nft owned by party B.
Contract takes custody of party A's Nft and sends the request to party B's inbox
party B can accept or reject the request. If party B accepts, the swap transaction is executed
If party B rejects, party A's nft is returned to their wallet.
Party A also has the ability to cancel their request provided it hasn't been accepted/rejected by party B._

### Contract
Swapper : contracts/Swapper.sol

Trustless NFT swapping implementation bewteen two parties A and B.
Party A sends a swap request to party B indicating they would like to swap
their Nft for an Nft owned by party B.
Contract takes custody of party A's Nft and sends the request to party B's inbox
party B can accept or reject the request. If party B accepts, the swap transaction is executed
If party B rejects, party A's nft is returned to their wallet.
Party A also has the ability to cancel their request provided it hasn't been accepted/rejected by party B.

 --- 
### Functions:
### requestNftSwap

```solidity
function requestNftSwap(struct RequestLib.RequestIn _inRequest) external
```

Ensures that both requester and requestee owns the nfts required for the tx.
contract takes requester's nft into custody, gives the request an id and sends it to requestee's inbox.

_Send a swap request to a user._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _inRequest | struct RequestLib.RequestIn | holds the request data. see RequestIn struct. |

### acceptRequest

```solidity
function acceptRequest(uint256 _requestId) external
```

### rejectRequest

```solidity
function rejectRequest(uint256 _requestId) public
```

_Reject an incoming request._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _requestId | uint256 | is the identifier for the request. |

### removeRequest

```solidity
function removeRequest(enum Swapper.location _from, address _user, struct RequestLib.Request[] _cache, uint256 _requestId) internal
```

_remove a request from inbox or outbox of a user._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _from | enum Swapper.location | is the location to delete from (inbox or outbox). |
| _user | address | is the user's address. |
| _cache | struct RequestLib.Request[] | is the cached list of the user's inbox or outbox. |
| _requestId | uint256 | is the unique identifier for the request. |

### cancelRequest

```solidity
function cancelRequest(uint256 _requestId) external
```

A requester can only cancel their request if the requestee has not accepted or rejected the request at their end.

_Allows a requester to cancel their request._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _requestId | uint256 | is the identifier of the request. |

### fetchInbox

```solidity
function fetchInbox(address _user) external view returns (struct RequestLib.Request[])
```

### fetchOutbox

```solidity
function fetchOutbox(address _user) external view returns (struct RequestLib.Request[])
```

### fetchAccepted

```solidity
function fetchAccepted(address _user) external view returns (struct RequestLib.Request[])
```

### fetchRejected

```solidity
function fetchRejected(address _user) external view returns (struct RequestLib.Request[])
```

### fetchCanceled

```solidity
function fetchCanceled(address _user) external view returns (struct RequestLib.Request[])
```

### approve

```solidity
function approve(address _user) external
```

_Allow a user to be able to send a swap request._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _user | address | is the user address to be approved. |

### revokeApproval

```solidity
function revokeApproval(address _user) external
```

_Prevent an address from sending a request_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _user | address | is the user address whose approval is to be revoked. |

### onERC721Received

```solidity
function onERC721Received(address, address, uint256, bytes) external pure returns (bytes4)
```

 --- 
### Events:
### RequestSwap

```solidity
event RequestSwap(uint256 _requestId)
```

### AcceptSwap

```solidity
event AcceptSwap(uint256 _requestId)
```

### RejectSwap

```solidity
event RejectSwap(uint256 _requestId)
```

### CancelSwap

```solidity
event CancelSwap(uint256 _requestId)
```

