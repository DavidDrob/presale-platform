-include .env

tests  :; forge test -vv --fork-url ${ETH_RPC_URL}
trace  :; forge test -vvv --fork-url ${ETH_RPC_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
test-test  :; forge test -vvvvv --match-test $(test) --fork-url ${ETH_RPC_URL}