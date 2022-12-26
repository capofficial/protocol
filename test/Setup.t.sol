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

    Trade public trade;
    Pool public pool;
    Store public store;
    CLP public clp;

    MockToken public usdc;
    MockChainlink public chainlink;

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
        pool.link(address(trade), address(store), address(this)); // assuming treasury = address(this)
        //console.log("Contracts linked");

        // Setup markets
        store.setMarket(
            "ETH-USD",
            Store.Market({
                symbol: "ETH-USD",
                feed: address(0),
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
                feed: address(0),
                maxLeverage: 50,
                maxOI: 5000000 * CURRENCY_UNIT,
                fee: 100,
                fundingFactor: 5000,
                minSize: 20 * CURRENCY_UNIT,
                minSettlementTime: 1 minutes
            })
        );

        //console.log("Markets set up.");

        // Mint and approve some mock USDC

        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);

        //console.log("Minted mock tokens for deployer account.");

        vm.startPrank(user);
        //console.log("Minting tokens with account", user);

        // To user
        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);

        //console.log("Minted mock tokens for user account.");

        vm.stopPrank();

        vm.startPrank(user2);
        //console.log("Minting tokens with account", user2);

        // To user2
        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);

        //console.log("Minted mock tokens for second user account.");

        vm.stopPrank();
    }
}
