<h1 align="center">
🐒🐒🐒 Macaque 🐒🐒🐒
</h1>

<h4 align="center">
  <p align="center">
    <img src="./assets/Logo.jpg" alt="Logo" width="300" height="auto">
  </p>
  <a href="https://sloths-warsaw.vercel.app/">Website</a>
</h4>

🐒 Macaque is a decentralized software stack that allows anyone to spin up their own Macaque Virtual Trading Chain (MVTC), completely chain and chain architecture agnostic. Building with this stack, builders can offer users slippage free cross chain trading at CEX level speed, with DEX level certainty.

- 💅 **Off-chain execution, on chain bookkeeping**: Orders a sent and matched within our off chain matching engine, and through the power of Vincent, we can orchestrate sophisticated fund managements, while bookkeeping everything transparently.
- ⛓️ **No more unnecessary dappchains**: Thanks to the power of EVVM, each MVTC is deployed as a virtual blockchain within a smart contract, running on an already existing EVM, minimizing the ever growing chain fragmentation problem
- 🤑 **No slippage**: Since we're matching all orders through a CLOB, users can trade safely knowing that they won't suffer any loss of funds due to slippage.
- 🌉 **Interops with already existing crosschain standards**: Since we're building Macaque from the ground up to be crosschain, we are fully utilizing [the CAIP10 standard](https://chainagnostic.org/CAIPs/caip-10)

## 🪏 Deeply integrated into the EVVM

Since MVTC's are app chains, we needed our functionality to play well along side the already existing infrastructure EVVM has. We also wanted to work some of our incentive mechanism to play well together with the EVVM mechanisms. Here are the ways that we try to utilize the EVVM to the maximum:
1. CAIP10 - we extended the core EVVM contracts to work with CAIP10 addresses, since this was needed for our bookkeeping.
2. EVVM Naming Service - our contracts are utilizing the EVVM Naming Service which can be used to set the evm withdrawal address.
3. Discount for EVVM stakers - for the real OGs that are staking on EVVM, they can enjoy 50% off on the fees, which are drawn on withdrawal.

## Screenshots:
| Landing Page                      | Order Book                        |
| --------------------------------- | --------------------------------- |
| ![deposit](assets/Screen1.jpg)    | ![trading](assets/Screen2.jpg)    |


## Diagrams
### Deposit
![deposit](assets/Deposit.png)

### Trading
![trading](assets/Trading.png)

## Bounties 😎

### Lit Protocol - Best DeFi automation Vincent Apps
This is a cross chain first dapp, and we've used Lit Protocols Vincent platform to be able to operate across multiple chain architecture

### EVVM - Most Innovative Use of EVVM’s Execution Function
Our whole system is deeply integrated into the EVVM, and we've included functions following the executor model.

## Next steps

- We're excited about this tech and would love to deepdive further into it. Mainly pushing the boundaries of whats possible utilizing the EVVM, and fishers, for improved trading UX as we see this as a possible better UX than most centralized services provides

## Links

- [Github](https://github.com/ETHOnline2025)
- [Vercel]()
- [Eth Global Submission](https://ethglobal.com/showcase/macaque-dnymr)

### Deployments Base sepolia
- [Trading](https://sepolia.basescan.org/address/0x0b4aec45bb5f3f70cc6cdb9771c850ff20d812a4)
- [EVVM](https://sepolia.basescan.org/address/0x934df9734a2f18f68714e627d80d1b4caea9f9aa)
- [Staking](https://sepolia.basescan.org/address/0xdc7d06ac7dcdb73bcdb79dadc20ab971d83539c3)
- [NameService](https://sepolia.basescan.org/address/0x456773190f3b3447a4885655df6a1bfcb0c4dbfe)
- [Treasury](https://sepolia.basescan.org/address/0xd120f54bd13c41e95b032dbd42f89c1a4f6c53bb)

## Team

- [0xshazam.eth](https://x.com/0xshazam)
- [0xjsi.eth](https://x.com/0xjsieth)
- [nhestrompia.eth](https://x.com/nhestrompia)
- [parham](https://x.com/khodedawsh)
