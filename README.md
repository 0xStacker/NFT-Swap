
# SWORP
A trustless, peer to peer NFT swapping tool built for secure exchanges between two parties. This project enhances exchange of NFTs between users without intermediaries.
## 🔍Overview
Sworp allows users to:

- **Create swap Order:** Propose an exchange to another user by specifying the NFTs you wish to offer and the NFTs you desire in return.

- **Accept Orders**: Agree to swap proposals sent to you, facilitating a direct exchange.

- **Reject Orders**: 
    Reject a swap proposal if you're not happy with the deal.

- **Cancel pending Orders**: Withdraw your swap proposal before they're accepted. 


## 🛠How It Works

 - Party A (requester) creates a swap order and sends to party B (fulfiller) indicating they would like to swap their Nft(s) for an Nft(s) owned by party B.
 - Contract takes custody of party A's Nft(s) and sends the request to party B's inbox
 - party B can accept or reject the request. If party B accepts, the swap transaction is executed
 - If party B rejects, party A's nft is returned to their wallet.
 - Party A also has the ability to cancel their request provided it hasn't been accepted/rejected by party B.
 - The contract allows for multiple nfts to be involved in a single transaction.
## 👀Features
- Trustless Peer to Peer NFT swaps with no central authority
- Swaps involving 1 to 1 NFTs, 1 to many NFTs, many to 1 NFT and many to many NFTs. Maximum NFTs that can be included in a transaction is capped at 15.


## 🗺Roadmap

-  **💲 Ability to include tokens within swap order to sweeten deal.**

- **🛠 Front End deployment**

- **🛠 Testnet Deployment**

- **🤹‍♀️ERC-1155 Support:**    
Extend functionalities to support multi token standards.

- **⛓⛏ Multi Chain Deployment**.

- **⛓💱 Multi Chain Swapping:** 
    Allow users on one chain to exchange their nfts with users on another chain. assets would retain their native chain.
