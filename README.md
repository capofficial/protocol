# CAP v4 Solidity Contracts

## TODO

For details on how the margin / trading system works, please check the [Whitepaper](https://www.cap.finance/whitepaper.pdf), specifically sections 4 and 4.4. Liquidation Rebates and Interest Rate no longer apply.

The items below are listed in priority order. All milestones are **ASAP**, with a target production launch date of **early January** on Arbitrum. The driving factor is high quality, speed, and code simplicity.

- [ ] If submitOrder margin exceeds freeMargin, set it to the max freeMargin available
- [ ] Add MAX_FEE and other constants in Store to curtail gov powers in methods marked with onlyGov. The goal is to prevent gov from having too much power over system function, like setting a fee share too high and siphoning all the funds.
- [ ] Add automated tests, including fuzzy, to achieve > 90% coverage
- [ ] Verify Chainlink contract works as expected for Arbitrum and its sequencer. Support all other Chainlink networks (or have a custom Chainlink contract for each chain)
- [ ] Add methods "depositThroughUniswap" and "addLiquidityThroughUniswap" to allow deposits from a contract like Uniswap Router, to allow people to deposit any asset which is then automatically converted into the Store-supported currency. Potentially support other DEXes like 1inch.
- [ ] Refactor code while maintaining readability
- [ ] Run auditing tools, get more eyes on the contracts
- [ ] Deploy and test locally with the [UI](https://github.com/capofficial/ui) to make sure everything is working as expected
- [ ] Create production deploy scripts

## Done

- [x] All orders including market should execute through keepers, which can be anyone, either after minSettlementTime or if chainlink price changes
- [x] Trigger orders execute at the chainlink price, not the price they've set
- [x] Give traders option to retrieve margin, closing without profit, when P/L > 0. Useful in black swan scenarios to get their margin back.
- [x] Flat fee
- [x] Allow submitting TP/SL with an order
- [x] Contracts: Trade, Pool, Store, Chainlink
- [x] Treasury fees should be paid out to a treasury address directly (set by gov)

## Compiling

```
forge build --via-ir
```

## Deploying locally

```
anvil
forge script DeployLocalScript --rpc-url http://127.0.0.1:8545 --broadcast --via-ir -vvvv
```
