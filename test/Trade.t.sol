//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";

contract TradeTest is SetupTest {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(user);

        // deposit 5000 USDC for trading
        trade.deposit(5000 * CURRENCY_UNIT);
    }

    function testOrderAndPositionStorage() public {
        // submit ETH long with stop loss
        trade.submitOrder(ethLong, 0, 4500);

        // should be two orders: ETH long and SL
        assertEq(_printOrders(), 2, "!orderCount");
        assertEq(_printUserPositions(user), 0, "!positionCount");

        console.log("-------------------------------");
        console.log();

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        // should be one SL order and one long position
        assertEq(_printOrders(), 1, "!orderCount");
        assertEq(_printUserPositions(user), 1, "!positionCount");

        console.log("-------------------------------");

        // set ETH price to SL price and execute SL order
        chainlink.setPrice(ethFeed, 4500);
        trade.executeOrders();

        // should be zero orders, zero positions
        assertEq(_printOrders(), 0, "!orderCount");
        assertEq(_printUserPositions(user), 0, "!positionCount");
    }

    function testExceedFreeMargin() public {
        // submit first order with 2500 margin
        trade.submitOrder(ethLong, 0, 0);
        assertEq(2500 * CURRENCY_UNIT, store.getLockedMargin(user), "lockedMargin != 2500 USDC");

        // submit second order with 2000 margin
        ethLong.margin = 2000 * CURRENCY_UNIT;
        trade.submitOrder(ethLong, 0, 0);
        assertEq(4500 * CURRENCY_UNIT, store.getLockedMargin(user), "lockedMargin != 2500 USDC");

        // balance should be 4800 USDC since submitting an order incurs a 100 USDC fee
        assertEq(4800 * CURRENCY_UNIT, store.getBalance(user), "balance != 4800 USDC");

        // at this point, lockedMargin = 4500 USDC and balance = 4800 USDC
        // freeMargin = balance - lockedMargin = 300 USDC

        // submit third order with 1000 USDC margin
        ethLong.margin = 1000 * CURRENCY_UNIT;
        trade.submitOrder(ethLong, 0, 0);

        Store.Order[] memory _orders = store.getUserOrders(user);

        // contract should have set order margin to 300
        assertEq(_orders[2].margin, 300 * CURRENCY_UNIT, "!orderMargin");

        // position.size was unchanged at 10000 USDC, so leverage = 10
        // since margin was decreased to 300 USDC, new position size for third order should be 3000 USDC
        assertEq(_orders[2].size, 3000 * CURRENCY_UNIT, "!positionSize");

        // taking order fees into account, equity is now below lockedMargin
        // submitting new orders shouldnt be possible
        vm.expectRevert("!equity");
        trade.submitOrder(ethLong, 0, 0);
    }
}
