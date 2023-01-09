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
        margin: 0, // will be set in Trade.submitOrder (size / market.maxLeverage)
        size: 100_000 * CURRENCY_UNIT,
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
        margin: 0, // will be set in Trade.submitOrder (size / market.maxLeverage)
        size: 100_000 * CURRENCY_UNIT,
        fee: 0,
        timestamp: 0
    });

    IStore.Order ethLongLimit = IStore.Order({
        orderId: 0,
        user: address(0),
        market: "ETH-USD",
        price: 4000,
        isLong: true,
        isReduceOnly: false,
        orderType: 1, // 0 = market, 1 = limit, 2 = stop
        margin: 0, // will be set in Trade.submitOrder (size / market.maxLeverage)
        size: 100_000 * CURRENCY_UNIT,
        fee: 0,
        timestamp: 0
    });

    IStore.Order ethShort = IStore.Order({
        orderId: 0,
        user: address(0),
        market: "ETH-USD",
        price: 0, // price doesnt matter, since ordertype = market
        isLong: false,
        isReduceOnly: false,
        orderType: 0, // 0 = market, 1 = limit, 2 = stop
        margin: 0, // will be set in Trade.submitOrder (size / market.maxLeverage)
        size: 100_000 * CURRENCY_UNIT,
        fee: 0,
        timestamp: 0
    });

    IStore.Order btcShort = IStore.Order({
        orderId: 0,
        user: address(0),
        market: "BTC-USD",
        price: 0, // price doesnt matter, since ordertype = market
        isLong: false,
        isReduceOnly: false,
        orderType: 0, // 0 = market, 1 = limit, 2 = stop
        margin: 0, // will be set in Trade.submitOrder (size / market.maxLeverage)
        size: 100_000 * CURRENCY_UNIT,
        fee: 0,
        timestamp: 0
    });

    // Helper functions
    function _submitAndExecuteOrders() internal {
        vm.startPrank(user);

        // deposit funds for trading
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        // submit two test orders with stop loss 2% below current price and TP 2% above current price
        trade.submitOrder(ethLong, 5100 * UNIT, 4900 * UNIT);
        trade.submitOrder(btcLong, 102_000 * UNIT, 98000 * UNIT);
        vm.stopPrank();

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();
    }

    // returns order fee
    function _getOrderFee(string memory market, uint256 orderSize) internal view returns (uint256 fee) {
        IStore.Market memory _market = store.getMarket(market);

        // order fee
        fee = _market.fee * orderSize / BPS_DIVIDER;
    }

    // console.log orders if log == true, returns length of order array
    function _printOrders(bool log) internal view returns (uint256) {
        IStore.Order[] memory _orders = store.getOrders();

        if (log) {
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
        }

        return _orders.length;
    }

    // console.log positions if log == true, returns length of user positions array
    function _printUserPositions(address _user, bool log) internal returns (uint256) {
        IStore.Position[] memory _positions = store.getUserPositions(_user);

        if (log) {
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
        }

        return _positions.length;
    }
}
