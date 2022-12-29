//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./utils/SetupTest.sol";

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

        _getEstimatedOutput(arbitrum, "Arbitrum", ArbitrumUSDC, ArbitrumDAI, ArbitrumWETH, 500);
        _getEstimatedOutput(optimism, "Optimism", OptimismUSDC, OptimismDAI, OptimismWETH, 100);
        _getEstimatedOutput(polygon, "Polygon", PolygonUSDC, PolygonDAI, PolygonWMATIC, 100);
    }

    function testAddLiquidity() public {
        // add liquidity with DAI
        _addLiquidityDAI(arbitrum, "Arbitrum", ArbitrumUSDC, ArbitrumDAI, ArbitrumWETH, 500);
        _addLiquidityDAI(optimism, "Optimism", OptimismUSDC, OptimismDAI, OptimismWETH, 100);
        _addLiquidityDAI(polygon, "Polygon", PolygonUSDC, PolygonDAI, PolygonWMATIC, 100);

        // add liquidity with WETH (or WMATIC on Polygon)
        _addLiquidityWETH(arbitrum, "Arbitrum", ArbitrumUSDC, ArbitrumWETH, 500);
        _addLiquidityWETH(optimism, "Optimism", OptimismUSDC, OptimismWETH, 500);
        _addLiquidityWETH(polygon, "Polygon", PolygonUSDC, PolygonWMATIC, 500);
    }

    function testDeposit() public {
        _depositDAI(arbitrum, "Arbitrum", ArbitrumUSDC, ArbitrumDAI, ArbitrumWETH, 500);
        _depositDAI(optimism, "Optimism", OptimismUSDC, OptimismDAI, OptimismWETH, 100);
        _depositDAI(polygon, "Polygon", PolygonUSDC, PolygonDAI, PolygonWMATIC, 100);

        _depositWETH(arbitrum, "Arbitrum", ArbitrumUSDC, ArbitrumWETH, 500);
        _depositWETH(optimism, "Optimism", OptimismUSDC, OptimismWETH, 500);
        _depositWETH(polygon, "Polygon", PolygonUSDC, PolygonWMATIC, 500);
    }

    function testRevertAmountOutMin() public {
        vm.selectFork(arbitrum);
        // deploy contracts
        super.setUp();

        // link SwapRouter address and USDC address
        store.link(address(trade), address(pool), ArbitrumUSDC, address(clp));
        store.linkUniswap(swapRouter, quoter, ArbitrumWETH);

        // give user 1000 DAI
        deal(ArbitrumDAI, user, 1000 ether);

        vm.startPrank(user);

        // add liquidity with DAI
        IERC20(ArbitrumDAI).approve(address(store), 1000 ether);

        // we use a pair with low liquidity, swap should revert because amountOut < amountOutMin
        // amountOutMin is 990 USDC, we swap 1000 DAI, so used slippage is 1%
        vm.expectRevert("Too little received");
        pool.addLiquidityThroughUniswap(ArbitrumDAI, 1000 ether, 990 * CURRENCY_UNIT, 3000);

        vm.stopPrank();
    }

    function _getEstimatedOutput(
        uint256 fork,
        string memory name,
        address usdc,
        address dai,
        address weth,
        uint24 poolFee
    ) internal {
        vm.selectFork(fork);
        console.log(name);

        // deploy contracts
        super.setUp();

        // link SwapRouter address and USDC address
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(swapRouter, quoter, weth);

        // get estimated output tokens for 1 WETH (or 1 Matic on Polygon)
        uint256 amountOutWETH = store.getEstimatedOutputTokens(1 ether, weth, 500);
        if (fork == polygon) console.log("Estimated output for 1 WMATIC:", amountOutWETH);
        else console.log("Estimated output for 1 WETH:", amountOutWETH);

        // get estimated output for 1000 DAI input
        uint256 amountOutDAI = store.getEstimatedOutputTokens(1000 ether, dai, poolFee);
        console.log("Estimated output for 1000 DAI:", amountOutDAI);
        console.log("-----------------------");
    }

    function _addLiquidityDAI(uint256 fork, string memory name, address usdc, address dai, address weth, uint24 poolFee)
        internal
    {
        vm.selectFork(fork);
        console.log(name);

        // deploy contracts
        super.setUp();

        // link SwapRouter address and USDC address
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(swapRouter, quoter, weth);

        // give user 1000 DAI
        deal(dai, user, 1000 ether);

        vm.startPrank(user);

        // check estimated output
        uint256 amountOutDAI = store.getEstimatedOutputTokens(1000 ether, dai, poolFee);

        // 1% slippage
        uint256 amountOutMin = amountOutDAI * 99 / 100;

        // add liquidity with DAI
        IERC20(dai).approve(address(store), 1000 ether);
        pool.addLiquidityThroughUniswap(dai, 1000 ether, amountOutMin, poolFee);
        console.log("Added USDC Liquidity with DAI:", store.getUserPoolBalance(user));

        vm.stopPrank();
        console.log("-----------------------");
    }

    function _addLiquidityWETH(uint256 fork, string memory name, address usdc, address weth, uint24 poolFee) internal {
        vm.selectFork(fork);
        console.log(name);

        // deploy contracts
        super.setUp();

        // link SwapRouter address and USDC address
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(swapRouter, quoter, weth);

        // give user some ETH
        vm.deal(user, 10 ether);

        vm.startPrank(user);

        uint256 amountOutWETH = store.getEstimatedOutputTokens(1 ether, weth, poolFee);

        // 1% slippage
        uint256 amountOutMin = amountOutWETH * 99 / 100;

        // add liquidity with ETH
        pool.addLiquidityThroughUniswap{value: 1 ether}(address(0), 0, amountOutMin, poolFee);

        if (fork == polygon) console.log("Added USDC Liquidity with MATIC:", store.getUserPoolBalance(user));
        else console.log("Added USDC Liquidity with ETH:", store.getUserPoolBalance(user));

        vm.stopPrank();
        console.log("-----------------------");
    }

    function _depositDAI(uint256 fork, string memory name, address usdc, address dai, address weth, uint24 poolFee)
        internal
    {
        vm.selectFork(fork);
        console.log(name);

        // deploy contracts
        super.setUp();

        // link SwapRouter address and USDC address
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(swapRouter, quoter, weth);

        // give user 1000 DAI
        deal(dai, user, 1000 ether);

        vm.startPrank(user);

        // check estimated output
        uint256 amountOutDAI = store.getEstimatedOutputTokens(1000 ether, dai, poolFee);

        // 1% slippage
        uint256 amountOutMin = amountOutDAI * 99 / 100;

        // deposit with DAI
        IERC20(dai).approve(address(store), 1000 ether);
        trade.depositThroughUniswap(dai, 1000 ether, amountOutMin, poolFee);
        console.log("Deposited USDC with DAI:", store.getBalance(user));

        vm.stopPrank();
        console.log("-----------------------");
    }

    function _depositWETH(uint256 fork, string memory name, address usdc, address weth, uint24 poolFee) internal {
        vm.selectFork(fork);
        console.log(name);

        // deploy contracts
        super.setUp();

        // link SwapRouter address and USDC address
        store.link(address(trade), address(pool), usdc, address(clp));
        store.linkUniswap(swapRouter, quoter, weth);

        // give user some ETH
        vm.deal(user, 10 ether);

        vm.startPrank(user);

        // get estimated output
        uint256 amountOutWETH = store.getEstimatedOutputTokens(1 ether, weth, poolFee);

        // 1% slippage
        uint256 amountOutMin = amountOutWETH * 99 / 100;

        // deposit with ETH
        trade.depositThroughUniswap{value: 1 ether}(address(0), 0, amountOutMin, poolFee);

        // native token on Polygon is MATIC
        if (fork == polygon) console.log("Deposited USDC with MATIC:", store.getBalance(user));
        else console.log("Deposited USDC with ETH:", store.getBalance(user));

        vm.stopPrank();
        console.log("-----------------------");
    }
}
