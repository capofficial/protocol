//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";

contract TradeTest is SetupTest {
    Store.Order testOrder = Store.Order({
        orderId: 0,
        user: address(0),
        market: "ETH-USD",
        price: 0, // price doesnt matter, since ordertype = market
        isLong: true,
        isReduceOnly: false,
        orderType: 0, // 0 = market, 1 = limit, 2 = stop
        margin: 2500 * CURRENCY_UNIT,
        size: 10000 * CURRENCY_UNIT,
        fee: 0,
        timestamp: 0
    });

    function setUp() public virtual override {
        super.setUp();

        // set price feed; 1 ETH = 5000 USDC
        chainlink.setPrice(address(0), 5000);

        vm.startPrank(user);
    }

    function testSubmitOrder() public {
        trade.deposit(5000 * CURRENCY_UNIT); // 5000 USDC
        trade.submitOrder(testOrder, 0, 0);

        // minSettlementTime is 1 minutes
        vm.warp(2 minutes);
        trade.executeOrders();
    }

    function testExceedFreeMargin() public {
        trade.deposit(5000 * CURRENCY_UNIT); // 5000 USDC
        assertEq(5000 * CURRENCY_UNIT, store.getBalance(user));

        trade.submitOrder(testOrder, 0, 0);
        assertEq(2500 * CURRENCY_UNIT, store.getLockedMargin(user));

        // submit second order with 2000 margin
        testOrder.margin = 2000 * CURRENCY_UNIT;
        trade.submitOrder(testOrder, 0, 0);
        assertEq(4500 * CURRENCY_UNIT, store.getLockedMargin(user));

        // balance should be 4800 USDC since submitting an order incurs a 100 USDC fee
        assertEq(4800 * CURRENCY_UNIT, store.getBalance(user));

        // at this point, lockedMargin = 4500 USDC and balance = 4800 USDC
        // freeMargin = balance - lockedMargin = 300 USDC

        // submit third order with 1000 USDC margin
        testOrder.margin = 1000 * CURRENCY_UNIT;
        trade.submitOrder(testOrder, 0, 0);

        Store.Order[] memory _orders = store.getUserOrders(user);

        // contract should have set order margin to 300
        assertEq(_orders[2].margin, 300 * CURRENCY_UNIT);

        // position.size was unchanged at 10000 USDC, so leverage = 10
        // since margin was decreased to 300 USDC, new position size for third order should be 3000 USDC
        assertEq(_orders[2].size, 3000 * CURRENCY_UNIT);

        // taking order fees into account, equity is now below lockedMargin
        // submitting new orders shouldnt be possible
        vm.expectRevert("!equity");
        trade.submitOrder(testOrder, 0, 0);
    }
}
