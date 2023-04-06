-include .env

.PHONY: all test clean deploy-anvil

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install foundry-rs/forge-std

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test -vvv

snapshot :; forge snapshot

slither :; slither ./src --exclude-dependencies --exclude timestamp,solc-version --solc-remaps @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ --filter-paths lib

format :; forge fmt

# solhint should be installed globally
lint :; solhint src/**/*.sol && solhint src/*.sol && solhint test/**/*.sol && solhint test/*.sol

anvil :; anvil -m 'test test test test test test test test test test test junk' -b 12

# use the "@" to hide the command from your shell
deploy-goerli :; @forge script scripts/DeployGoerli.s.sol:DeployGoerli --rpc-url ${GOERLI_RPC_URL} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

deploy-sepolia :; @forge script scripts/DeploySepolia.s.sol:DeploySepolia --rpc-url ${SEPOLIA_RPC_URL} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

deploy-mainnet :; @forge script scripts/DeployMainnet.s.sol:DeployMainnet --rpc-url ${MAINNET_RPC_URL} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv

# This is the private key of account from the mnemonic from the "make anvil" command
deploy-anvil :; @forge script scripts/DeployLocal.s.sol:DeployLocal --rpc-url http://localhost:8545 --broadcast
