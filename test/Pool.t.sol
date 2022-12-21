//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";

contract PoolTest is SetupTest {
    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(user);
    }

    function testAddLiquidity(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000000 * CURRENCY_UNIT);
        pool.addLiquidity(amount);

        assertEq(store.poolBalance(), amount);
    }

    function testAddLiquidityThroughUniswap(uint256 amount) public {}
}
