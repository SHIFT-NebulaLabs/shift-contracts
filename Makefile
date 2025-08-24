# To run a command make <target>

-include .env

build:
	forge build

clean:
	forge clean

coverage:
	forge coverage

testing:
	forge fmt
	forge test -vv

sim-deploy-local:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Testnet

sim-deploy-sepolia:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Testnet --rpc-url $(SEPOLIA_URL)

sim-deploy-arbitrum:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Mainnet --rpc-url $(ARBITRUM_URL)

deploy-sepolia:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Testnet --rpc-url $(SEPOLIA_URL) --interactives 1 --broadcast --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY) --verify

deploy-arbitrum:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Mainnet --rpc-url $(ARBITRUM_URL) --interactives 1 --broadcast --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY) --verify