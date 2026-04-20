// Pure utility helpers — no ethers dependency, viem only.

export const formatAddress = (address) => {
  if (!address) return "";
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
};

export const formatTokenSymbol = (paymentToken) => {
  switch (paymentToken) {
    case 0: return "ETH";
    case 1: return "USDC";
    case 2: return "USDT";
    default: return "Unknown";
  }
};

export const getTokenDecimals = (paymentToken) => {
  switch (paymentToken) {
    case 0: return 18;
    case 1: return 6;
    case 2: return 6;
    default: return 18;
  }
};

/**
 * Converts royaltyBps (basis points, 0–10000) to a human-readable percentage string.
 * e.g. 500 → "5.00%"
 */
export const formatRoyaltyBps = (bps) =>
  `${(bps / 100).toFixed(2)}%`;

/**
 * Converts a percentage (e.g. 5) to basis points (500).
 */
export const pctToBps = (pct) => Math.round(pct * 100);

/**
 * Converts basis points (500) to a percentage (5).
 */
export const bpsToPct = (bps) => bps / 100;

export const formatPrice = (price, decimals = 18) =>
  formatUnits(BigInt(price.toString()), decimals);