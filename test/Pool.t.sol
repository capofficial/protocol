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
        _depositAndSubmitOrders();

        // ETH and BTC Long are executed, position size is 10k each, fee is 100 USDC each
        uint256 fee = 200 * CURRENCY_UNIT;
        uint256 keeperFee = fee * store.keeperFeeShare() / BPS_DIVIDER;
        fee -= keeperFee;
        uint256 poolFee = fee * store.poolFeeShare() / BPS_DIVIDER;
        uint256 treasuryFee = fee - poolFee;

        assertEq(store.poolBalance(), poolFee, "!poolFee");
        assertEq(IERC20(usdc).balanceOf(treasury), treasuryFee, "!treasuryFee");
        assertEq(store.getBalance(address(this)), keeperFee, "!keeperFee");
    }

    function testRevertPoolBalance() public {
        _depositAndSubmitOrders();

        // add pool liquidity
        pool.addLiquidity(1000 * CURRENCY_UNIT);
        assertGt(store.poolBalance(), 1000 * CURRENCY_UNIT, "!poolBalance");

        // set ETH price to 6000 USDC, TP order should execute -> user made 2k profit
        chainlink.setPrice(ethFeed, 6000);

        // pool liquidity is 1k, not enough to pay trader profit
        vm.expectRevert("!pool-balance");
        trade.executeOrders();
    }

    /// @param amount amount of liquidity to add and remove (Fuzzer)
    function testFuzzAddAndRemoveLiquidity(uint256 amount) public {
        vm.assume(amount > 1 * CURRENCY_UNIT && amount <= INITIAL_BALANCE);

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
}
