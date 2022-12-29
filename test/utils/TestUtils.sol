// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./SetupTest.sol";

contract TestUtils is SetupTest {
    // Test Orders
    IStore.Order ethLong = IStore.Order({
        orderId: 0,
        user: address(0),
        market: "ETH-USD",
        price: 0, // price doesnt matter, since ordertype = market
        isLong: true,
        isReduceOnly: false,
        orderType: 0, // 0 = market, 1 = limit, 2 = stop
        margin: 2500 * CURRENCY_UNIT,
        size: 10000 * CURRENCY_UNIT, // leverage => 5x
        fee: 0,
        timestamp: 0
    });

    IStore.Order btcLong = IStore.Order({
        orderId: 0,
        user: address(0),
        market: "BTC-USD",
        price: 0, // price doesnt matter, since ordertype = market
        isLong: true,
        isReduceOnly: false,
        orderType: 0, // 0 = market, 1 = limit, 2 = stop
        margin: 2500 * CURRENCY_UNIT,
        size: 10000 * CURRENCY_UNIT, // leverage => 5x
        fee: 0,
        timestamp: 0
    });

    // Helper functions
    function _depositAndSubmitOrders() internal {
        vm.startPrank(user);
        trade.deposit(10000 * CURRENCY_UNIT);
        // submit two test orders with stop loss 10% below current price and TP 20% above current price
        trade.submitOrder(ethLong, 6000, 4500);
        trade.submitOrder(btcLong, 120_000, 90000);
        vm.stopPrank();

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();
    }

    function _printOrders() internal view returns (uint256) {
        IStore.Order[] memory _orders = store.getOrders();

        for (uint256 i = 0; i < _orders.length; i++) {
            console.log("/* ========== ORDER ========== */");
            console.log("Order ID:", _orders[i].orderId);
            console.log("User:", _orders[i].user);
            console.log("Market:", _orders[i].market);
            console.log("Price:", _orders[i].price);
            console.log("isLong:", _orders[i].isLong);
            console.log("isReduceOnly:", _orders[i].isReduceOnly);
            console.log("orderType:", _orders[i].orderType);
            console.log("margin:", _orders[i].margin);
            console.log("size:", _orders[i].size);
            console.log("fee:", _orders[i].fee);
            console.log("timestamp:", _orders[i].timestamp);
            console.log();
        }

        return _orders.length;
    }

    function _printUserPositions(address _user) internal returns (uint256) {
        IStore.Position[] memory _positions = store.getUserPositions(_user);

        for (uint256 i = 0; i < _positions.length; i++) {
            console.log("/* ========== POSITION ========== */");
            console.log("User:", _positions[i].user);
            console.log("Market:", _positions[i].market);
            console.log("Price:", _positions[i].price);
            console.log("isLong:", _positions[i].isLong);
            console.log("margin:", _positions[i].margin);
            console.log("size:", _positions[i].size);
            emit log_named_int("fundingTracker", _positions[i].fundingTracker);
            console.log("timestamp:", _positions[i].timestamp);
            console.log();
        }

        return _positions.length;
    }
}
