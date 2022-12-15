// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./Chainlink.sol";
import "./Store.sol";

contract Cap {

    // Stateless, data in Store.sol

    uint256 public constant UNIT = 10**18;
    uint256 public constant BPS_DIVIDER = 10000;


    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    event OrderCreated(
        uint256 indexed orderId,
		address indexed user,
		string market,
		bool isLong,
		uint256 margin,
		uint256 size,
		uint256 price,
		uint256 fee,
		uint8 orderType,
		bool isReduceOnly
    );

    event OrderCancelled(
		uint256 indexed orderId,
		address indexed user
	);

    event PositionIncreased(
        uint256 indexed orderId,
		address indexed user,
		string market,
		bool isLong,
		uint256 size,
		uint256 margin,
		uint256 price,
		uint256 positionMargin,
		uint256 positionSize,
		uint256 positionPrice,
		int256 fundingTracker,
		uint256 fee,
		uint256 keeperFee
	);

	event PositionDecreased(
        uint256 indexed orderId,
		address indexed user,
		string market,
		bool isLong,
		uint256 size,
		uint256 margin,
		uint256 price,
		uint256 positionMargin,
		uint256 positionSize,
		uint256 positionPrice,
		int256 fundingTracker,
		uint256 fee,
        uint256 keeperFee,
		int256 pnl,
		int256 fundingFee
	);

    event AddLiquidity(
        address indexed user, 
        uint256 amount, 
        uint256 clpAmount,
        uint256 poolBalance
    );

    event RemoveLiquidity(
        address indexed user, 
        uint256 amount,  
        uint256 feeAmount,  
        uint256 clpAmount,
        uint256 poolBalance
    );

    event PoolPayIn(
    	address indexed user, 
        string market,
        uint256 amount,
        uint256 bufferToPoolAmount,
        uint256 poolBalance,
        uint256 bufferBalance
    );

    event PoolPayOut(
    	address indexed user,
        string market,
        uint256 amount,
        uint256 poolBalance,
        uint256 bufferBalance
    );

    event FeePaid(
	    address indexed user,
	    string market,
	    uint256 fee,
	    uint256 poolFee,
	    bool isLiquidation
	);

    event PositionLiquidated(
		address indexed user,
		string market,
		bool isLong,
		uint256 size,
		uint256 margin,
		uint256 price,
		uint256 fee,
        uint256 liquidatorFee
	);

    event FundingUpdated(
        string market,
        int256 fundingTracker,
	    int256 fundingIncrement
    );

    // Store

    Chainlink public chainlink;
    Store public store;

    constructor(address _chainlink, address _store) {
		chainlink = Chainlink(_chainlink);
        store = Store(_store);
	}

    // Methods

    /*
    TODO
    OK - all orders including market should execute through keepers (anyone) either after 3min or if chainlink price is different
    OK - trigger orders should execute at the chainlink price, not at their price
    OK - you need to give traders the option to close with no profit, and get their margin back, in case there is nothing / little in the pool
    OK - fee should be flat, no fee adjustments
    - allow submitting TP/SL with an order
    - leave opportunity for deposits from a contract, as a sender, eg depositing ETH and getting funded in USDC directly
    OK - add gov methods to store
    - add MAX_FEE, etc vars in contract to limit gov powers

    the above prevents front running and makes sure chainlink has time to update before executing an order. also prevents scalpers, attracts swing or long term traders. no need for min position holding time.

    => the problem is people won't get the price that's displayed on the screen as entry
    => it is what it is, this is because LPs are passive. It's like uniswap, you don't know exactly, you can get front-run
    */

    function deposit(uint256 amount) external {
        require(amount > 0, "!amount");
        store.transferIn(msg.sender, amount);
        store.incrementBalance(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }
    
    function withdraw(uint256 amount) external {
        require(amount > 0, "!amount");
        address user = msg.sender;
        store.decrementBalance(user, amount);

        // check equity
        int256 upl = getUpl(user);
        uint256 balance = store.getBalance(user); // balance after decrement
        int256 equity = int256(balance) + upl;
        uint256 lockedMargin = store.getLockedMargin(user);

        require(int256(lockedMargin) <= equity, "!equity");

        store.transferOut(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function addLiquidity(uint256 amount) external {
        require(amount > 0, "!amount");
        uint256 balance = store.poolBalance();
        address user = msg.sender;
        store.transferIn(user, amount);

        uint256 clpSupply = store.getCLPSupply();

        uint256 clpAmount = balance == 0 || clpSupply == 0 ? amount : amount * clpSupply / balance;

		store.mintCLP(user, clpAmount);
		store.incrementPoolBalance(amount);

		emit AddLiquidity(
			user,
			amount,
			clpAmount,
			store.poolBalance()
		);

    }

    function removeLiquidity(uint256 amount) external {

        require(amount > 0, "!amount");

		address user = msg.sender;
		uint256 balance = store.poolBalance();
		uint256 clpSupply = store.getCLPSupply();
		require(balance > 0 && clpSupply > 0, "!empty");

		uint256 userBalance = store.getUserPoolBalance(user);
		if (amount > userBalance) amount = userBalance;

		uint256 feeAmount = amount * store.poolWithdrawalFee() / BPS_DIVIDER;
		uint256 amountMinusFee = amount - feeAmount;

		// CLP amount
		uint256 clpAmount = amountMinusFee * clpSupply / balance;

		store.burnCLP(user, clpAmount);
		store.decrementPoolBalance(amountMinusFee);

		store.transferOut(user, amountMinusFee);

		emit RemoveLiquidity(
			user,
			amount,
			feeAmount,
			clpAmount,
			store.poolBalance()
		);

    }

    function submitOrder(Store.Order memory params) external {

        address user = msg.sender;
        
        Store.Market memory market = store.getMarket(params.market);
        require(market.maxLeverage > 0, "!market");
        require(market.minSize <= params.size, "!min-size");

        if (params.isReduceOnly) {
            params.margin = 0;
        } else {
            require(params.margin > 0, "!margin");
            uint256 leverage = UNIT * params.size / params.margin;
            require(leverage >= UNIT, "!min-leverage");
            require(leverage <= market.maxLeverage * UNIT, "!max-leverage");

            store.lockMargin(user, params.margin);
            
        }

        // check equity
        int256 upl = getUpl(user);
        uint256 balance = store.getBalance(user);
        int256 equity = int256(balance) + upl;
        uint256 lockedMargin = store.getLockedMargin(user);

        require(int256(lockedMargin) <= equity, "!equity");

        // fee
        uint256 fee = market.fee * params.size / BPS_DIVIDER;
        store.decrementBalance(user, fee);

        // Get chainlink price
        uint256 chainlinkPrice = chainlink.getPrice(market.feed);
        require(chainlinkPrice > 0, "!chainlink");

        // Check chainlink price vs order price for trigger orders
        if (
            params.orderType == 1 && params.isLong && chainlinkPrice <= params.price ||
            params.orderType == 1 && !params.isLong && chainlinkPrice >= params.price ||
            params.orderType == 2 && params.isLong && chainlinkPrice >= params.price ||
            params.orderType == 2 && !params.isLong && chainlinkPrice <= params.price
        ) {
            revert("!orderType");
        }

        // Assign current chainlink price to market orders
        if (params.orderType == 0) {
            params.price = chainlinkPrice; 
        }

        // Save order to store
        params.user = user;
		params.fee = fee;
		params.timestamp = block.timestamp;

        uint256 orderId = store.addOrder(params);
        emit OrderCreated(
            orderId,
            params.user,
            params.market,
            params.isLong,
            params.margin,
            params.size,
            params.price,
            params.fee,
            params.orderType,
            params.isReduceOnly
        );

    }

    function updateOrder(uint256 orderId, uint256 price) external {
        Store.Order memory order = store.getOrder(orderId);
        require(order.user == msg.sender, "!user");
        require(order.size > 0, "!order");
        require(order.orderType != 0, "!market-order");
        Store.Market memory market = store.getMarket(order.market);
        uint256 chainlinkPrice = chainlink.getPrice(market.feed);
        require(chainlinkPrice > 0, "!chainlink");
        if (
            order.orderType == 1 && order.isLong && chainlinkPrice <= price ||
            order.orderType == 1 && !order.isLong && chainlinkPrice >= price ||
            order.orderType == 2 && order.isLong && chainlinkPrice >= price ||
            order.orderType == 2 && !order.isLong && chainlinkPrice <= price
        ) {
            if (order.orderType == 1) order.orderType = 2;
            if (order.orderType == 2) order.orderType = 1;
        }
        order.price = price;
        store.updateOrder(order);
    }

    function cancelOrder(uint256 orderId) public {
        Store.Order memory order = store.getOrder(orderId);
        require(order.user == msg.sender, "!user");
        require(order.size > 0, "!order");
        require(order.orderType != 0, "!market-order");
        if (!order.isReduceOnly) {
            store.unlockMargin(order.user, order.margin);
        }
        store.incrementBalance(order.user, order.fee);
        store.transferOut(order.user, order.margin + order.fee);
        store.removeOrder(orderId);
        emit OrderCancelled(
			orderId, 
			order.user
		);
    }

    function cancelOrders(uint256[] calldata orderIds) external {
        for (uint256 i = 0; i < orderIds.length; i++) {
            cancelOrder(orderIds[i]);
        }
    }

    function getExecutableOrderIds() public view returns(uint256[] memory orderIdsToExecute){

        Store.Order[] memory orders = store.getOrders();
        uint256[] memory _orderIds = new uint256[](orders.length);
        uint256 j;
        for (uint256 i = 0; i < orders.length; i++) {

            Store.Order memory order = orders[i];
            Store.Market memory market = store.getMarket(order.market);

            uint256 chainlinkPrice = chainlink.getPrice(market.feed);
            if (chainlinkPrice == 0) continue;

            // Can this order be executed?
            if (
                order.orderType == 0 ||
                order.orderType == 1 && order.isLong && chainlinkPrice <= order.price ||
                order.orderType == 1 && !order.isLong && chainlinkPrice >= order.price ||
                order.orderType == 2 && order.isLong && chainlinkPrice >= order.price ||
                order.orderType == 2 && !order.isLong && chainlinkPrice <= order.price
            ) {
                // Check settlement time has passed, or chainlinkPrice is different for market order
                if (order.orderType == 0 && chainlinkPrice != order.price || block.timestamp - order.timestamp > market.minSettlementTime) {
                    _orderIds[j] = order.orderId;
                    j++;
                }
            }

        }

        // Return trimmed result containing only executable order ids
        orderIdsToExecute = new uint256[](j);
        for (uint256 i = 0; i < j; i++) {
            orderIdsToExecute[i] = _orderIds[i];
        }

        return orderIdsToExecute;

    }

    function executeOrders() external {
        uint256[] memory orderIds = getExecutableOrderIds();
		for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 orderId = orderIds[i];
            Store.Order memory order = store.getOrder(orderId);
            if (order.size == 0 || order.price == 0) continue;
            Store.Market memory market = store.getMarket(order.market);
            uint256 chainlinkPrice = chainlink.getPrice(market.feed);
            if (chainlinkPrice == 0) continue;
            _executeOrder(order, chainlinkPrice, msg.sender);
        }
    }

    function _executeOrder(Store.Order memory order, uint256 price, address keeper) internal {

        // Check for existing position
        Store.Position memory position = store.getPosition(order.user, order.market);

        bool doAdd = !order.isReduceOnly && (position.size == 0 || order.isLong == position.isLong);
		bool doReduce = position.size > 0 && order.isLong != position.isLong;

        if (doAdd) {
            _increasePosition(order, price, keeper);
        } else if (doReduce) {
            _decreasePosition(order, price, keeper);
        }

    }

    function _increasePosition(Store.Order memory order, uint256 price, address keeper) internal {
        
        Store.Position memory position = store.getPosition(order.user, order.market);

        uint256 fee = order.fee;
        uint256 keeperFee = fee * store.keeperFeeShare() / BPS_DIVIDER;
        fee -= keeperFee;

        _creditFee(order.user, order.market, fee, false);

        store.transferOut(keeper, keeperFee);

        store.incrementOI(order.market, order.size, order.isLong);

        _updateFundingTracker(order.market);

        uint256 averagePrice = (position.size * position.price + order.size * price) / (position.size + order.size);

		if (position.size == 0) {
			position.user = order.user;
			position.market = order.market;
			position.timestamp = block.timestamp;
			position.isLong = order.isLong;
			position.fundingTracker = store.getFundingTracker(order.market);
		}

        position.size += order.size;
		position.margin += order.margin;
		position.price = averagePrice;

        store.addOrUpdatePosition(position);

        if (order.orderId > 0) {
            store.removeOrder(order.orderId);
        }

        emit PositionIncreased(
            order.orderId,
			order.user,
			order.market,
			order.isLong,
			order.size,
			order.margin,
			price,
			position.margin,
			position.size,
			position.price,
			position.fundingTracker,
            fee,
            keeperFee
		);

    }

    function _decreasePosition(Store.Order memory order, uint256 price, address keeper) internal {

        Store.Position memory position = store.getPosition(order.user, order.market);

		uint256 executedOrderSize = position.size > order.size ? order.size : position.size;
		uint256 remainingOrderSize = order.size - executedOrderSize;

		uint256 remainingOrderMargin;
		uint256 amountToReturnToUser;

		if (order.isReduceOnly) {
			// order.margin = 0
			// A fee (order.fee) corresponding to order.size was taken from balance on submit. Only fee corresponding to executedOrderSize should be charged, rest should be returned, if any
            store.incrementBalance(order.user, order.fee * remainingOrderSize / order.size);
		} else {
			// User submitted order.margin when sending the order. Refund the portion of order.margin that executes against the position
			uint256 executedOrderMargin = order.margin * executedOrderSize / order.size;
			amountToReturnToUser += executedOrderMargin;
			remainingOrderMargin = order.margin - executedOrderMargin;
		}

        uint256 fee = order.fee;
        uint256 keeperFee = fee * store.keeperFeeShare() / BPS_DIVIDER;
        fee -= keeperFee;

        _creditFee(order.user, order.market, fee, false);

        store.transferOut(keeper, keeperFee);

		// Funding update

		store.decrementOI(order.market, order.size, position.isLong);
		
        _updateFundingTracker(order.market);

		// P/L

		(int256 pnl, int256 fundingFee) = _getPnL(
			order.market, 
			position.isLong, 
			price, 
			position.price, 
			executedOrderSize, 
			position.fundingTracker
		);

		uint256 executedPositionMargin = position.margin * executedOrderSize / position.size;

		if (pnl <= -1 * int256(position.margin)) {
			pnl = -1 * int256(position.margin);
			executedPositionMargin = position.margin;
			executedOrderSize = position.size;
			position.size = 0;
		} else {
			position.margin -= executedPositionMargin;
			position.size -= executedOrderSize;
			position.fundingTracker = store.getFundingTracker(order.market);
		}

		if (pnl < 0) {
			uint256 absPnl = uint256(-1 * pnl);

            // credit trader loss to pool
			_creditTraderLoss(order.user, order.market, absPnl);

			if (absPnl < executedPositionMargin) {
				amountToReturnToUser += executedPositionMargin - absPnl;
			}

		} else {	
			_debitTraderProfit(order.user, order.market, uint256(pnl));
			amountToReturnToUser += executedPositionMargin;
		}

        store.unlockMargin(order.user, amountToReturnToUser);

		if (position.size == 0) {
			store.removePosition(order.user, order.market);
		} else {
			store.addOrUpdatePosition(position);
		}

		store.removeOrder(order.orderId);

		emit PositionDecreased(
			order.orderId,
			order.user,
			order.market,
			order.isLong,
			executedOrderSize,
			executedPositionMargin,
			price,
			position.margin,
			position.size,
			position.price,
			position.fundingTracker,
			fee,
            keeperFee,
			pnl,
			fundingFee
		);

		// Open position in opposite direction if size remains

		if (!order.isReduceOnly && remainingOrderSize > 0) {

			Store.Order memory nextOrder = Store.Order({
				orderId: 0,
				user: order.user,
				market: order.market,
				margin: remainingOrderMargin,
				size: remainingOrderSize,
				price: 0,
				isLong: order.isLong,
                orderType: 0,
				fee: order.fee * remainingOrderSize / order.size,
				isReduceOnly: false,
				timestamp: block.timestamp
			});

			_increasePosition(nextOrder, price, keeper);

		}

    }

    function closePositionWithoutProfit(string memory _market) external {

        address user = msg.sender;

        Store.Position memory position = store.getPosition(user, _market);
        require(position.size > 0, "!position");

        Store.Market memory market = store.getMarket(_market);

        uint256 fee = position.size * market.fee / BPS_DIVIDER;

        _creditFee(user, _market, fee, false);

		store.decrementOI(_market, position.size, position.isLong);
		
        _updateFundingTracker(_market);

        uint256 chainlinkPrice = chainlink.getPrice(market.feed);
        require(chainlinkPrice > 0, "!price");

		// P/L

		(int256 pnl, ) = _getPnL(
			_market, 
			position.isLong, 
			chainlinkPrice, 
			position.price, 
			position.size, 
			position.fundingTracker
		);

        // Only profitable positions can be closed this way
        require(pnl >= 0, "!pnl");

        store.unlockMargin(user, position.margin);
        store.removePosition(user, _market);

		emit PositionDecreased(
			0,
			user,
			_market,
			!position.isLong,
			position.size,
			position.margin,
			chainlinkPrice,
			position.margin,
			position.size,
			position.price,
			position.fundingTracker,
			fee,
            0,
			0,
			0
		);

    }

    function getLiquidatableUsers() public view returns(address[] memory usersToLiquidate) {
        uint256 length = store.getUsersWithLockedMarginLength();
        address[] memory _users = new address[](length);
        uint256 j = 0;
        for (uint256 i = 0; i < length; i++) {
            address user = store.getUserWithLockedMargin(i);
            int256 equity = int256(store.getBalance(user)) + getUpl(user);
            uint256 lockedMargin = store.getLockedMargin(user);
            uint256 marginLevel;
            if (equity <= 0) {
                marginLevel = 0;
            } else {
                marginLevel = BPS_DIVIDER * uint256(equity) / lockedMargin;
            }
            if (marginLevel < store.minimumMarginLevel()) {
                _users[j] = user;
                j++;
            }
		}
        // Return trimmed result containing only users to be liquidated
        usersToLiquidate = new address[](j);
        for (uint256 i = 0; i < j; i++) {
            usersToLiquidate[i] = _users[i];
        }
        return usersToLiquidate;
    }

    function liquidateUsers() external {

        address[] memory usersToLiquidate = getLiquidatableUsers();
        uint256 liquidatorFees;

        for (uint256 i = 0; i < usersToLiquidate.length; i++) {
            address user = usersToLiquidate[i];
            Store.Position[] memory positions = store.getUserPositions(user);
            for (uint256 j = 0; j < positions.length; j++) {

                Store.Position memory position = positions[j];
                Store.Market memory market = store.getMarket(position.market);

                uint256 fee = position.size * market.fee / BPS_DIVIDER;
                uint256 liquidatorFee = fee * store.keeperFeeShare() / BPS_DIVIDER;
                fee -= liquidatorFee;
                liquidatorFees += liquidatorFee;

                _creditTraderLoss(user, position.market, position.margin - fee - liquidatorFee);
                _creditFee(user, position.market, fee, true);
                store.decrementOI(position.market, position.size, position.isLong);
                _updateFundingTracker(position.market);
                store.removePosition(user, position.market);

                store.unlockMargin(user, position.margin);

                uint256 chainlinkPrice = chainlink.getPrice(market.feed);

                emit PositionLiquidated(
                    user,
                    position.market,
                    position.isLong,
                    position.size,
                    position.margin,
                    chainlinkPrice,
                    fee,
                    liquidatorFee
                );

		    }
        }

        // credit liquidator fees
        store.transferOut(msg.sender, liquidatorFees);

    }

    function getUserPositionsWithUpls(address user) external view returns(Store.Position[] memory _positions, int256[] memory _upls) {
        _positions = store.getUserPositions(user);
        uint256 length = _positions.length;
        _upls = new int256[](length);
        for (uint256 i = 0; i < length; i++) {
            Store.Position memory position = _positions[i];

            Store.Market memory market = store.getMarket(position.market);

            uint256 chainlinkPrice = chainlink.getPrice(market.feed);
            if (chainlinkPrice == 0) continue;

            (int256 pnl, ) = _getPnL(
                position.market, 
                position.isLong, 
                chainlinkPrice, 
                position.price, 
                position.size, 
                position.fundingTracker
            );

            _upls[i] = pnl;

        }

        return (_positions, _upls);

    }
    
    function getMarketsWithPrices() external view returns(Store.Market[] memory _markets, uint256[] memory _prices) {
        
        string[] memory marketList = store.getMarketList();
        uint256 length = marketList.length;
        _markets = new Store.Market[](length);
        _prices = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            Store.Market memory market = store.getMarket(marketList[i]);
            uint256 chainlinkPrice = chainlink.getPrice(market.feed);
            _markets[i] = market;
            _prices[i] = chainlinkPrice;
        }

        return (_markets, _prices);

    }

    function _getPnL(
		string memory market,
		bool isLong,
		uint256 price,
		uint256 positionPrice,
		uint256 size,
		int256 fundingTracker
	) internal view returns(int256 pnl, int256 fundingFee) {

		if (price == 0 || positionPrice == 0 || size == 0) return (0,0);

		if (isLong) {
			pnl = int256(size) * (int256(price) - int256(positionPrice)) / int256(positionPrice);
		} else {
			pnl = int256(size) * (int256(positionPrice) - int256(price)) / int256(positionPrice);
		}

		int256 currentFundingTracker = store.getFundingTracker(market);
		fundingFee = int256(size) * (currentFundingTracker - fundingTracker) / (int256(BPS_DIVIDER) * int256(UNIT)); // funding tracker is in UNIT * bps

		if (isLong) {
			pnl -= fundingFee; // positive = longs pay, negative = longs receive
		} else {
			pnl += fundingFee; // positive = shorts receive, negative = shorts pay
		}

		return (pnl, fundingFee);

	}

    function getUpl(address user) public view returns(int256 upl) {

        Store.Position[] memory positions = store.getUserPositions(user);
        for (uint256 j = 0; j < positions.length; j++) {

            Store.Position memory position = positions[j];
            Store.Market memory market = store.getMarket(position.market);

            uint256 chainlinkPrice = chainlink.getPrice(market.feed);
            if (chainlinkPrice == 0) continue;

            (int256 pnl, ) = _getPnL(
                position.market, 
                position.isLong, 
                chainlinkPrice, 
                position.price, 
                position.size, 
                position.fundingTracker
            );

            upl += pnl;

        }

        return upl;

    }

    function _updateFundingTracker(string memory market) internal {

        uint256 lastUpdated = store.getFundingLastUpdated(market);
		uint256 _now = block.timestamp;
		
		if (lastUpdated == 0) {
	    	store.setFundingLastUpdated(market, _now);
	    	return;
	    }

		if (lastUpdated + store.fundingInterval() > _now) return;
	    
	    int256 fundingIncrement = getAccruedFunding(market, 0); // in UNIT * bps

	    if (fundingIncrement == 0) return;
    	
    	store.updateFundingTracker(market, fundingIncrement);
    	store.setFundingLastUpdated(market, _now);
	    
	    emit FundingUpdated(
	    	market,
	    	store.getFundingTracker(market),
	    	fundingIncrement
	    );

    }

    function getAccruedFunding(string memory market, uint256 intervals) public view returns (int256) {

        if (intervals == 0) {
			intervals = (block.timestamp - store.getFundingLastUpdated(market)) / store.fundingInterval();
		}
		
		if (intervals == 0) return 0;
	    
	    uint256 OILong = store.getOILong(market);
	    uint256 OIShort = store.getOIShort(market);
	    
	    if (OIShort == 0 && OILong == 0) return 0;

	    uint256 OIDiff = OIShort > OILong ? OIShort - OILong : OILong - OIShort;
        uint256 yearlyFundingFactor = store.getFundingFactor(market); // in bps
        // intervals = hours since fundingInterval = 1 hour
	    uint256 accruedFunding = UNIT * yearlyFundingFactor * OIDiff * intervals / (24 * 365 * (OILong + OIShort)); // in UNIT * bps

	    if (OILong > OIShort) {
	    	// Longs pay shorts. Increase funding tracker.
	    	return int256(accruedFunding);
	    } else {
	    	// Shorts pay longs. Decrease funding tracker.
	    	return -1 * int256(accruedFunding);
	    }

    }

    function _creditTraderLoss(
		address user,  
		string memory market,
		uint256 amount
	) internal {
		
		store.incrementBufferBalance(amount);

		uint256 lastPaid = store.poolLastPaid();
		uint256 _now = block.timestamp;

		if (lastPaid == 0) {
			store.setPoolLastPaid(_now);
			return;
		}

		uint256 bufferBalance = store.bufferBalance();
		uint256 bufferPayoutPeriod = store.bufferPayoutPeriod();

		uint256 amountToSendPool = bufferBalance * (block.timestamp - lastPaid) / bufferPayoutPeriod;
		
		if (amountToSendPool > bufferBalance) amountToSendPool = bufferBalance;
		
		store.incrementPoolBalance(amountToSendPool);
		store.decrementBufferBalance(amountToSendPool);
		store.setPoolLastPaid(_now);

        store.decrementBalance(user, amount);

		emit PoolPayIn(
			user,
			market,
			amount,
			amountToSendPool,
			store.poolBalance(),
			store.bufferBalance()
		);

	}

    function _debitTraderProfit(
		address user, 
		string memory market,
		uint256 amount
	) internal {

		if (amount == 0) return;
		
		uint256 bufferBalance = store.bufferBalance();

		store.decrementBufferBalance(amount);

		if (amount > bufferBalance) {
			uint256 diffToPayFromPool = amount - bufferBalance;
			uint256 poolBalance = store.poolBalance();
			require(diffToPayFromPool < poolBalance, "!pool-balance");
			store.decrementPoolBalance(diffToPayFromPool);
		}

        store.incrementBalance(user, amount);
		
		emit PoolPayOut(
			user,
			market,
			amount,
			store.poolBalance(),
			store.bufferBalance()
		);

	}

    function _creditFee(
		address user,
		string memory market,
		uint256 fee,
		bool isLiquidation
    ) internal {

		if (fee == 0) return;

		uint256 poolFee = fee * store.poolFeeShare() / BPS_DIVIDER;
		uint256 treasuryFee = fee - poolFee;

		store.incrementPoolBalance(poolFee);
		store.incrementTreasuryBalance(treasuryFee);

		emit FeePaid(
			user, 
			market,
			fee, // paid by user
			poolFee,
			isLiquidation
		);

    }
    
}
