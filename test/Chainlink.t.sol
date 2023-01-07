//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/Chainlink.sol";

contract ChainlinkTest is Test {
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

    Chainlink public chainlink;

    function setUp() public {
        arbitrum = vm.createFork(ARBITRUM_RPC_URL);
        optimism = vm.createFork(OPTIMISM_RPC_URL);
        polygon = vm.createFork(POLYGON_RPC_URL);
        bnb = vm.createFork(BNB_RPC_URL);
        avalanche = vm.createFork(AVAX_RPC_URL);
        fantom = vm.createFork(FANTOM_RPC_URL);
    }

    function testNetworks() public {
        _getPriceOnL2(
            arbitrum, "Arbitrum", 0xFdB631F5EE196F0ed6FAa767959853A9F217697D, 0x6ce185860a4963106506C203335A2910413708e9
        );
        _getPriceOnL2(
            optimism, "Optimism", 0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389, 0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593
        );
        _getPriceOnSidechain(polygon, "Polygon", 0xc907E116054Ad103354f2D350FD2514433D57F6f);
        _getPriceOnSidechain(bnb, "Binance Smart Chain", 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf);
        _getPriceOnSidechain(avalanche, "Avalanche", 0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743);
        _getPriceOnSidechain(fantom, "Fantom", 0x8e94C22142F4A64b99022ccDd994f4e9EC86E4B4);
    }

    function _getPriceOnL2(uint256 fork, string memory name, address sequencer, address feed) internal {
        vm.selectFork(fork);

        console.log(name);

        chainlink = new Chainlink(sequencer);
        console.log("Chainlink deployed to", address(chainlink));

        // get price
        uint256 result = chainlink.getPrice(feed);
        assert(result > 0);
        console.log("BTC-USD:", result);

        console.log("-----------------------");
    }

    function _getPriceOnSidechain(uint256 fork, string memory name, address feed) internal {
        vm.selectFork(fork);

        console.log(name);

        chainlink = new Chainlink(address(0));
        console.log("Chainlink deployed to", address(chainlink));

        // get price
        uint256 result = chainlink.getPrice(feed);
        assert(result > 0);
        console.log("BTC-USD:", result);

        console.log("-----------------------");
    }
}
