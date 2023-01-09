//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./utils/TestUtils.sol";

contract PoolTest is TestUtils {
    // Events
    event AddLiquidity(address indexed user, uint256 amount, uint256 clpAmount, uint256 poolBalance);
    event RemoveLiquidity(
        address indexed user, uint256 amount, uint256 feeAmount, uint256 clpAmount, uint256 poolBalance
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public virtual override {
        super.setUp();

        _submitAndExecuteOrders();
    }

    function testCreditTraderLoss() public {
        // set ETH price to stop loss price, stop loss order should execute
        chainlink.setPrice(ethFeed, ETH_SL_PRICE);
        trade.executeOrders();

        // ETH went down 2%, position size was 100k, so user lost 2k
        // poolLastPaid = 0, so full amount should be used to increment Buffer balance
        assertEq(store.bufferBalance(), 2000 * CURRENCY_UNIT, "!bufferBalance");

        // fast forward one day
        skip(1 days);

        // set BTC price to stop loss price, stop loss order should execute
        chainlink.setPrice(btcFeed, BTC_SL_PRICE);
        trade.executeOrders();

        // BTC went down 2%, position size was 100k, so user lost 2k -> bufferBalance = 4k USDC
        // we fast forwarded one day, so amountToSendPool = 4k USDC * 1/7 = 571.43

        // buffer balance should be reduced
        assertApproxEqRel(
            store.bufferBalance(),
            (4000 - 571) * CURRENCY_UNIT,
            0.01 * 1e18,
            "bufferBalance != 4000 USDC - amountToSendPool"
        );
        // pool balance should be amountToSendPool + fees
        assertGt(store.poolBalance(), 571 * CURRENCY_UNIT, "!(poolBalance > amountToSendPool)");
    }

    function testDebitTraderProfit() public {
        // add pool liquidity
        pool.addLiquidity(5000 * CURRENCY_UNIT);
        // set msg.sender = trade contract to set buffer balance
        vm.prank(address(trade));
        store.incrementBufferBalance(2000 * CURRENCY_UNIT);

        // Check that balances are correct
        assertEq(store.bufferBalance(), 2000 * CURRENCY_UNIT, "!bufferBalance");
        assertGt(store.poolBalance(), 5000 * CURRENCY_UNIT, "!poolBalance");

        // set ETH price to 5100 USDC, TP order should execute -> user made 2k profit
        chainlink.setPrice(ethFeed, ETH_TP_PRICE);
        trade.executeOrders();

        assertEq(store.bufferBalance(), 0, "bufferBalance != 0");

        // set BTC price to 102k, TP order should execute -> user made 2k profit
        chainlink.setPrice(btcFeed, BTC_TP_PRICE);
        trade.executeOrders();

        // buffer is already empty so profits are taken from the pool
        assertGt(store.poolBalance(), 3000 * CURRENCY_UNIT, "!poolBalance");

        // in total 6 orders were executed
        uint256 fee = _getOrderFee("ETH-USD", ethLong.size) * 6;
        // user balance should be initital deposit - orderFees + profit
        assertEq(store.getBalance(user), INITIAL_TRADE_DEPOSIT - fee + 4000 * CURRENCY_UNIT, "!userBalance");
    }

    function testCreditFee() public {
        // ETH and BTC Long are executed, position size is 10k each, fee is 10 USDC each
        uint256 fee = _getOrderFee("ETH-USD", ethLong.size) + _getOrderFee("BTC-USD", btcLong.size);
        uint256 keeperFee = fee * store.keeperFeeShare() / BPS_DIVIDER;
        fee -= keeperFee;
        uint256 poolFee = fee * store.poolFeeShare() / BPS_DIVIDER;
        uint256 treasuryFee = fee - poolFee;

        assertEq(store.poolBalance(), poolFee, "!poolFee");
        assertEq(IERC20(usdc).balanceOf(treasury), treasuryFee, "!treasuryFee");
        assertEq(store.getBalance(address(this)), keeperFee, "!keeperFee");
    }

    function testRevertPoolBalance() public {
        // add pool liquidity
        pool.addLiquidity(1000 * CURRENCY_UNIT);
        assertGt(store.poolBalance(), 1000 * CURRENCY_UNIT, "!poolBalance");

        // set ETH to ETH_TP_PRICE, TP order should execute -> user made 2k profit
        chainlink.setPrice(ethFeed, ETH_TP_PRICE);

        // pool liquidity is 1k, not enough to pay trader profit
        vm.expectRevert("!pool-balance");
        trade.executeOrders();
    }

    /// @param amount amount of liquidity to add and remove (Fuzzer)
    function testFuzzAddAndRemoveLiquidity(uint256 amount) public {
        vm.assume(amount > 1 * CURRENCY_UNIT && amount <= INITIAL_BALANCE);

        // one ETH long and one BTC long is already executed
        uint256 fee = _getOrderFee("ETH-USD", ethLong.size) + _getOrderFee("BTC-USD", btcLong.size);
        uint256 keeperFee = fee * store.keeperFeeShare() / BPS_DIVIDER;
        fee -= keeperFee;
        uint256 poolFee = fee * store.poolFeeShare() / BPS_DIVIDER;

        // expect AddLiquidity event
        vm.expectEmit(true, true, true, true);
        emit AddLiquidity(user, amount, amount, amount + poolFee);
        vm.prank(user);
        pool.addLiquidity(amount);

        // pool balance should be equal to amount + fees
        assertEq(store.poolBalance(), amount + poolFee, "!poolBalance");

        uint256 feeAmount = amount * store.poolWithdrawalFee() / BPS_DIVIDER;
        uint256 amountMinusFee = amount - feeAmount;

        // CLP amount
        uint256 balance = store.poolBalance();
        uint256 clpSupply = store.getCLPSupply();
        uint256 clpAmount = amountMinusFee * clpSupply / balance;

        console.log("poolFee", poolFee);
        console.log("feeAMount", feeAmount);

        // CLP should be burned
        vm.expectEmit(true, true, true, true);
        emit Transfer(user, address(0), clpAmount);

        // expect RemoveLiquidity event
        vm.expectEmit(true, true, true, true);
        emit RemoveLiquidity(user, amount, feeAmount, clpAmount, poolFee + feeAmount);
        vm.prank(user);
        pool.removeLiquidity(amount);
    }
}
