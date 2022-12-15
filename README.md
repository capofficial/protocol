# CAP v4 Solidity Contracts

## TODO

- [x] All orders including market should execute through keepers, which can be anyone, either after minSettlementTime or if chainlink price changes
- [x] Trigger orders execute at the chainlink price, not the price they've set
- [x] Give traders option to retrieve margin, closing without profit, when P/L > 0. Useful in black swan scenarios to get their margin back.
- [x] Flat fee
- [x] Allow submitting TP/SL with an order
- [x] Contracts: Trade, Pool, Store, Chainlink 
- [ ] Add method to "depositAs" or "addLiquidityAs" e.g. to allow deposits from a contract like Uniswap Router, to allow people to deposit any asset which is then automatically converted into the Store supported currency
- [ ] Add MAX_FEE and other variables in Store to limit gov powers
- [ ] Add automated tests, including fuzzy, to achieve > 90% coverage
- [ ] Create production deploy scripts

## Compiling

```
forge build --via-ir
```

## Deploying locally

```
anvil
forge script DeployLocalScript --rpc-url http://127.0.0.1:8545 --broadcast --via-ir -vvvv
```