/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  images: {
    unoptimized: true,
    remotePatterns: [
      { protocol: "https", hostname: "gateway.pinata.cloud" },
      { protocol: "https", hostname: "ipfs.io" },
      { protocol: "https", hostname: "cloudflare-ipfs.com" },
      { protocol: "https", hostname: "nftstorage.link" },
    ],
  },
  transpilePackages: [
    "@rainbow-me/rainbowkit",
    "@walletconnect/ethereum-provider",
    "@walletconnect/universal-provider",
  ],
  webpack: (config) => {

    config.resolve.alias = {
      ...config.resolve.alias,
      "@react-native-async-storage/async-storage": false,
    };

    config.resolve.fallback = {
      ...config.resolve.fallback,
      fs: false,
      net: false,
      tls: false,
      crypto: false,
      stream: false,
      http: false,
      https: false,
      zlib: false,
      path: false,
      os: false,
    };
    config.externals.push(
      "utf-8-validate",
      "bufferutil",
      "pino-pretty",
      "lokijs",
      "encoding"
    );
    return config;
  },
};

module.exports = nextConfig;