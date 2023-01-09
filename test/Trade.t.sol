//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./utils/TestUtils.sol";

contract TradeTest is TestUtils {
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(user);
    }

    function testOrderAndPositionStorage() public {
        // deposit 5000 USDC for trading
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        // submit ETH long with stop loss
        trade.submitOrder(ethLong, 0, 4500 * UNIT);

        // console.log orders and positions? true = yes, false = no
        bool flag = false;

        // should be two orders: ETH long and SL
        assertEq(_printOrders(flag), 2, "!orderCount");
        assertEq(_printUserPositions(user, flag), 0, "!positionCount");

        console.log();

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        // should be one SL order and one long position
        assertEq(_printOrders(flag), 1, "!orderCount");
        assertEq(_printUserPositions(user, flag), 1, "!positionCount");

        // set ETH price to SL price and execute SL order
        chainlink.setPrice(ethFeed, 4500 * UNIT);
        trade.executeOrders();

        // should be zero orders, zero positions
        assertEq(_printOrders(flag), 0, "!orderCount");
        assertEq(_printUserPositions(user, flag), 0, "!positionCount");
    }

    function testExceedFreeMargin() public {
        // deposit 5000 USDC for trading
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        // submit first order, order.size = 100k, leverage = 50 -> margin 2k
        trade.submitOrder(ethLong, 0, 0);
        assertEq(2000 * CURRENCY_UNIT, store.getLockedMargin(user), "!lockedMargin");

        // submit second order, order.size = 100k, leverage = 50 -> margin 2k
        trade.submitOrder(btcLong, 0, 0);
        assertEq(4000 * CURRENCY_UNIT, store.getLockedMargin(user), "!lockedMargin");

        // balance should be initial deposit - fee (4800 USDC)
        uint256 fee = _getOrderFee("ETH-USD", ethLong.size) + _getOrderFee("BTC-USD", btcLong.size);
        assertEq(INITIAL_TRADE_DEPOSIT - fee, store.getBalance(user), "!balance");

        // at this point, lockedMargin = 4000 USDC and balance = 4800 USDC
        // freeMargin = balance - lockedMargin = 800 USDC

        // submit third order, order.size = 100k, leverage = 50 -> margin 2k
        trade.submitOrder(ethLong, 0, 0);

        Store.Order[] memory _orders = store.getUserOrders(user);

        // since freeMargin = 800, contract should have set margin of newest position to 800 USDC
        assertEq(_orders[2].margin, 800 * CURRENCY_UNIT, "!orderMargin");

        // order.size should be order.margin * market.maxLeverage
        IStore.Market memory _market = store.getMarket("ETH-USD");
        assertEq(_orders[2].size, _orders[2].margin * _market.maxLeverage, "!orderSize");

        // taking order fees into account, equity is now below lockedMargin
        // submitting new orders shouldnt be possible
        vm.expectRevert("!equity");
        trade.submitOrder(ethLong, 0, 0);
    }

    /// @param amount deposit amount
    function testFuzzDepositAndWithdraw(uint256 amount) public {
        vm.assume(amount > 1 && amount <= INITIAL_BALANCE);

        // expect Deposit event
        vm.expectEmit(true, true, true, true);
        emit Deposit(user, amount);
        trade.deposit(amount);

        // balance should be equal to amount
        assertEq(store.getBalance(user), amount, "!userBalance");
        assertEq(IERC20(usdc).balanceOf(address(store)), amount, "!storeBalance");

        // expect withdraw event
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, amount);
        trade.withdraw(amount);
    }

    function testRevertWithdraw() public {
        vm.expectRevert("!amount");
        trade.withdraw(0);

        trade.deposit(INITIAL_TRADE_DEPOSIT);

        // submit order, order.size 100k, margin 2k
        trade.submitOrder(ethLong, 0, 0);

        // locked margin = 2000 USDC, orderfee = 100 USDC => withdrawing more than 2900 USDC shouldnt work
        uint256 fee = _getOrderFee("ETH-USD", ethLong.size);
        IStore.Order memory order = store.getOrder(1);
        uint256 maxAmountToWithdraw = INITIAL_TRADE_DEPOSIT - order.margin - fee;
        vm.expectRevert("!equity");
        trade.withdraw(maxAmountToWithdraw + 1);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        // set eth price above 5k USD so trade is in profit
        chainlink.setPrice(ethFeed, 5100 * UNIT);

        // withdrawing should work
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, maxAmountToWithdraw + 1);
        trade.withdraw(maxAmountToWithdraw + 1);
    }

    function testRevertOrderType() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        ethLongLimit.price = 6000 * UNIT;

        // orderType == 1 && isLong == true && chainLinkPrice <= order.price, should revert
        vm.expectRevert("!orderType");
        trade.submitOrder(ethLongLimit, 0, 0);
    }

    function testUpdateOrder() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        trade.submitOrder(ethLongLimit, 0, 0);

        // update order
        trade.updateOrder(1, 6000 * UNIT);
        IStore.Order[] memory _orders = store.getOrders();

        // order type from 1 => 2
        assertEq(_orders[0].orderType, 2);
        // price should be 6000
        assertEq(_orders[0].price, 6000 * UNIT);
    }

    function testRevertUpdateOrder() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        // submit ETH market long
        trade.submitOrder(ethLong, 0, 0);
        vm.expectRevert("!market-order");
        trade.updateOrder(1, 5000);
    }

    function testCancelOrder() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        trade.submitOrder(ethLongLimit, 0, 0);
        trade.cancelOrder(1);

        assertEq(store.getLockedMargin(user), 0);

        // fee should be credited back to user
        assertEq(store.getBalance(user), INITIAL_TRADE_DEPOSIT);
    }

    function testExecutableOrderIds() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        // submit three orders:
        // 1. eth long, is executable
        // 2. take profit at 6000 USD
        // 3. stop loss at 4000 USD
        trade.submitOrder(ethLong, 6000 * UNIT, 4000 * UNIT);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);

        uint256[] memory orderIdsToExecute = trade.getExecutableOrderIds();
        assertEq(orderIdsToExecute[0], 1);
        assertEq(orderIdsToExecute.length, 1);

        // set chainlinkprice above TP price
        chainlink.setPrice(ethFeed, 6001 * UNIT);
        orderIdsToExecute = trade.getExecutableOrderIds();

        // initial long order and TP order should be executable
        assertEq(orderIdsToExecute[0], 1);
        assertEq(orderIdsToExecute[1], 2);
        assertEq(orderIdsToExecute.length, 2);

        // set chainlinkprice below SL price
        chainlink.setPrice(ethFeed, 3999 * UNIT);
        orderIdsToExecute = trade.getExecutableOrderIds();

        // initial long order and SL order should be executable
        assertEq(orderIdsToExecute[0], 1);
        assertEq(orderIdsToExecute[1], 3);
        assertEq(orderIdsToExecute.length, 2);
    }

    function testClosePositionWithoutProfit() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);
        // submit order with stop loss 10% below current price and TP 20% above current price
        trade.submitOrder(ethLong, 6000 * UNIT, 4500 * UNIT);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        trade.closePositionWithoutProfit("ETH-USD");

        // user should have margin back
        assertEq(store.getLockedMargin(user), 0);
    }

    function testRevertClosePositionWithoutProfit() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);
        // submit order with stop loss 10% below current price and TP 20% above current price
        trade.submitOrder(ethLong, 6000 * UNIT, 4500 * UNIT);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        // set ETH price below position price
        chainlink.setPrice(ethFeed, 4999 * UNIT);

        // call should revert since position is not in profit
        vm.expectRevert("pnl < 0");
        trade.closePositionWithoutProfit("ETH-USD");
    }

    function testLiquidateUsers() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);
        // submit market long: size 10k, margin 2.5k
        trade.submitOrder(ethLong, 0, 0);
        vm.stopPrank();

        uint256 orderFee = _getOrderFee("ETH-USD", ethLong.size);
        IStore.Order memory order = store.getOrder(1);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        // liquidation when marginLevel < 20%
        // marginLevel = (INITIAL_TRADE_DEPOSIT - fee + P/L) / lockedMargin
        // lockedMargin = 2k; INITIAL_TRADE_DEPOSIT - fee = 4900 USDC
        // -> liquidation when unrealized P/L = -4500 USD -> ETH has to fall below 4775 USD
        chainlink.setPrice(ethFeed, 4775 * UNIT);

        // ETH price is right at liquidation level, user shouldnt get liquidated yet
        address[] memory usersToLiquidate = trade.getLiquidatableUsers();
        assertEq(usersToLiquidate.length, 0);

        chainlink.setPrice(ethFeed, 4774 * UNIT);
        // ETH price is right below liquidation level
        usersToLiquidate = trade.getLiquidatableUsers();
        assertEq(usersToLiquidate[0], user);

        // liquidate user
        vm.prank(user2);
        trade.liquidateUsers();

        // liquidation fee should have been credited to user2
        assertEq(store.getBalance(user2), orderFee * store.keeperFeeShare() / BPS_DIVIDER);

        // user should have lost his margin
        assertEq(store.getLockedMargin(user), 0);

        // and balance should be INITIAL_DEPOSIT - order.fee - order.margin
        assertEq(store.getBalance(user), INITIAL_TRADE_DEPOSIT - orderFee - order.margin);
    }

    function testOpenInterestLong() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);
        // submit market long: size 10k, margin 2.5k
        trade.submitOrder(ethLong, 0, 0);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        assertEq(store.getOILong("ETH-USD"), ethLong.size);

        // open short of same size, closing previous position
        trade.deposit(INITIAL_TRADE_DEPOSIT);
        trade.submitOrder(ethShort, 0, 0);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        assertEq(store.getOILong("ETH-USD"), 0);
    }

    function testOpenInterestShort() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);
        // submit market short: size 10k, margin 2.5k
        trade.submitOrder(ethShort, 0, 0);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        assertEq(store.getOIShort("ETH-USD"), ethShort.size);
    }

    function testAccruedFunding() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);
        // submit market long: size 10k, margin 2.5k
        trade.submitOrder(ethLong, 0, 0);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        // should be zero since no time passed
        assertEq(trade.getAccruedFunding("ETH-USD", 0), 0);

        // fast forward one day -> intervals = 24
        skip(1 days);

        // OI Long should be 10k * 10**18
        assertEq(store.getOILong("ETH-USD"), ethLong.size);

        // accruedFunding = UNIT * yearlyFundingFactor * OIDiff * intervals / (24 * 365 * (OILong + OIShort))
        // accruedFunding = UNIT * 5000 * 10k * CURRENCY_UNIT * 24 / (24 * 365 * 10k * CURRENCY_UNIT)
        // accruedFunding = UNIT * 5000 / 365 = 13698630136986301369 (or 0xbe1b4f87f88773b9 in hex)
        assertEq(trade.getAccruedFunding("ETH-USD", 0), 13698630136986301369);
    }
}
