//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";

contract UniswapTest is SetupTest {
    uint256 arbitrum;
    uint256 optimism;
    uint256 polygon;

    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM_RPC_URL");
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");

    // Uniswap Router and Quoter for Polygon, Arbitrum and Optimism
    // see also https://docs.uniswap.org/contracts/v3/reference/deployments
    address swapRouter = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address quoter = address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    // Deployment addresses for USDC
    address PolygonUSDC = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    address ArbitrumUSDC = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address OptimismUSDC = address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    // Deployment addresses for DAI
    address PolygonDAI = address(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
    address ArbitrumDAI = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    address OptimismDAI = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);

    // Deployment addresses for WETH
    address ArbitrumWETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address OptimismWETH = address(0x4200000000000000000000000000000000000006);
    // On Polygon the native token is MATIC, so we use Wrapped Matic here
    address PolygonWMATIC = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

    function setUp() public virtual override {
        arbitrum = vm.createFork(ARBITRUM_RPC_URL);
        optimism = vm.createFork(OPTIMISM_RPC_URL);
        polygon = vm.createFork(POLYGON_RPC_URL);
    }

    function testQuoter() public {
        console.log("-----------------------");
        console.log("Output token = USDC");
        console.log("-----------------------");

        _getEstimatedOutput(arbitrum, "Arbitrum", ArbitrumUSDC, ArbitrumDAI, ArbitrumWETH);
        _getEstimatedOutput(optimism, "Optimism", OptimismUSDC, OptimismDAI, OptimismWETH);
        _getEstimatedOutput(polygon, "Polygon", PolygonUSDC, PolygonDAI, PolygonWMATIC);
    }

    function _getEstimatedOutput(uint256 fork, string memory name, address usdc, address dai, address weth) internal {
        vm.selectFork(fork);
        console.log(name);
        // deploy contracts
        super.setUp();
        vm.startPrank(deployer);

        // link SwapRouter address and USDC address
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(swapRouter, quoter, weth);

        vm.stopPrank();

        // get estimated output tokens for 1 WETH (or 1 Matic on Polygon)
        console.log("Estimated output for 1 WETH:", store.getEstimatedOutputTokens(1 ether, weth, 500));

        // get estimated output for 1000 DAI input

        // DAI/USDC poolFee on Arbitrum is 0.05%
        uint24 poolFee;
        if (fork == arbitrum) poolFee = 500;
        else poolFee = 100;
        console.log("Estimated output for 1000 DAI:", store.getEstimatedOutputTokens(1000 ether, dai, poolFee));
        console.log("-----------------------");
    }

    function testAddLiquidity() public {
        // test adding liquidity
        _addLiquidity(arbitrum, "Arbitrum", ArbitrumUSDC, ArbitrumDAI, ArbitrumWETH);
        _addLiquidity(optimism, "Optimism", OptimismUSDC, OptimismDAI, OptimismWETH);
        _addLiquidity(polygon, "Polygon", PolygonUSDC, PolygonDAI, PolygonWMATIC);
    }

    function testDeposit() public {
        // test depositing
        _deposit(arbitrum, "Arbitrum", ArbitrumUSDC, ArbitrumDAI, ArbitrumWETH);
        _deposit(optimism, "Optimism", OptimismUSDC, OptimismDAI, OptimismWETH);
        _deposit(polygon, "Polygon", PolygonUSDC, PolygonDAI, PolygonWMATIC);
    }

    function _addLiquidity(uint256 fork, string memory name, address usdc, address dai, address weth) internal {
        vm.selectFork(fork);
        console.log(name);
        // deploy contracts
        super.setUp();
        vm.startPrank(deployer);

        // link SwapRouter address and USDC address
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(swapRouter, quoter, weth);

        vm.stopPrank();

        // give user some ETH
        vm.deal(user, 10 ether);

        vm.startPrank(user);

        // add liquidity with ETH
        // we use a poolFee of 100 for very stable pairs and 500 for stable pairs
        pool.addLiquidityThroughUniswap{value: 1 ether}(address(0), 0, 500);
        uint256 balanceAfterETH = store.getUserPoolBalance(user);
        if (fork == polygon) console.log("Added USDC Liquidity with MATIC:", balanceAfterETH);
        else console.log("Added USDC Liquidity with ETH:", balanceAfterETH);

        // give user 1000 DAI
        deal(dai, user, 1000 ether);

        // add liquidity with DAI
        IERC20(dai).approve(address(store), 1000 ether);

        // DAI/USDC poolFee on Arbitrum is 0.05%
        uint24 poolFee;
        if (fork == arbitrum) poolFee = 500;
        else poolFee = 100;

        pool.addLiquidityThroughUniswap(dai, 1000 ether, poolFee);
        console.log("Added USDC Liquidity with DAI:", store.getUserPoolBalance(user) - balanceAfterETH);

        vm.stopPrank();
        console.log("-----------------------");
    }

    function _deposit(uint256 fork, string memory name, address usdc, address dai, address weth) internal {
        vm.selectFork(fork);
        console.log(name);
        // deploy contracts
        super.setUp();
        vm.startPrank(deployer);

        // link SwapRouter address and USDC address
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(swapRouter, quoter, weth);

        vm.stopPrank();

        // give user some ETH
        vm.deal(user, 10 ether);

        vm.startPrank(user);

        // deposit with ETH
        // we use a poolFee of 100 for very stable pairs and 500 for stable pairs
        trade.depositThroughUniswap{value: 1 ether}(address(0), 0, 500);
        uint256 balanceAfterETH = store.getBalance(user);

        // native token on Polygon is MATIC
        if (fork == polygon) console.log("Deposited USDC with MATIC:", balanceAfterETH);
        else console.log("Deposited USDC with ETH:", balanceAfterETH);

        // give user 1000 DAI
        deal(dai, user, 1000 ether);

        // deposit with DAI
        IERC20(dai).approve(address(store), 1000 ether);

        // DAI/USDC poolFee on Arbitrum is 0.05%
        uint24 poolFee;
        if (fork == arbitrum) poolFee = 500;
        else poolFee = 100;

        trade.depositThroughUniswap(dai, 1000 ether, poolFee);
        console.log("Deposited USDC with DAI:", store.getBalance(user) - balanceAfterETH);

        vm.stopPrank();
        console.log("-----------------------");
    }
}
