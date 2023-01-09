// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../src/interfaces/IStore.sol";
import "../src/Trade.sol";
import "../src/Pool.sol";
import "../src/Store.sol";
import "../src/CLP.sol";
import "../src/mocks/MockChainlink.sol";
import "../src/mocks/MockToken.sol";

contract DeployLocalScript is Script {
    uint256 public constant UNIT = 10 ** 18;
    uint256 public constant CURRENCY_UNIT = 10 ** 6;

    Trade public trade;
    Pool public pool;
    Store public store;
    CLP public clp;

    MockToken public usdc;
    MockChainlink public chainlink;

    function setUp() public {}

    function run() public {
        // this is the default mnemonic anvil uses
        string memory mnemonic = "test test test test test test test test test test test junk";
        (address deployer,) = deriveRememberKey(mnemonic, 0);

        console.log("Deploying contracts with address", deployer);
        vm.startBroadcast(deployer);

        usdc = new MockToken("USDC", "USDC", 6);
        console.log("USDC token deployed to", address(usdc));

        chainlink = new MockChainlink();
        console.log("Chainlink deployed to", address(chainlink));

        store = new Store(deployer);
        console.log("Store deployed to", address(store));

        trade = new Trade(deployer);
        console.log("Trade deployed to", address(trade));

        pool = new Pool(deployer);
        console.log("Pool deployed to", address(pool));

        clp = new CLP(address(store));
        console.log("CLP deployed to", address(clp));

        // Link
        store.link(address(trade), address(pool), address(usdc), address(clp));
        trade.link(address(chainlink), address(pool), address(store));
        pool.link(address(trade), address(store), address(this)); // assuming treasury = address(this)
        console.log("Contracts linked");

        address ethFeed = makeAddr("ETH-USD");
        address btcFeed = makeAddr("BTC-USD");

        console.log("ethFeed", ethFeed);
        console.log("btcFeed", btcFeed);

        // Setup markets
        store.setMarket(
            "ETH-USD",
            IStore.Market({
                symbol: "ETH-USD",
                feed: ethFeed,
                maxLeverage: 50,
                maxOI: 5000000 * CURRENCY_UNIT,
                fee: 10,
                fundingFactor: 5000,
                minSize: 20 * CURRENCY_UNIT,
                minSettlementTime: 1 minutes
            })
        );
        store.setMarket(
            "BTC-USD",
            IStore.Market({
                symbol: "BTC-USD",
                feed: btcFeed,
                maxLeverage: 50,
                maxOI: 5000000 * CURRENCY_UNIT,
                fee: 10,
                fundingFactor: 5000,
                minSize: 20 * CURRENCY_UNIT,
                minSettlementTime: 1 minutes
            })
        );

        console.log("Markets set up.");

        // Setup prices
        chainlink.setPrice(ethFeed, 5000 * UNIT); // 1 ETH = 5000 USD
        chainlink.setPrice(btcFeed, 100_000 * UNIT); // 1 BTC = 100k USD

        // Mint and approve some mock USDC

        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);

        console.log("Minted mock tokens for main account.");

        vm.stopBroadcast();

        (address user,) = deriveRememberKey(mnemonic, 2);
        console.log("Minting tokens with account", user);
        vm.startBroadcast(user);

        // To user1
        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);

        console.log("Minted mock tokens for secondary account.");

        vm.stopBroadcast();
    }
}
