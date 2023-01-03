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
        trade.submitOrder(ethLong, 0, 4500);

        // console.log orders and positions? true = yes, false = no
        bool flag = false;

        // should be two orders: ETH long and SL
        assertEq(_printOrders(flag), 2, "!orderCount");
        assertEq(_printUserPositions(user, flag), 0, "!positionCount");

        console.log("-------------------------------");
        console.log();

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        // should be one SL order and one long position
        assertEq(_printOrders(flag), 1, "!orderCount");
        assertEq(_printUserPositions(user, flag), 1, "!positionCount");

        console.log("-------------------------------");

        // set ETH price to SL price and execute SL order
        chainlink.setPrice(ethFeed, 4500);
        trade.executeOrders();

        // should be zero orders, zero positions
        assertEq(_printOrders(flag), 0, "!orderCount");
        assertEq(_printUserPositions(user, flag), 0, "!positionCount");
    }

    function testExceedFreeMargin() public {
        // deposit 5000 USDC for trading
        trade.deposit(INITIAL_TRADE_DEPOSIT);

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
        trade.submitOrder(ethLong, 0, 0);

        // locked margin = 2500 USDC, orderfee = 100 USDC => withdrawing more than 2400 USDC shouldnt work
        vm.expectRevert("!equity");
        trade.withdraw(2401 * CURRENCY_UNIT);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        // set eth price above 5k USD so trade is in profit
        chainlink.setPrice(ethFeed, 5100);

        // withdrawing should work
        vm.expectEmit(true, true, true, true);
        emit Withdraw(user, 2501 * CURRENCY_UNIT);
        trade.withdraw(2501 * CURRENCY_UNIT);
    }

    function testRevertOrderType() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        ethLongLimit.price = 6000;
        // orderType == 1 && isLong == true && chainLinkPrice <= order.price, should revert
        vm.expectRevert("!orderType");
        trade.submitOrder(ethLongLimit, 0, 0);
    }

    function testUpdateOrder() public {
        trade.deposit(INITIAL_TRADE_DEPOSIT);

        trade.submitOrder(ethLongLimit, 0, 0);

        // update order
        trade.updateOrder(1, 6000);
        IStore.Order[] memory _orders = store.getOrders();

        // order type from 1 => 2
        assertEq(_orders[0].orderType, 2);
        // price should be 6000
        assertEq(_orders[0].price, 6000);
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

        // console.log orders and positions? true = yes, false = no
        bool flag = false;

        trade.submitOrder(ethLong, 4000, 7000);
        _printOrders(flag);

        // minSettlementTime is 1 minutes -> fast forward 2 minutes
        skip(2 minutes);
        trade.executeOrders();

        _printOrders(flag);
        _printUserPositions(user, flag);
    }
}
