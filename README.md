## Presale Platform

**Factory and launchpad contracts to create a presale for an ERC-20 token**

During the presale, the launchpad uses a fixed price for the token. It includes an optional whitelist for buying. After the presale, the team can create a liquidity pool (LP) on UniswapV2 to begin the linear token vesting. The token's price inside the LP is guaranteed to be higher than it was during the presale. If the team fails to create an LP, users will be able to withdraw their deposited native token.

## Test

1. Make sure you have foundry installed and run `forge install`
2. Copy `.env.example` into `.env` and add your `ETH_RPC_URL` and `ETHERSCAN_API_KEY`
3. Run `make tests` to run all tests or `make test-test test=[name]` to run a specific test

 
## Future plans

- Deployment scripts
- Whitelist: add max amount of tokens a user can buy
- Dynamic pricing formula (dutch auction, bonding curve, ...)
- More vesting options
- Creating LP using different protocols