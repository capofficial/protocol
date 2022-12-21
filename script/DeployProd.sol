// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../src/Trade.sol";
import "../src/Pool.sol";
import "../src/Store.sol";
import "../src/CLP.sol";
import "../src/Chainlink.sol";

// USDC
// Arbitrum: https://arbiscan.io/token/0xff970a61a04b1ca14834a43f5de4533ebddb5cc8
// Optimism: https://optimistic.etherscan.io/token/0x7f5c764cbc14f9669b88837ca1490cca17c31607

// Chainlink sequencer
// Arbitrum: 0xFdB631F5EE196F0ed6FAa767959853A9F217697D
// Optimism: 0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389

// todo: support more networks
contract DeployProd is Script {
    uint256 arbitrumFork;
    uint256 optimismFork;

    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");

    uint256 public constant CURRENCY_UNIT = 10 ** 6;

    Trade public trade;
    Pool public pool;
    Store public store;
    CLP public clp;

    Chainlink public chainlink;

    address ArbitrumUSDC = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address OptimismUSDC = address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    address ArbitrumSequencer = address(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);
    address OptimismSequencer = address(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389);

    // todo: add price feeds for chains

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        console.log("Deploying contracts with address", vm.addr(pk));
        vm.startBroadcast(pk);

        //_deploy(...);

        vm.stopBroadcast();
    }

    function _deploy(uint256 _fork, address _sequencer, address _usdc, address ethFeed, address btcFeed) internal {
        //uint256 fork = vm.createSelectFork(_fork);

        chainlink = new Chainlink{salt: bytes32("CHAINLINK")}(_sequencer);
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
        // todo: add multisig address
        store.link(address(trade), address(pool), _usdc, address(clp));
        trade.link(address(chainlink), address(pool), address(store));
        pool.link(address(trade), address(store), address(this)); // assuming treasury = address(this)
        console.log("Contracts linked");

        // Setup markets
        store.setMarket(
            "ETH-USD",
            Store.Market({
                symbol: "ETH-USD",
                feed: address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
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
                feed: address(0x6ce185860a4963106506C203335A2910413708e9),
                maxLeverage: 50,
                maxOI: 5000000 * CURRENCY_UNIT,
                fee: 100,
                fundingFactor: 5000,
                minSize: 20 * CURRENCY_UNIT,
                minSettlementTime: 1 minutes
            })
        );

        console.log("Markets set up.");
    }
}
