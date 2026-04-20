export const contractConfig = {
  address: process.env.NEXT_PUBLIC_CONTRACT_ADDRESS,
  usdcAddress: process.env.NEXT_PUBLIC_USDC_ADDRESS,
  usdtAddress: process.env.NEXT_PUBLIC_USDT_ADDRESS,
  chainId: parseInt(process.env.NEXT_PUBLIC_CHAIN_ID || "11155111"),
  rpcUrl: process.env.NEXT_PUBLIC_RPC_URL,
};

export const pinataConfig = {
  jwt: process.env.NEXT_PUBLIC_PINATA_JWT,
  gatewayUrl:
    process.env.NEXT_PUBLIC_PINATA_GATEWAY_URL ||
    "https://gateway.pinata.cloud/ipfs/",
};

// Matches contract enum PaymentToken { ETH=0, USDC=1, USDT=2 }
export const PaymentToken = {
  ETH: 0,
  USDC: 1,
  USDT: 2,
};

// Matches contract BPS_BASE = 10_000
export const BPS_BASE = 10000;
// Matches contract MAX_ROYALTY_BPS = 1_000 (10%)
export const MAX_ROYALTY_BPS = 1000;