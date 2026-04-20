/**
 * @file functions.js
 * @description Viem-based contract interaction helpers for NFTMarketplace.
 *
 * Field mapping from old → new contract:
 *   royaltyPercentage → royaltyBps
 *   getTotalItemsSold → getTotalSold
 *   platformFeePercentage → platformFeeBps
 *   emergencyWithdrawTimestamp → emergencyWithdrawUnlockAt
 *   MAX_ROYALTY_PERCENTAGE → MAX_ROYALTY_BPS
 *   PERCENTAGE_BASE → BPS_BASE
 *   MAX_LISTING_PRICE → MAX_LISTING_FEE
 *   usdcAddress/usdtAddress state vars → REMOVED (use env)
 *   NEW: cancelListing(tokenId)
 */

import { createPublicClient, http, getContract as viemGetContract } from "viem";
import { parseEther, parseUnits, formatEther, formatUnits } from "viem";
import { sepolia } from "viem/chains";
import { contractConfig } from "./config";

import NFTMarketplaceABI from "../../abi/NFTMarketplace-abi.json";
import ERC20ABI from "../../abi/MockERC20-abi.json";

// ─── Client helpers ──────────────────────────────────────────────────────────

const getPublicClient = () =>
  createPublicClient({
    chain: sepolia,
    transport: http(
      contractConfig.rpcUrl ||
        "https://eth-sepolia.g.alchemy.com/v2/demo"
    ),
  });

const getReadContract = (publicClient) =>
  viemGetContract({
    address: contractConfig.address,
    abi: NFTMarketplaceABI,
    client: publicClient,
  });

const getWriteContract = (walletClient) =>
  viemGetContract({
    address: contractConfig.address,
    abi: NFTMarketplaceABI,
    client: walletClient,
  });

const getERC20Contract = (tokenAddress, client) =>
  viemGetContract({
    address: tokenAddress,
    abi: ERC20ABI,
    client,
  });

// ─── Shared item normaliser ───────────────────────────────────────────────────

/**
 * Converts a raw on-chain MarketItem struct to a plain JS object.
 * Handles the royaltyBps rename (was royaltyPercentage in the old contract).
 */
const normaliseItem = (item, tokenURI = "") => ({
  tokenId: item.tokenId.toString(),
  seller: item.seller,
  owner: item.owner,
  ethPrice: formatEther(item.ethPrice),
  usdcPrice: formatUnits(item.usdcPrice, 6),
  usdtPrice: formatUnits(item.usdtPrice, 6),
  sold: item.sold,
  listedAt: new Date(Number(item.listedAt) * 1000),
  // NEW field name in refactored contract
  royaltyBps: Number(item.royaltyBps),
  royaltyRecipient: item.royaltyRecipient,
  tokenURI,
});

const fetchTokenURI = async (contract, tokenId) => {
  try {
    return await contract.read.tokenURI([tokenId]);
  } catch {
    return "";
  }
};

// ─── READ FUNCTIONS ───────────────────────────────────────────────────────────

export const getListingPrice = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    const price = await contract.read.getListingPrice();
    return formatEther(price);
  } catch (error) {
    throw new Error(`Failed to get listing price: ${error.message}`);
  }
};

export const getMarketItem = async (publicClient, tokenId) => {
  try {
    const contract = getReadContract(publicClient);
    const item = await contract.read.getMarketItem([BigInt(tokenId)]);
    const tokenURI = await fetchTokenURI(contract, item.tokenId);
    return normaliseItem(item, tokenURI);
  } catch (error) {
    throw new Error(`Failed to get market item: ${error.message}`);
  }
};

export const fetchMarketItems = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    const items = await contract.read.fetchMarketItems();
    return Promise.all(
      items.map(async (item) => {
        const tokenURI = await fetchTokenURI(contract, item.tokenId);
        return normaliseItem(item, tokenURI);
      })
    );
  } catch (error) {
    throw new Error(`Failed to fetch market items: ${error.message}`);
  }
};

export const fetchMyNFTs = async (publicClient, userAddress) => {
  try {
    const contract = getReadContract(publicClient);
    const totalTokens = await contract.read.getTotalTokens();
    if (totalTokens === 0n) return [];

    const userNFTs = [];
    for (let i = 1; i <= Number(totalTokens); i++) {
      try {
        const [marketItem, actualOwner] = await Promise.all([
          contract.read.getMarketItem([BigInt(i)]),
          contract.read.ownerOf([BigInt(i)]),
        ]);

        const user = userAddress.toLowerCase();

        const isMarketOwner = marketItem.owner.toLowerCase()  === user;
        const isActualOwner = actualOwner.toLowerCase()       === user;
        const isSeller      = marketItem.seller.toLowerCase() === user; // ← qo'shildi

        if (isMarketOwner || isActualOwner || isSeller) {
          const tokenURI = await fetchTokenURI(contract, BigInt(i));
          userNFTs.push({
            ...normaliseItem(marketItem, tokenURI),
            actualOwner,
            isListed:
              marketItem.owner.toLowerCase() ===
              contractConfig.address.toLowerCase(),
          });
        }
      } catch {
        // token doesn't exist or other error — skip
      }
    }
    return userNFTs;
  } catch (error) {
    throw new Error(`Failed to fetch user NFTs: ${error.message}`);
  }
};

export const fetchItemsListed = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    const items = await contract.read.fetchItemsListed();
    return Promise.all(
      items.map(async (item) => {
        const tokenURI = await fetchTokenURI(contract, item.tokenId);
        return normaliseItem(item, tokenURI);
      })
    );
  } catch (error) {
    throw new Error(`Failed to fetch listed items: ${error.message}`);
  }
};

export const getTotalStats = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    // NEW: getTotalSold (was getTotalItemsSold)
    const [totalTokens, totalSold] = await Promise.all([
      contract.read.getTotalTokens(),
      contract.read.getTotalSold(),
    ]);
    return {
      totalTokens: Number(totalTokens),
      totalSold: Number(totalSold),
      totalListed: Number(totalTokens) - Number(totalSold),
    };
  } catch (error) {
    throw new Error(`Failed to get total stats: ${error.message}`);
  }
};

export const getTokenURI = async (publicClient, tokenId) => {
  try {
    const contract = getReadContract(publicClient);
    return await contract.read.tokenURI([BigInt(tokenId)]);
  } catch (error) {
    throw new Error(`Failed to get token URI: ${error.message}`);
  }
};

// ─── WRITE FUNCTIONS ──────────────────────────────────────────────────────────

const _waitReceipt = async (hash) => {
  const pub = getPublicClient();
  const receipt = await pub.waitForTransactionReceipt({ hash });
  return { hash, receipt, wait: () => Promise.resolve(receipt) };
};

export const createToken = async (
  walletClient,
  tokenURI,
  prices,
  royaltyBps = 0,        // uint16 in new contract
  royaltyRecipient = null
) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");

    const contract = getWriteContract(walletClient);
    const listingPrice = await contract.read.getListingPrice();

    const priceParams = {
      ethPrice: prices.ethPrice ? parseEther(prices.ethPrice.toString()) : 0n,
      usdcPrice: prices.usdcPrice
        ? parseUnits(prices.usdcPrice.toString(), 6)
        : 0n,
      usdtPrice: prices.usdtPrice
        ? parseUnits(prices.usdtPrice.toString(), 6)
        : 0n,
    };

    if (
      priceParams.ethPrice === 0n &&
      priceParams.usdcPrice === 0n &&
      priceParams.usdtPrice === 0n
    ) {
      throw new Error("At least one price must be set");
    }

    const hash = await contract.write.createToken(
      [
        tokenURI,
        priceParams,
        royaltyBps,                                         // uint16
        royaltyRecipient || walletClient.account.address,
      ],
      { value: listingPrice }
    );

    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to create token: ${error.message}`);
  }
};

export const updateItemPrices = async (walletClient, tokenId, prices) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");

    const contract = getWriteContract(walletClient);
    const priceParams = {
      ethPrice: prices.ethPrice ? parseEther(prices.ethPrice.toString()) : 0n,
      usdcPrice: prices.usdcPrice
        ? parseUnits(prices.usdcPrice.toString(), 6)
        : 0n,
      usdtPrice: prices.usdtPrice
        ? parseUnits(prices.usdtPrice.toString(), 6)
        : 0n,
    };

    const hash = await contract.write.updateItemPrices([
      BigInt(tokenId),
      priceParams,
    ]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to update item prices: ${error.message}`);
  }
};

export const resellToken = async (walletClient, tokenId, prices) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");

    const contract = getWriteContract(walletClient);
    const listingPrice = await contract.read.getListingPrice();
    const priceParams = {
      ethPrice: prices.ethPrice ? parseEther(prices.ethPrice.toString()) : 0n,
      usdcPrice: prices.usdcPrice
        ? parseUnits(prices.usdcPrice.toString(), 6)
        : 0n,
      usdtPrice: prices.usdtPrice
        ? parseUnits(prices.usdtPrice.toString(), 6)
        : 0n,
    };

    const hash = await contract.write.resellToken(
      [BigInt(tokenId), priceParams],
      { value: listingPrice }
    );
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to resell token: ${error.message}`);
  }
};

/**
 * NEW — cancelListing: seller removes their NFT from the marketplace.
 */
export const cancelListing = async (walletClient, tokenId) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");

    const contract = getWriteContract(walletClient);
    const hash = await contract.write.cancelListing([BigInt(tokenId)]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to cancel listing: ${error.message}`);
  }
};

export const createMarketSaleETH = async (walletClient, tokenId, price) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");

    const contract = getWriteContract(walletClient);
    const hash = await contract.write.createMarketSaleETH([BigInt(tokenId)], {
      value: parseEther(price.toString()),
    });
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to buy with ETH: ${error.message}`);
  }
};

export const createMarketSaleUSDC = async (walletClient, tokenId, price) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");

    const pub = getPublicClient();
    const usdcContract = getERC20Contract(contractConfig.usdcAddress, walletClient);
    const parsedPrice = parseUnits(price.toString(), 6);

    const allowance = await usdcContract.read.allowance([
      walletClient.account.address,
      contractConfig.address,
    ]);

    if (allowance < parsedPrice) {
      const approveHash = await usdcContract.write.approve([
        contractConfig.address,
        parsedPrice,
      ]);
      await pub.waitForTransactionReceipt({ hash: approveHash });
    }

    const contract = getWriteContract(walletClient);
    const hash = await contract.write.createMarketSaleUSDC([BigInt(tokenId)]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to buy with USDC: ${error.message}`);
  }
};

export const createMarketSaleUSDT = async (walletClient, tokenId, price) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");

    const pub = getPublicClient();
    const usdtContract = getERC20Contract(contractConfig.usdtAddress, walletClient);
    const parsedPrice = parseUnits(price.toString(), 6);

    const allowance = await usdtContract.read.allowance([
      walletClient.account.address,
      contractConfig.address,
    ]);

    if (allowance < parsedPrice) {
      const approveHash = await usdtContract.write.approve([
        contractConfig.address,
        parsedPrice,
      ]);
      await pub.waitForTransactionReceipt({ hash: approveHash });
    }

    const contract = getWriteContract(walletClient);
    const hash = await contract.write.createMarketSaleUSDT([BigInt(tokenId)]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to buy with USDT: ${error.message}`);
  }
};

// ─── ADMIN FUNCTIONS ──────────────────────────────────────────────────────────

export const updateListingPrice = async (walletClient, newListingPrice) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.updateListingPrice([
      parseEther(newListingPrice.toString()),
    ]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to update listing price: ${error.message}`);
  }
};

export const updatePlatformFee = async (walletClient, newFeeBps) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.updatePlatformFee([BigInt(newFeeBps)]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to update platform fee: ${error.message}`);
  }
};

export const updateFeeRecipient = async (walletClient, newFeeRecipient) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.updateFeeRecipient([newFeeRecipient]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to update fee recipient: ${error.message}`);
  }
};

export const setUserBlacklisted = async (walletClient, userAddress, blacklisted) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.setUserBlacklisted([userAddress, blacklisted]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to set user blacklist status: ${error.message}`);
  }
};

export const setTokenBlacklisted = async (walletClient, tokenId, blacklisted) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.setTokenBlacklisted([BigInt(tokenId), blacklisted]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to set token blacklist status: ${error.message}`);
  }
};

export const pauseContract = async (walletClient) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.pause({
      gas: 100000n,
    });
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to pause contract: ${error.message}`);
  }
};

export const unpauseContract = async (walletClient) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.unpause({
      gas: 100000n,
    });
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to unpause contract: ${error.message}`);
  }
};

// ─── EMERGENCY FUNCTIONS ─────────────────────────────────────────────────────

export const initiateEmergencyWithdraw = async (walletClient) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.initiateEmergencyWithdraw();
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to initiate emergency withdraw: ${error.message}`);
  }
};

export const cancelEmergencyWithdraw = async (walletClient) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.cancelEmergencyWithdraw();
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to cancel emergency withdraw: ${error.message}`);
  }
};

export const emergencyWithdrawETH = async (walletClient) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.emergencyWithdrawETH();
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to execute emergency ETH withdraw: ${error.message}`);
  }
};

export const emergencyWithdrawToken = async (walletClient, tokenAddress) => {
  try {
    if (!walletClient?.account) throw new Error("Wallet client not available");
    const contract = getWriteContract(walletClient);
    const hash = await contract.write.emergencyWithdrawToken([tokenAddress]);
    return _waitReceipt(hash);
  } catch (error) {
    throw new Error(`Failed to execute emergency token withdraw: ${error.message}`);
  }
};

// ─── VIEW FUNCTIONS ───────────────────────────────────────────────────────────

/**
 * NEW field name: platformFeeBps (was platformFeePercentage)
 */
export const getPlatformFeePercentage = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    const fee = await contract.read.platformFeeBps();
    return Number(fee);
  } catch (error) {
    throw new Error(`Failed to get platform fee: ${error.message}`);
  }
};

export const getFeeRecipient = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    return await contract.read.feeRecipient();
  } catch (error) {
    throw new Error(`Failed to get fee recipient: ${error.message}`);
  }
};

export const isUserBlacklisted = async (publicClient, userAddress) => {
  try {
    const contract = getReadContract(publicClient);
    return await contract.read.blacklistedUsers([userAddress]);
  } catch (error) {
    throw new Error(`Failed to check user blacklist status: ${error.message}`);
  }
};

export const isTokenBlacklisted = async (publicClient, tokenId) => {
  try {
    const contract = getReadContract(publicClient);
    return await contract.read.blacklistedTokens([BigInt(tokenId)]);
  } catch (error) {
    throw new Error(`Failed to check token blacklist status: ${error.message}`);
  }
};

/**
 * NEW field: emergencyWithdrawUnlockAt (was emergencyWithdrawTimestamp)
 */
export const getEmergencyWithdrawStatus = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    const [enabled, unlockAt] = await Promise.all([
      contract.read.emergencyWithdrawEnabled(),
      contract.read.emergencyWithdrawUnlockAt(),
    ]);
    return {
      enabled,
      unlockAt: Number(unlockAt),
      readyAt: new Date(Number(unlockAt) * 1000),
      isReady: enabled && Date.now() >= Number(unlockAt) * 1000,
    };
  } catch (error) {
    throw new Error(`Failed to get emergency withdraw status: ${error.message}`);
  }
};

/**
 * Returns MAX_ROYALTY_BPS and BPS_BASE from the new contract.
 * (Old names: MAX_ROYALTY_PERCENTAGE, PERCENTAGE_BASE, MAX_LISTING_PRICE)
 */
export const getContractConstants = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    const [maxRoyaltyBps, bpsBase, maxListingFee] = await Promise.all([
      contract.read.MAX_ROYALTY_BPS(),
      contract.read.BPS_BASE(),
      contract.read.MAX_LISTING_FEE(),
    ]);
    return {
      maxRoyaltyBps: Number(maxRoyaltyBps),        // 1000 = 10%
      bpsBase: Number(bpsBase),                    // 10000
      maxListingFee: formatEther(maxListingFee),   // 1 ETH
    };
  } catch (error) {
    throw new Error(`Failed to get contract constants: ${error.message}`);
  }
};

export const getOwner = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    return await contract.read.owner();
  } catch (error) {
    throw new Error(`Failed to get contract owner: ${error.message}`);
  }
};

export const isPaused = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    return await contract.read.paused();
  } catch (error) {
    throw new Error(`Failed to check if contract is paused: ${error.message}`);
  }
};

export const getRoyaltyInfo = async (publicClient, tokenId, salePrice) => {
  try {
    const contract = getReadContract(publicClient);
    const [receiver, royaltyAmount] = await contract.read.royaltyInfo([
      BigInt(tokenId),
      parseEther(salePrice.toString()),
    ]);
    return {
      receiver,
      royaltyAmount: formatEther(royaltyAmount),
      royaltyBps:
        (Number(royaltyAmount) * 10000) /
        Number(parseEther(salePrice.toString())),
    };
  } catch (error) {
    throw new Error(`Failed to get royalty info: ${error.message}`);
  }
};

export const getTokenBalance = async (publicClient, tokenAddress, userAddress) => {
  try {
    if (tokenAddress === "0x0000000000000000000000000000000000000000") {
      const balance = await publicClient.getBalance({ address: userAddress });
      return formatEther(balance);
    } else {
      const tokenContract = getERC20Contract(tokenAddress, publicClient);
      const [balance, decimals] = await Promise.all([
        tokenContract.read.balanceOf([userAddress]),
        tokenContract.read.decimals(),
      ]);
      return formatUnits(balance, decimals);
    }
  } catch (error) {
    throw new Error(`Failed to get token balance: ${error.message}`);
  }
};

export const checkUserBalance = async (publicClient, userAddress, paymentToken, amount) => {
  try {
    let tokenAddress;
    let decimals;
    switch (paymentToken) {
      case 0:
        tokenAddress = "0x0000000000000000000000000000000000000000";
        decimals = 18;
        break;
      case 1:
        tokenAddress = contractConfig.usdcAddress;
        decimals = 6;
        break;
      case 2:
        tokenAddress = contractConfig.usdtAddress;
        decimals = 6;
        break;
      default:
        throw new Error("Invalid payment token");
    }
    const balance = await getTokenBalance(publicClient, tokenAddress, userAddress);
    const balanceNum = parseFloat(balance);
    const amountNum = parseFloat(amount);
    return {
      hasEnoughBalance: balanceNum >= amountNum,
      balance,
      required: amount,
      difference: (balanceNum - amountNum).toFixed(6),
    };
  } catch (error) {
    throw new Error(`Failed to check user balance: ${error.message}`);
  }
};

export const calculateFees = async (publicClient, tokenId, salePrice) => {
  try {
    const contract = getReadContract(publicClient);
    const [platformFeeBps, item] = await Promise.all([
      contract.read.platformFeeBps(),   // NEW name
      contract.read.getMarketItem([BigInt(tokenId)]),
    ]);

    const price = parseEther(salePrice.toString());
    const platformFee = (price * platformFeeBps) / 10000n;
    const royaltyFee = (price * BigInt(item.royaltyBps)) / 10000n; // NEW field
    const sellerAmount = price - platformFee - royaltyFee;

    return {
      totalPrice: formatEther(price),
      platformFee: formatEther(platformFee),
      royaltyFee: formatEther(royaltyFee),
      sellerAmount: formatEther(sellerAmount),
      platformFeePct: Number(platformFeeBps) / 100,
      royaltyPct: Number(item.royaltyBps) / 100,
    };
  } catch (error) {
    throw new Error(`Failed to calculate fees: ${error.message}`);
  }
};

export const checkContractDeployment = async (publicClient) => {
  try {
    const bytecode = await publicClient.getBytecode({
      address: contractConfig.address,
    });
    return { isDeployed: !!bytecode && bytecode !== "0x", address: contractConfig.address };
  } catch (error) {
    return { isDeployed: false, address: contractConfig.address, error: error.message };
  }
};
// Doc 4 ning oxiriga qo'shing:
export const getContractAddresses = async (publicClient) => {
  try {
    const contract = getReadContract(publicClient);
    const [usdc, usdt] = await Promise.all([
      contract.read.USDC(),
      contract.read.USDT(),
    ]);
    return { usdcAddress: usdc, usdtAddress: usdt };
  } catch (error) {
    throw new Error(`Failed to get contract addresses: ${error.message}`);
  }
};