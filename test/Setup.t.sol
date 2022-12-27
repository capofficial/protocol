// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/Trade.sol";
import "../src/Pool.sol";
import "../src/Store.sol";
import "../src/CLP.sol";
import "../src/mocks/MockChainlink.sol";
import "../src/mocks/MockToken.sol";

contract SetupTest is Test {
    uint256 public constant CURRENCY_UNIT = 10 ** 6;

    address public user = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);
    address public user2 = address(0x90F79bf6EB2c4f870365E785982E1f101E93b906);

    address public ethFeed = makeAddr("ETH-USD");
    address public btcFeed = makeAddr("BTC-USD");

    Trade public trade;
    Pool public pool;
    Store public store;
    CLP public clp;

    MockToken public usdc;
    MockChainlink public chainlink;

    // Test Orders
    Store.Order ethLong = Store.Order({
        orderId: 0,
        user: address(0),
        market: "ETH-USD",
        price: 0, // price doesnt matter, since ordertype = market
        isLong: true,
        isReduceOnly: false,
        orderType: 0, // 0 = market, 1 = limit, 2 = stop
        margin: 2500 * CURRENCY_UNIT,
        size: 10000 * CURRENCY_UNIT, // leverage => 5x
        fee: 0,
        timestamp: 0
    });

    Store.Order btcLong = Store.Order({
        orderId: 0,
        user: address(0),
        market: "BTC-USD",
        price: 0, // price doesnt matter, since ordertype = market
        isLong: true,
        isReduceOnly: false,
        orderType: 0, // 0 = market, 1 = limit, 2 = stop
        margin: 2500 * CURRENCY_UNIT,
        size: 10000 * CURRENCY_UNIT, // leverage => 5x
        fee: 0,
        timestamp: 0
    });

    function setUp() public virtual {
        usdc = new MockToken("USDC", "USDC", 6);
        //console.log("USDC token deployed to", address(usdc));

        chainlink = new MockChainlink();
        //console.log("Chainlink deployed to", address(chainlink));

        store = new Store();
        //console.log("Store deployed to", address(store));

        trade = new Trade();
        //console.log("Trade deployed to", address(trade));

        pool = new Pool();
        //console.log("Pool deployed to", address(pool));

        clp = new CLP(address(store));
        //console.log("CLP deployed to", address(clp));

        // Link
        store.link(address(trade), address(pool), address(usdc), address(clp));
        trade.link(address(chainlink), address(pool), address(store));
        pool.link(address(trade), address(store), address(1)); // assuming treasury = address(1)
        //console.log("Contracts linked");

        // Setup markets
        store.setMarket(
            "ETH-USD",
            Store.Market({
                symbol: "ETH-USD",
                feed: ethFeed,
                maxLeverage: 50,
                maxOI: 5000000 * CURRENCY_UNIT,
                fee: 100,
                fundingFactor: 5000,
                minSize: 20 * CURRENCY_UNIT,
                minSettlementTime: 1 minutes
            })
        );
        store.setMarket(
            "BTC-USD",
            Store.Market({
                symbol: "BTC-USD",
                feed: btcFeed,
                maxLeverage: 50,
                maxOI: 5000000 * CURRENCY_UNIT,
                fee: 100,
                fundingFactor: 5000,
                minSize: 20 * CURRENCY_UNIT,
                minSettlementTime: 1 minutes
            })
        );

        //console.log("Markets set up.");

        // Setup prices
        chainlink.setPrice(ethFeed, 5000); // 1 ETH = 5000 USD
        chainlink.setPrice(btcFeed, 100_000); // 1 BTC = 100k USD

        // Mint and approve some mock USDC
        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);

        // To user
        vm.startPrank(user);
        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);
        vm.stopPrank();

        // To user2
        vm.startPrank(user2);
        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);
        vm.stopPrank();
    }
}