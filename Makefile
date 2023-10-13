-include .env

.PHONY: all test clean deploy-anvil

all: clean remove install update build

# Clean the repo
clean :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install foundry-rs/forge-std

# Update Dependencies
update :; forge update

build :; forge build

test :; forge test -vvv

test-dev :; FOUNDRY_FUZZ_RUNS=50 forge test -vvv

snapshot :; forge snapshot

slither :; slither ./src --exclude-dependencies --exclude timestamp,solc-version,missing-zero-check --solc-remaps @openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ --filter-paths lib

format :; forge fmt

# solhint should be installed globally
lint :; solhint src/**/*.sol && solhint src/*.sol && solhint test/**/*.sol && solhint test/*.sol

anvil :; anvil -m 'test test test test test test test test test test test junk' -b 6

deploy-anvil :; WITH_OATH=true forge script script/LocalDeploy.s.sol:LocalDeploy --rpc-url http://localhost:8545 --broadcast

deploy-anvil-oathless :; forge script script/LocalDeploy.s.sol:LocalDeploy --rpc-url http://localhost:8545 --broadcast

deploy-anvil-upgradeless :; forge script script/LocalDeployUpgradeless.s.sol:LocalDeployUpgradeless --rpc-url http://localhost:8545 --broadcast
