// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../src/interfaces/IStore.sol";
import "../src/Trade.sol";
import "../src/Pool.sol";
import "../src/Store.sol";
import "../src/CLP.sol";
import "../src/Chainlink.sol";

contract DeployProd is Script {
    uint256 public constant CURRENCY_UNIT = 10 ** 6;

    /* ========== FORK CONFIG ========== */
    uint256 arbitrum;
    uint256 optimism;
    uint256 polygon;
    uint256 bsc;
    uint256 avalanche;
    uint256 fantom;

    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");
    string BSC_RPC_URL = vm.envString("BSC_RPC_URL");
    string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
    string FANTOM_RPC_URL = vm.envString("FANTOM_RPC_URL");

    /* ========== UNISWAP CONFIG ========== */
    // Uniswap Router and Quoter for Polygon, Arbitrum and Optimism
    // see also https://docs.uniswap.org/contracts/v3/reference/deployments
    address swapRouter = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address quoter = address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    // Deployment addresses for WETH
    address ARB_WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address OP_WETH = address(0x4200000000000000000000000000000000000006);
    // On Polygon the native token is MATIC, so we use Wrapped Matic here
    address POLY_WMATIC = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    /* ========== CHAINLINK CONFIG ========== */
    // Chainlink Sequencer on Arbitrum and Optimism
    address ARB_SEQ = address(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);
    address OP_SEQ = address(0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389);

    // Price feeds
    address ARB_BTCUSD = address(0x6ce185860a4963106506C203335A2910413708e9);
    address ARB_ETHUSD = address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

    address OP_BTCUSD = address(0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593);
    address OP_ETHUSD = address(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    address POLY_BTCUSD = address(0xc907E116054Ad103354f2D350FD2514433D57F6f);
    address POLY_ETHUSD = address(0xF9680D99D6C9589e2a93a78A04A279e509205945);

    address BSC_BTCUSD = address(0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf);
    address BSC_ETHUSD = address(0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e);

    address AVAX_BTCUSD = address(0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743);
    address AVAX_ETHUSD = address(0x976B3D034E162d8bD72D6b9C989d545b839003b0);

    address FTM_BTCUSD = address(0x8e94C22142F4A64b99022ccDd994f4e9EC86E4B4);
    address FTM_ETHUSD = address(0x11DdD3d147E5b83D01cee7070027092397d63658);

    /* ========== USDC CONTRACTS ========== */
    address ARB_USDC = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address OP_USDC = address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);
    address POLY_USDC = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address BSC_USDC = address(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
    address AVAX_USDC = address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    address FTM_USDC = address(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);

    /* ========== CONTRACTS ========== */
    Trade public trade;
    Pool public pool;
    Store public store;
    CLP public clp;

    Chainlink public chainlink;

    // todo: set treasury and gov address
    address treasury;
    address gov;

    /* ========== METHODS ========== */
    function run() public {
        // create forks
        arbitrum = vm.createFork(ARBITRUM_RPC_URL);
        optimism = vm.createFork(OPTIMISM_RPC_URL);
        polygon = vm.createFork(POLYGON_RPC_URL);
        bsc = vm.createFork(BSC_RPC_URL);
        avalanche = vm.createFork(AVAX_RPC_URL);
        fantom = vm.createFork(FANTOM_RPC_URL);

        // private key for deployment
        uint256 pk = vm.envUint("PRIVATE_KEY");
        console.log("Deploying contracts with address", vm.addr(pk));

        // deploy on L2s
        _deploy(
            arbitrum,
            pk,
            ARB_SEQ,
            ARB_USDC,
            ARB_ETHUSD,
            ARB_BTCUSD,
            swapRouter,
            quoter,
            ARB_WETH,
            vm.addr(pk),
            vm.addr(pk)
        );
        _deploy(
            optimism, pk, OP_SEQ, OP_USDC, OP_ETHUSD, OP_BTCUSD, swapRouter, quoter, OP_WETH, vm.addr(pk), vm.addr(pk)
        );

        // sidechains, no sequencer needed
        _deploy(
            polygon,
            pk,
            address(0),
            POLY_USDC,
            POLY_ETHUSD,
            POLY_BTCUSD,
            swapRouter,
            quoter,
            POLY_WMATIC,
            vm.addr(pk),
            vm.addr(pk)
        );
        // no uniswap support for following chains
        _deploy(
            bsc,
            pk,
            address(0),
            BSC_USDC,
            BSC_ETHUSD,
            BSC_BTCUSD,
            address(0),
            address(0),
            address(0),
            vm.addr(pk),
            vm.addr(pk)
        );
        _deploy(
            avalanche,
            pk,
            address(0),
            AVAX_USDC,
            AVAX_ETHUSD,
            AVAX_BTCUSD,
            address(0),
            address(0),
            address(0),
            vm.addr(pk),
            vm.addr(pk)
        );
        _deploy(
            fantom,
            pk,
            address(0),
            FTM_USDC,
            FTM_ETHUSD,
            FTM_BTCUSD,
            address(0),
            address(0),
            address(0),
            vm.addr(pk),
            vm.addr(pk)
        );
    }

    function _deploy(
        uint256 fork,
        uint256 pk,
        address sequencer,
        address usdc,
        address ethFeed,
        address btcFeed,
        address _swapRouter,
        address _quoter,
        address _weth,
        address _treasury,
        address _gov
    ) internal {
        // select fork
        vm.selectFork(fork);

        // start broadcasting
        vm.startBroadcast(pk);

        // deploy contracts
        chainlink = new Chainlink{salt: bytes32("CHAINLINK")}(sequencer);
        store = new Store{salt: bytes32("STORE")}(_gov);
        trade = new Trade{salt: bytes32("TRADE")}(_gov);
        pool = new Pool{salt: bytes32("POOL")}(_gov);
        clp = new CLP{salt: bytes32("CLP")}(address(store));

        // Link contracts
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(_swapRouter, _quoter, _weth);
        trade.link(address(chainlink), address(pool), address(store));
        pool.link(address(trade), address(store), _treasury);

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

        vm.stopBroadcast();
    }
}
