import { sepolia } from "wagmi/chains";
import { getDefaultConfig } from "@rainbow-me/rainbowkit";

export const config = getDefaultConfig({
  appName: process.env.NEXT_PUBLIC_APP_NAME || "NFT Marketplace DApp",
  projectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID,
  chains: [sepolia],
  ssr: true,
}
);