import Head from "next/head";
import { WagmiProvider } from "wagmi";
import { RainbowKitProvider } from "@rainbow-me/rainbowkit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "react-hot-toast";
import { config } from "../lib/wagmi";

import "@rainbow-me/rainbowkit/styles.css";
import "../styles/globals.css";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 2, staleTime: 30_000 },
  },
});

function MyApp({ Component, pageProps }) {
  return (
    <>
      <Head>
        <title>NFT Marketplace DApp</title>
        <meta
          name="description"
          content="Production-grade Web3 NFT Marketplace — Sepolia Testnet"
        />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <link rel="icon" href="/logo3.jpg" />
      </Head>

      <WagmiProvider config={config}>
        <QueryClientProvider client={queryClient}>
          <RainbowKitProvider>
            <Component {...pageProps} />
            <Toaster
              position="top-right"
              toastOptions={{
                duration: 4000,
                style: { background: "#1e1b2e", color: "#fff" },
                success: { duration: 3000 },
                error: { duration: 5000 },
              }}
            />
          </RainbowKitProvider>
        </QueryClientProvider>
      </WagmiProvider>
    </>
  );
}

export default MyApp;