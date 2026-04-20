# NFT Marketplace DApp

Full-stack Web3 NFT marketplace — Next.js 15 frontend for the refactored `NFTMarketplace` Solidity contract deployed on Sepolia.

## Contract

- **Network:** Ethereum Sepolia
- **Address:** `0x340C12a94DD8BB553E2259884079B99afc132b8a`
- **Payments:** ETH, USDC, USDT
- **Royalties:** EIP-2981 (basis points)

## Stack

| Layer | Tech |
|-------|------|
| Framework | Next.js 15 (Pages Router) |
| Wallet | wagmi v2 + RainbowKit + viem |
| Styling | Tailwind CSS v3 + framer-motion |
| IPFS | Pinata |
| State | TanStack Query v5 |

## Setup

```bash
cp .env.local.example .env.local
# Fill in .env.local (see below)
npm install
npm run dev
```

## .env.local

```
NEXT_PUBLIC_APP_NAME=NFT Marketplace DApp
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=eb0a56565e9ca9dc894545836b50ae42
NEXT_PUBLIC_CONTRACT_ADDRESS=0x340C12a94DD8BB553E2259884079B99afc132b8a
NEXT_PUBLIC_CHAIN_ID=11155111
NEXT_PUBLIC_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_ALCHEMY_KEY
NEXT_PUBLIC_USDC_ADDRESS=<your_sepolia_usdc_address>
NEXT_PUBLIC_USDT_ADDRESS=<your_sepolia_usdt_address>
NEXT_PUBLIC_PINATA_JWT=<your_pinata_jwt>
NEXT_PUBLIC_PINATA_GATEWAY_URL=https://gateway.pinata.cloud/ipfs/
NEXT_PUBLIC_FORMSPREE_API=xo555bdn
```

## Pages

| Route | Description |
|-------|-------------|
| `/` | Landing page with stats, FAQ, newsletter |
| `/dashboard` | Marketplace — browse & buy NFTs (ETH/USDC/USDT) |
| `/create` | Mint new NFT (3-step wizard, IPFS upload) |
| `/my-nfts` | My collection — view, relist, **cancel listing** |
| `/my-listings` | My active listings — edit prices, **cancel listing** |
| `/activity` | Live activity feed |
| `/analytics` | Analytics & charts |
| `/admin` | Admin panel (owner only) |

## Contract Changes vs Original

| Old | New |
|-----|-----|
| `royaltyPercentage` (uint256) | `royaltyBps` (uint16, aliased) |
| `getTotalItemsSold()` | `getTotalSold()` |
| `platformFeePercentage` | `platformFeeBps` |
| `emergencyWithdrawTimestamp` | `emergencyWithdrawUnlockAt` |
| ❌ no cancel | `cancelListing(tokenId)` ✅ |
| `tokenListingFees` (dead) | Removed |
| `usdcAddress`/`usdtAddress` | `USDC()`/`USDT()` |
