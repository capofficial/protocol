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

        trade.deposit(10000 * CURRENCY_UNIT);

        // submit two test orders with stop loss 10% below current price
        trade.submitOrder(ethLong, 0, 4500);
        trade.submitOrder(btcLong, 0, 90000);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        vm.stopPrank();
    }

    function testCreditTraderLoss() public {
        // set ETH price to stop loss price, stop loss order should execute
        chainlink.setPrice(ethFeed, 4500);
        trade.executeOrders();

        // ETH went down 10%, position size was 10k, so user lost 1k
        // poolLastPaid = 0, so full amount should be used to increment Buffer balance
        assertEq(store.bufferBalance(), 1000 * CURRENCY_UNIT, "bufferBalance != 1000 USDC");

        // fast forward one day
        skip(1 days);

        // set BTC price to stop loss price, stop loss order should execute
        chainlink.setPrice(btcFeed, 90000);
        trade.executeOrders();

        // BTC went down 10%, position size was 10k, so user lost 1k -> bufferBalance = 2k USDC
        // we fast forwarded one day, so amountToSendPool = 2k USDC * 1/7 = 285.71

        // buffer balance should be reduced
        assertApproxEqRel(
            store.bufferBalance(),
            (2000 - 285) * CURRENCY_UNIT,
            0.01 * 1e18,
            "bufferBalance != 2000 USDC - amountToSendPool"
        );
        // pool balance should be amountToSendPool + fees
        assertGt(store.poolBalance(), 285 * CURRENCY_UNIT, "!(poolBalance > amountToSendPool)");
    }

    /// @param amount amount of liquidity to add and remove (Fuzzer)
    function testFuzzAddAndRemoveLiquidity(uint256 amount) public {
        vm.assume(amount > 1 && amount <= 1000000 * CURRENCY_UNIT);

        // expect AddLiquidity event
        vm.expectEmit(true, true, true, true);
        emit AddLiquidity(user, amount, amount, amount);

        pool.addLiquidity(amount);

        // pool balance should be equal to amount
        assertEq(store.poolBalance(), amount, "poolBalance != amount");

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
        assertEq(store.poolBalance(), feeAmount, "poolBalance != feeAmount");
    }
}
