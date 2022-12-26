//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";

contract PoolTest is SetupTest {
    // Events
    event AddLiquidity(address indexed user, uint256 amount, uint256 clpAmount, uint256 poolBalance);
    event RemoveLiquidity(
        address indexed user, uint256 amount, uint256 feeAmount, uint256 clpAmount, uint256 poolBalance
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    // Constants
    uint256 public constant BPS_DIVIDER = 10000;

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(user);
    }

    /// @param amount amount of liquidity to add and remove (Fuzzer)
    function testFuzzAddAndRemoveLiquidity(uint256 amount) public {
        vm.assume(amount > 1 && amount <= 1000000 * CURRENCY_UNIT);

        // expect AddLiquidity event
        vm.expectEmit(true, true, true, true);
        emit AddLiquidity(user, amount, amount, amount);

        pool.addLiquidity(amount);

        // pool balance should be equal to amount
        assertEq(store.poolBalance(), amount);

        // CLP should be burned
        vm.expectEmit(true, true, true, true);
        emit Transfer(user, address(0), amount);

        uint256 feeAmount = amount * store.poolWithdrawalFee() / BPS_DIVIDER;
        uint256 amountMinusFee = amount - feeAmount;
        // CLP amount is amountMinusFee, since clpSupply and poolBalance is identical
        uint256 clpAmount = amountMinusFee;

        vm.expectEmit(true, true, true, true);
        emit RemoveLiquidity(user, amount, feeAmount, clpAmount, feeAmount);

        pool.removeLiquidity(amount);

        // fee should remain in the pool
        assertEq(store.poolBalance(), feeAmount);
    }
}
