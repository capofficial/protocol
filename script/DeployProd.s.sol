// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../src/interfaces/IStore.sol";
import "../src/Trade.sol";
import "../src/Pool.sol";
import "../src/Store.sol";
import "../src/CLP.sol";
import "../src/Chainlink.sol";

// todo: support more networks
contract DeployProd is Script {
    /* ========== FORK VARIABLES ========== */
    uint256 arbitrum;
    uint256 optimism;
    uint256 polygon;
    uint256 bnb;
    uint256 avalanche;
    uint256 fantom;

    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");
    string BNB_RPC_URL = vm.envString("BNB_RPC_URL");
    string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
    string FANTOM_RPC_URL = vm.envString("FANTOM_RPC_URL");

    /* ========== DEPLOYMENT ADDRESSES ========== */
    // Uniswap Router and Quoter for Polygon, Arbitrum and Optimism
    // see also https://docs.uniswap.org/contracts/v3/reference/deployments
    address swapRouter = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address quoter = address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    // Deployment addresses for USDC
    address PolygonUSDC = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address ArbitrumUSDC = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address OptimismUSDC = address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    // Deployment addresses for WETH
    address ArbitrumWETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address OptimismWETH = address(0x4200000000000000000000000000000000000006);
    // On Polygon the native token is MATIC, so we use Wrapped Matic here
    address PolygonWMATIC = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    // Chainlink Sequencer on Arbitrum and Optimism
    address ArbitrumSequencer = address(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);
    address OptimismSequencer = address(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389);

    /* ========== CONSTANTS ========== */
    uint256 public constant CURRENCY_UNIT = 10 ** 6;

    /* ========== CONTRACTS ========== */
    Trade public trade;
    Pool public pool;
    Store public store;
    CLP public clp;

    Chainlink public chainlink;

    /* ========== METHODS ========== */
    function run() public {
        // create forks
        arbitrum = vm.createFork(ARBITRUM_RPC_URL);
        optimism = vm.createFork(OPTIMISM_RPC_URL);
        polygon = vm.createFork(POLYGON_RPC_URL);
        bnb = vm.createFork(BNB_RPC_URL);
        avalanche = vm.createFork(AVAX_RPC_URL);
        fantom = vm.createFork(FANTOM_RPC_URL);

        // private key for deployment
        uint256 pk = vm.envUint("PRIVATE_KEY");
        console.log("Deploying contracts with address", vm.addr(pk));

        // start broadcasting
        vm.startBroadcast(pk);

        // todo: call deploy function for all supported networks
        //_deploy(...);

        vm.stopBroadcast();
    }

    function _deploy(
        uint256 fork,
        string memory name,
        address sequencer,
        address usdc,
        address ethFeed,
        address btcFeed,
        address _swapRouter,
        address _quoter,
        address _weth,
        address treasury
    ) internal {
        // select fork
        vm.selectFork(fork);
        console.log(name);

        chainlink = new Chainlink{salt: bytes32("CHAINLINK")}(sequencer);
        console.log("Chainlink deployed to", address(chainlink));

        store = new Store{salt: bytes32("STORE")}();
        console.log("Store deployed to", address(store));

        trade = new Trade{salt: bytes32("TRADE")}();
        console.log("Trade deployed to", address(trade));

        pool = new Pool{salt: bytes32("POOL")}();
        console.log("Pool deployed to", address(pool));

        clp = new CLP{salt: bytes32("CLP")}(address(store));
        console.log("CLP deployed to", address(clp));

        // Link
        // todo: add multisig address
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(_swapRouter, _quoter, _weth);
        trade.link(address(chainlink), address(pool), address(store));
        pool.link(address(trade), address(store), treasury);
        console.log("Contracts linked");

        // Setup markets
        store.setMarket(
            "ETH-USD",
            IStore.Market({
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
            IStore.Market({
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

        console.log("Markets set up.");
    }
}
