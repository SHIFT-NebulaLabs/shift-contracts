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

sim-deploy-testnet:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Testnet --rpc-url $(MAINNET_URL)

sim-deploy-mainnet:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Mainnet --rpc-url $(MAINNET_URL)

deploy-testnet:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Testnet --rpc-url $(TESTNET_URL) --interactives 1 --broadcast --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY) --verify

deploy-mainnet:
	forge script script/ShiftProtocol.s.sol:DeployShiftProtocol_Mainnet --rpc-url $(MAINNET_URL) --interactives 1 --broadcast --verifier etherscan --etherscan-api-key $(ETHERSCAN_API_KEY) --verify