// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {NFTMarketplace}    from "../src/NFTMarketplace.sol";
import {HelperConfig}      from "./HelperConfig.s.sol";

/**
 * @title  DeployNFTMarketplace
 * @notice Foundry deployment script — works on Anvil, Sepolia, and Mainnet.
 *
 * Usage:
 *   # Local Anvil
 *   forge script script/DeployNFTMarketplace.s.sol --rpc-url localhost --broadcast
 *
 *   # Sepolia
 *   forge script script/DeployNFTMarketplace.s.sol \
 *       --rpc-url $SEPOLIA_RPC_URL \
 *       --private-key $PRIVATE_KEY \
 *       --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
 */
contract DeployNFTMarketplace is Script {
    function run() external returns (NFTMarketplace marketplace, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        (
            address usdc,
            address usdt,
            address feeRecipient,
            string memory name,
            string memory symbol
        ) = helperConfig.activeNetworkConfig();

        console2.log("Deploying NFTMarketplace on chain:", block.chainid);
        console2.log("  USDC         :", usdc);
        console2.log("  USDT         :", usdt);
        console2.log("  feeRecipient :", feeRecipient);

        vm.startBroadcast();
        marketplace = new NFTMarketplace(
            usdc,
            usdt,
            feeRecipient,
            name,
            symbol
        );
        vm.stopBroadcast();

        console2.log("NFTMarketplace deployed at:", address(marketplace));
    }
}
