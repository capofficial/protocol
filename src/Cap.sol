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
		bool isStop,
		bool isReduceOnly
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
		uint256 fee
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
		int256 pnl,
		int256 fundingFee
	);

    event PoolDeposit(
        address indexed user, 
        uint256 amount, 
        uint256 clpAmount,
        uint256 poolBalance
    );

    event PoolWithdrawal(
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

    constructor(Chainlink _chainlink, Store _store) {
		chainlink = _chainlink;
        store = _store;
	}

    // Methods

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
        int256 upl = _getUpl(user);
        uint256 balance = store.getBalance(user); // balance after decrement
        int256 equity = int256(balance) + upl;
        uint256 lockedMargin = store.getLockedMargin(user);

        require(int256(lockedMargin) <= equity, "!equity");

        store.transferOut(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    // todo: depositPool
    // todo: withdrawPool

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
        int256 upl = _getUpl(user);
        uint256 balance = store.getBalance(user);
        int256 equity = int256(balance) + upl;
        uint256 lockedMargin = store.getLockedMargin(user);

        require(int256(lockedMargin) <= equity, "!equity");

        // fee
        (uint256 longFee, uint256 shortFee) = store.getMarketFee(params.market, params.isReduceOnly);
        uint256 fee = (params.isLong ? longFee : shortFee) * params.size / BPS_DIVIDER;
        store.decrementBalance(user, fee);

        // Get chainlink price
        uint256 chainlinkPrice = chainlink.getPrice(market.feed);
        require(chainlinkPrice > 0, "!chainlink");

        // Check chainlink price vs order price
        if (params.price > 0) {
            // If trigger order price is beyond chainlink price, set it to 0 (market order)
            if (
                !params.isStop && params.isLong && chainlinkPrice <= params.price ||
                !params.isStop && !params.isLong && chainlinkPrice >= params.price ||
                params.isStop && params.isLong && chainlinkPrice >= params.price ||
                params.isStop && !params.isLong && chainlinkPrice <= params.price
            ) {
                params.price = 0;
            }
        }

        // Save order to store

        params.user = user;
		params.fee = fee;
		params.timestamp = block.timestamp;

        if (params.price == 0) {
            _executeOrder(params, chainlinkPrice);
        } else {
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
                params.isStop,
                params.isReduceOnly
            );
        }

    }

    function updateOrder() external {

    }

    function cancelOrder() external {

    }

    function getExecutableOrders() external {

    }

    function executeOrders(uint256[] calldata orderIds) external {
        uint256 length = orderIds.length;
		for (uint256 i = 0; i < length; i++) {
            uint256 orderId = orderIds[i];
            Store.Order memory order = store.getOrder(orderId);
            if (order.size == 0 || order.price == 0) continue;
            Store.Market memory market = store.getMarket(order.market);
            uint256 chainlinkPrice = chainlink.getPrice(market.feed);
            if (chainlinkPrice == 0) continue;
            _executeOrder(order, chainlinkPrice);
        }
    }

    function _executeOrder(Store.Order memory order, uint256 price) internal {

        // Check for existing position
        Store.Position memory position = store.getPosition(order.user, order.market);

        bool doAdd = !order.isReduceOnly && (position.size == 0 || order.isLong == position.isLong);
		bool doReduce = position.size > 0 && order.isLong != position.isLong;

        if (doAdd) {
            _increasePosition(order, price);
        } else if (doReduce) {
            _decreasePosition(order, price);
        }

    }

    function _increasePosition(Store.Order memory order, uint256 price) internal {
        
        Store.Position memory position = store.getPosition(order.user, order.market);

        _creditFee(order.user, order.market, order.fee, false);

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
            order.fee
		);

    }

    function _decreasePosition(Store.Order memory order, uint256 price) internal {

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

        _creditFee(order.user, order.market, order.fee, false);

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
			order.fee,
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
                isStop: false,
				fee: order.fee * remainingOrderSize / order.size,
				isReduceOnly: false,
				timestamp: block.timestamp
			});

			_increasePosition(nextOrder, price);

		}

    }

    function getLiquidatableUsers() public view returns(address[] memory usersToLiquidate) {
        uint256 length = store.getUsersWithLockedMarginLength();
        address[] memory _users = new address[](length);
        uint256 j = 0;
        for (uint256 i = 0; i < length; i++) {
            address user = store.getUserWithLockedMargin(i);
            int256 equity = int256(store.getBalance(user)) + _getUpl(user);
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
        // Retrun trimmed result containing only users to be liquidated
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

                uint256 fee = position.size * market.baseFee / BPS_DIVIDER;
                uint256 liquidatorFee = fee * store.liquidatorFeeShare() / BPS_DIVIDER;
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

     function _getUpl(address user) internal view returns(int256 upl) {

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
