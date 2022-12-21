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

    address public deployer;
    address public user;
    address public user2;

    Trade public trade;
    Pool public pool;
    Store public store;
    CLP public clp;

    MockToken public usdc;
    MockChainlink public chainlink;

    function setUp() public virtual {
        // this is the default mnemonic anvil uses
        string memory mnemonic = "test test test test test test test test test test test junk";
        (deployer,) = deriveRememberKey(mnemonic, 0);

        console.log("Deploying contracts with address", deployer);
        vm.prank(deployer);

        usdc = new MockToken("USDC", "USDC", 6);
        console.log("USDC token deployed to", address(usdc));

        chainlink = new MockChainlink();
        console.log("Chainlink deployed to", address(chainlink));

        store = new Store();
        console.log("Store deployed to", address(store));

        trade = new Trade();
        console.log("Trade deployed to", address(trade));

        pool = new Pool();
        console.log("Pool deployed to", address(pool));

        clp = new CLP(address(store));
        console.log("CLP deployed to", address(clp));

        // Link
        store.link(address(trade), address(pool), address(usdc), address(clp));
        trade.link(address(chainlink), address(pool), address(store));
        pool.link(address(trade), address(store), address(this)); // assuming treasury = address(this)
        console.log("Contracts linked");

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

        console.log("Markets set up.");

        // Mint and approve some mock USDC

        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);

        console.log("Minted mock tokens for deployer account.");

        vm.stopPrank();

        (user,) = deriveRememberKey(mnemonic, 2);
        console.log("Minting tokens with account", user);
        vm.startPrank(user);

        // To user
        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);

        console.log("Minted mock tokens for user account.");

        vm.stopPrank();

        (user2,) = deriveRememberKey(mnemonic, 1);
        console.log("Minting tokens with account", user2);
        vm.startPrank(user2);

        // To user2
        usdc.mint(1000000 * CURRENCY_UNIT);
        usdc.approve(address(store), 10 ** 9 * CURRENCY_UNIT);

        console.log("Minted mock tokens for second user account.");

        vm.stopPrank();
    }
}
