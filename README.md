
# SWORP

## ⚠ Problem
Nft asset exchange between peers on social media can be risky. Often it would require one of the involved parties to
trust the other, usually the person that sends their asset first. another way would be to include an escrow but both parties would have to trust the escrow in this case.


![Live Scanario](./xscenario.PNG "Live Scenario")


## 🛠 Solution
A carefully designed trustless, peer-to-peer NFT swapping protocol for secure, decentralized exchanges of NFTs between two parties without intermediaries while also giving involved parties full control over their assets.


## 🔁Flow Of Actions
* User A (requester) creates a swap order and sends to user B (fulfiller) indicating they would like to swap their Nft(s) for an Nft(s) owned by party B.
* Contract takes custody of user A's Nft(s) and sends the request to user B's inbox
* User B can accept or reject the request. If user B accepts, the swap transaction is executed
* If user B rejects, user A's nft is returned to their wallet.
* user A also has the ability to cancel their request provided it hasn't been accepted/rejected by user B, effectively preventing asset being locked in the contract.

## 👀Current Features
- Trustless Peer to Peer NFT swaps with no central authority
- Swaps involving 1 to 1 NFTs, 1 to many NFTs, many to 1 NFT and many to many NFTs. Maximum NFTs that can be included in a transaction is capped at 15.
- Create, cancel, accept, and reject offers.  

## 🗺 Roadmap
- [ ] 💲 Ability to include tokens within swap order to sweeten deal.**

- [ ] ⛓⛏ Multi Chain Deployment**.

- [ ] 🔗Crosschain nft swapping

