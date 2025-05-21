
# SWORP
Sworp is a trustless, peer-to-peer NFT swapping protocol designed for secure, decentralized exchanges between two parties without intermediaries.

## 🔍Overview
Sworp allows users to:

- **Create Swap Order:** Propose an exchange to another user by specifying the NFTs you wish to offer and the NFTs you desire in return.

- **Accept Orders**: Agree to swap proposals sent to you, facilitating a direct exchange.

- **Reject Orders**: 
    Reject a swap proposal if you're not happy with the deal.

- **Cancel Pending Orders**: Withdraw your swap proposal before they're accepted. 


## 🛠How It Works

 - Party A (requester) creates a swap order and sends to party B (fulfiller) indicating they would like to swap their Nft(s) for an Nft(s) owned by Party B.
 - Contract takes custody of Party A's Nft(s) and sends the request to Party B's inbox
 - Party B can accept or reject the request. If Party B accepts, the swap transaction is executed
 - If Party B rejects, Party A's nft is returned to their wallet.
 - Party A also has the ability to cancel their request provided it hasn't been accepted/rejected by Party B.
 - The contract allows for multiple nfts to be involved in a single transaction.

## 👀Current Features
- Trustless Peer to Peer NFT swaps with no central authority
- Swaps involving 1 to 1 NFTs, 1 to many NFTs, many to 1 NFT and many to many NFTs. Maximum NFTs that can be included in a transaction is capped at 15.
- Create, cancel, accept, adn reject proposals.  

## 🕔 Upcoming Features
-  **💲 Ability to include tokens within swap order to sweeten deal.**

- **⛓⛏ Multi Chain Deployment**.

- **⛓💱 Multi Chain Swapping:** 
    Allow users on one chain to exchange their nfts with users on another chain. assets would retain their native chain.

- 