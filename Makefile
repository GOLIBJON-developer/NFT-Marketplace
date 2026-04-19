# ─── NFT Marketplace Makefile ───────────────────────────────────────────────
# Usage: make <target>
# Requires: foundry (forge, cast, anvil)

-include .env

.PHONY: all clean install build test test-ci coverage gas snapshot deploy-local deploy-sepolia

DEFAULT_ANVIL_KEY  := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
SEPOLIA_RPC_URL    ?= $(shell grep SEPOLIA_RPC_URL .env 2>/dev/null | cut -d '=' -f2)
ETHERSCAN_API_KEY  ?= $(shell grep ETHERSCAN_API_KEY .env 2>/dev/null | cut -d '=' -f2)

# ── Core ────────────────────────────────────────────────────────────────────

all: clean install build

clean:
	forge clean

install:
	forge install OpenZeppelin/openzeppelin-contracts
	forge install foundry-rs/forge-std

build:
	forge build

# ── Tests ───────────────────────────────────────────────────────────────────

test:
	forge test -vv

test-unit:
	forge test --match-contract NFTMarketplaceTest -vv

test-fuzz:
	forge test --match-contract NFTMarketplaceFuzz -vv

test-ci:
	forge test --profile ci -vv

test-verbose:
	forge test -vvvv

# ── Coverage & Gas ──────────────────────────────────────────────────────────

coverage:
	forge coverage --report summary

coverage-html:
	forge coverage --report lcov && genhtml lcov.info -o coverage/

gas:
	forge test --gas-report

snapshot:
	forge snapshot

snapshot-diff:
	forge snapshot --diff

# ── Deployment ──────────────────────────────────────────────────────────────

deploy-local:
	@echo "Starting Anvil and deploying locally..."
	forge script script/DeployNFTMarketplace.s.sol \
		--rpc-url http://localhost:8545 \
		--private-key $(DEFAULT_ANVIL_KEY) \
		--broadcast \
		-vvvv

deploy-sepolia:
	@echo "Deploying to Sepolia..."
	forge script script/DeployNFTMarketplace.s.sol \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--account $(ACCOUNT) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		--slow -vvvv

# ── Utilities ───────────────────────────────────────────────────────────────

format:
	forge fmt

lint:
	forge fmt --check

anvil:
	anvil --block-time 1

# ── Wallet ────────────────────────────────────────────────────────

wallet-import:
	cast wallet import $(ACCOUNT) --interactive

wallet-list:
	cast wallet list