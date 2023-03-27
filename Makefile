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
deploy-sepolia :; @forge script scripts/${contract}.s.sol:Deploy${contract} --rpc-url ${SEPOLIA_RPC_URL}  --private-key ${PRIVATE_KEY} --broadcast --verify --etherscan-api-key ${ETHERSCAN_API_KEY}  -vvvv

# This is the private key of account from the mnemonic from the "make anvil" command
deploy-anvil :; @forge script scripts/DeployLocal.s.sol:DeployLocal --rpc-url http://localhost:8545  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast

