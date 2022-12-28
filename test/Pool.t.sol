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
    }

    function testCreditTraderLoss() public {
        _depositAndSubmitOrders();

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

    function testDebitTraderProfit() public {
        _depositAndSubmitOrders();

        // add pool liquidity
        pool.addLiquidity(5000 * CURRENCY_UNIT);
        // set msg.sender = trade contract to set buffer balance
        vm.prank(address(trade));
        store.incrementBufferBalance(2000 * CURRENCY_UNIT);

        assertEq(store.bufferBalance(), 2000 * CURRENCY_UNIT, "!bufferBalance");
        assertGt(store.poolBalance(), 5000 * CURRENCY_UNIT, "!poolBalance");

        // set ETH price to 6000 USDC, TP order should execute -> user made 2k profit
        chainlink.setPrice(ethFeed, 6000);
        trade.executeOrders();

        assertEq(store.bufferBalance(), 0, "bufferBalance != 0");

        // set BTC price to 120k, TP order should execute -> user made 2k profit
        chainlink.setPrice(btcFeed, 120_000);
        trade.executeOrders();

        // buffer is already empty so profits are taken from the pool
        assertGt(store.poolBalance(), 3000 * CURRENCY_UNIT, "!poolBalance");

        // user balance should be initital deposit + profit - orderFees => 10k + 4k - 600 = 18400
        assertEq(store.getBalance(user), 13400 * CURRENCY_UNIT, "!userBalance");
    }

    function testCreditFee() public {
        // submit order with size of 10k USDC => fee = 100 USDC (45 Pool, 45 Treasury, 10 Keeper)
        vm.startPrank(user);
        trade.deposit(10000 * CURRENCY_UNIT);
        trade.submitOrder(btcLong, 0, 0);
        vm.stopPrank();

        uint256 oldKeeperBalance = IERC20(usdc).balanceOf(address(this));
        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        assertEq(store.poolBalance(), 45 * CURRENCY_UNIT, "!poolFee");
        assertEq(IERC20(usdc).balanceOf(treasury), 45 * CURRENCY_UNIT, "!treasuryFee");
        assertEq(IERC20(usdc).balanceOf(address(this)), oldKeeperBalance + 10 * CURRENCY_UNIT, "!keeperFee");
    }

    /// @param amount amount of liquidity to add and remove (Fuzzer)
    function testFuzzAddAndRemoveLiquidity(uint256 amount) public {
        vm.assume(amount > 1 * CURRENCY_UNIT && amount <= 1000000 * CURRENCY_UNIT);

        // expect AddLiquidity event
        vm.expectEmit(true, true, true, true);
        emit AddLiquidity(user, amount, amount, amount);
        vm.prank(user);
        pool.addLiquidity(amount);

        // pool balance should be equal to amount + fees
        assertEq(store.poolBalance(), amount, "poolBalance != amount");


        uint256 feeAmount = amount * store.poolWithdrawalFee() / BPS_DIVIDER;
        uint256 amountMinusFee = amount - feeAmount;
        // CLP amount is amountMinusFee, since clpSupply and poolBalance is identical
        uint256 clpAmount = amountMinusFee;

        // CLP should be burned
        vm.expectEmit(true, true, true, true);
        emit Transfer(user, address(0), clpAmount);
        // expect RemoveLiquidity event
        vm.expectEmit(true, true, true, true);
        emit RemoveLiquidity(user, amount, feeAmount, clpAmount, feeAmount);
        vm.prank(user);
        pool.removeLiquidity(amount);
    }

    function _depositAndSubmitOrders() internal {
        vm.startPrank(user);

        trade.deposit(10000 * CURRENCY_UNIT);
        // submit two test orders with stop loss 10% below current price and TP 20% above current price
        trade.submitOrder(ethLong, 6000, 4500);
        trade.submitOrder(btcLong, 120_000, 90000);
        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        vm.stopPrank();
    }
}
