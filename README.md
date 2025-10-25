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

## Flowcharts:
| Deposit                           | Trading                           |
| --------------------------------- | --------------------------------- |
| ![deposit](assets/Deposit.png)    | ![trading](assets/Trading.png)    |


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

- We want to bring this tool primarly in the hands of hackathons in order for hackers to be able get a picture of the credibility of a company and wether or not they are likely to pay the bounties to the winning hackers.

## Links

- [Devfolio](https://devfolio.co/projects/sloth-shaming-bea7)
- [Vercel](https://sloths-warsaw.vercel.app/)
- [Github](https://github.com/warsaw-hackers/Sloth-Shaming)

### Deployments
- [Deployment Celo](https://explorer.celo.org/alfajores/address/0x81afFbf9392a1402B44B8b6C45C89F602657b3eF)
- [Deployment Sei](https://seitrace.com/address/0xF519289Ed67326514c6Eb47851f9e605DC8ad640?chain=pacific-1)
- [Deployment Zircuit](https://explorer.testnet.zircuit.com/address/0x81afFbf9392a1402B44B8b6C45C89F602657b3eF)
- [Deployment Mantle](https://explorer.sepolia.mantle.xyz/address/0xF519289Ed67326514c6Eb47851f9e605DC8ad640?tab=txs)
- [Deployment Optimism](https://sepolia-optimism.etherscan.io/address/0xBf8C8Ef202C8D14f8657f6E476c0F115906c773D)




## Team

- [0xshazam.eth](https://x.com/0xshazam)
- [0xjsi.eth](https://x.com/0xjsieth)
- [nhestrompia.eth](https://x.com/nhestrompia)
- [parham](https://x.com/khodedawsh)
