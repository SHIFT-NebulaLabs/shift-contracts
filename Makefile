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

# SIMULATIONS
sim-deploy-local:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Testnet

# - Protocol
sim-deploy-protocol-testnet:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Testnet --rpc-url $(TESTNET_URL)

sim-deploy-protocol-mainnet:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Mainnet --rpc-url $(MAINNET_URL)

# - Add-On: Supply Validator
sim-deploy-supply-validator:
	forge script script/SupplyValidator.s.sol:DeploySupplyValidator --rpc-url $(MAINNET_URL)

# DEPLOYMENTS
# - Protocol
deploy-protocol-testnet:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Testnet --rpc-url $(TESTNET_URL) --interactives 1 --broadcast --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY) --verify

deploy-protocol-mainnet:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Mainnet --rpc-url $(MAINNET_URL) --interactives 1 --broadcast --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY) --verify

# - Add-On: Supply Validator
deploy-supply-validator:
	forge script script/SupplyValidator.s.sol:DeploySupplyValidator --rpc-url $(MAINNET_URL) --interactives 1 --broadcast --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY) --verify