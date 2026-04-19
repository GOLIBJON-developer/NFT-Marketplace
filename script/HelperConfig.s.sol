// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "../src/MockERC20.sol";

/**
 * @title  HelperConfig
 * @notice Returns network-specific constructor arguments for NFTMarketplace.
 *         
 */
contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                               TYPES
    //////////////////////////////////////////////////////////////*/

    struct NetworkConfig {
        address usdc;
        address usdt;
        address feeRecipient;
        string  name;
        string  symbol;
    }

    /*//////////////////////////////////////////////////////////////
                         NETWORK CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant ANVIL_CHAIN_ID   = 31337;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant MAINNET_CHAIN_ID = 1;

    // Sepolia USDC / USDT test tokens (Circle & Tether official)
    address public constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address public constant SEPOLIA_USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;

    // Mainnet
    address public constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /*//////////////////////////////////////////////////////////////
                              STATE
    //////////////////////////////////////////////////////////////*/

    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        if (block.chainid == MAINNET_CHAIN_ID) {
            activeNetworkConfig = getMainnetEthConfig();
        } else if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        NETWORK CONFIGS
    //////////////////////////////////////////////////////////////*/

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc:         MAINNET_USDC,
            usdt:         MAINNET_USDT,
            feeRecipient: 0x000000000000000000000000000000000000dEaD, // replace with real multisig
            name:         "NFT Marketplace",
            symbol:       "NFTM"
        });
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc:         SEPOLIA_USDC,
            usdt:         SEPOLIA_USDT,
            feeRecipient: 0xe354ad36eDF11836C38EB8aD33911067D1D94dC4, // replace with deployer
            name:         "NFT Marketplace Sepolia",
            symbol:       "NFTMS"
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Return cached config if already deployed
        if (activeNetworkConfig.usdc != address(0)) return activeNetworkConfig;

        vm.startBroadcast();
        MockERC20 mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6, 1_000_000 * 1e6);
        MockERC20 mockUsdt = new MockERC20("Mock USDT", "mUSDT", 6, 1_000_000 * 1e6);
        vm.stopBroadcast();

        return NetworkConfig({
            usdc:         address(mockUsdc),
            usdt:         address(mockUsdt),
            feeRecipient: msg.sender,
            name:         "NFT Marketplace Local",
            symbol:       "NFTMX"
        });
    }
}
