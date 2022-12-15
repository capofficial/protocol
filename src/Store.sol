// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./CLP.sol";

contract Store {

    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DIVIDER = 10000;

    address public gov;
    address public capContract;
    address public currency;
    address public clp;

    uint256 public poolFeeShare; // in bps
    uint256 public keeperFeeShare; // in bps
    uint256 public poolWithdrawalFee; // in bps

    uint256 public minimumMarginLevel = 2000; // 20% in bps, at which account is liquidated

     // Structs

    struct Market {
        string symbol;
        address feed;
        uint256 maxLeverage;
        uint256 maxOI;
        uint256 fee; // in bps
        uint256 fundingFactor; // Yearly funding rate if OI is completely skewed to one side. In bps.
        uint256 minSize;
        uint256 minSettlementTime; // time before keepers can execute order (price finality) if chainlink price didn't change
    }

    struct Order {
        uint256 orderId;
        address user;
        string market;
        uint256 price;
        bool isLong;
        bool isReduceOnly;
        uint8 orderType; // 0 = market, 1 = limit, 2 = stop
        uint256 margin;
        uint256 size;
        uint256 fee;
        uint256 timestamp;
    }

    struct Position {
        address user;
        string market;
        bool isLong;
        uint256 size;
		uint256 margin;
		int256 fundingTracker;
		uint256 price;
		uint256 timestamp;
    }

    // Variables

    uint256 public orderId;

    uint256 public bufferBalance;
    uint256 public poolBalance;
    uint256 public poolLastPaid;
    uint256 public treasuryBalance;

    uint256 public bufferPayoutPeriod = 7 days;

    mapping(uint256 => Order) private orders;
    mapping(address => EnumerableSet.UintSet) private userOrderIds; // user => [order ids..]
    EnumerableSet.UintSet private orderIds; // [order ids..]

    uint256 public constant MAX_FEE = 1000; // 10%

    string[] public marketList; // "ETH-USD", "BTC-USD", etc
    mapping(string => Market) private markets;

    mapping(bytes32 => Position) private positions; // key = user,market
    EnumerableSet.Bytes32Set private positionKeys; // [position keys..]
	mapping(address => EnumerableSet.Bytes32Set) private positionKeysForUser; // user => [position keys..]

    mapping(string => uint256) private OILong;
    mapping(string => uint256) private OIShort;

    mapping(address => uint256) private balances; // user => amount
    mapping(address => uint256) private lockedMargins; // user => amount
    EnumerableSet.AddressSet private usersWithLockedMargin; // [users...]

    // Funding
	uint256 public constant fundingInterval = 1 hours; // In seconds.

	mapping(string => int256) private fundingTrackers; // market => funding tracker (long) (short is opposite) // in UNIT * bps
	mapping(string => uint256) private fundingLastUpdated; // market => last time fundingTracker was updated. In seconds.

    constructor(address _contract) {
        gov = msg.sender;
        capContract = _contract;
    }

    // Gov methods

    function setPoolFeeShare(uint256 amount) external onlyGov {
        poolFeeShare = amount;
    }

    function setKeeperFeeShare(uint256 amount) external onlyGov {
        keeperFeeShare = amount;
    }

    function setPoolWithdrawalFee(uint256 amount) external onlyGov {
        poolWithdrawalFee = amount;
    }

    function setMinimumMarginLevel(uint256 amount) external onlyGov {
        minimumMarginLevel = amount;
    }

    function setBufferPayoutPeriod(uint256 amount) external onlyGov {
        bufferPayoutPeriod = amount;
    }

    function setMarket(string memory market, Market memory marketInfo) external onlyGov {
		require(marketInfo.fee <= MAX_FEE, "!max-fee");
		markets[market] = marketInfo;
		for (uint256 i = 0; i < marketList.length; i++) {
			if (keccak256(abi.encodePacked(marketList[i])) == keccak256(abi.encodePacked(market))) return;
		}
		marketList.push(market);
	}

    // Methods

    function transferIn(address user, uint256 amount) external onlyContract {
		IERC20(currency).safeTransferFrom(user, address(this), amount);
	}

    function transferOut(address user, uint256 amount) external onlyContract {
        IERC20(currency).safeTransfer(user, amount);
	}

    function getCLPSupply() external view onlyContract returns(uint256) {
        return IERC20(clp).totalSupply();
    }

    function mintCLP(address user, uint256 amount) external onlyContract {
        CLP(clp).mint(user, amount);
    }

    function burnCLP(address user, uint256 amount) external onlyContract {
        CLP(clp).mint(user, amount);
    }

    function incrementBalance(address user, uint256 amount) external onlyContract {
        balances[user] += amount;
    }

    function decrementBalance(address user, uint256 amount) external onlyContract {
        require(amount <= balances[user], "!balance");
        balances[user] -= amount;
    }

    function getBalance(address user) external view returns(uint256) {
        return balances[user];
    }

    function incrementPoolBalance(uint256 amount) external onlyContract {
        poolBalance += amount;
    }

    function decrementPoolBalance(uint256 amount) external onlyContract {
        poolBalance -= amount;
    }

    function getUserPoolBalance(address user) public view returns(uint256) {
        uint256 clpSupply = IERC20(clp).totalSupply();
        if (clpSupply == 0) return 0;
		return IERC20(clp).balanceOf(user) * poolBalance / clpSupply;
	}

    function incrementBufferBalance(uint256 amount) external onlyContract {
        bufferBalance += amount;
    }

    function decrementBufferBalance(uint256 amount) external onlyContract {
        bufferBalance -= amount;
    }

    function setPoolLastPaid(uint256 timestamp) external onlyContract {
        poolLastPaid = timestamp;
    }

    function incrementTreasuryBalance(uint256 amount) external onlyContract {
        treasuryBalance += amount;
    }

    function decrementTreasuryBalance(uint256 amount) external onlyContract {
        treasuryBalance -= amount;
    }

     function lockMargin(address user, uint256 amount) external onlyContract {
        lockedMargins[user] += amount;
        usersWithLockedMargin.add(user);
    }

    function unlockMargin(address user, uint256 amount) external onlyContract {
        if (amount > lockedMargins[user]) {
            lockedMargins[user] = 0;
        } else {
            lockedMargins[user] -= amount;
        }
        if (lockedMargins[user] == 0) {
            usersWithLockedMargin.remove(user);
        }
    }

    function getLockedMargin(address user) external view returns(uint256) {
        return lockedMargins[user];
    }

    function getUsersWithLockedMarginLength() external view returns(uint256) {
        return usersWithLockedMargin.length();
    }

    function getUserWithLockedMargin(uint256 i) external view returns(address) {
        return usersWithLockedMargin.at(i);
    }

    function incrementOI(string memory market, uint256 size, bool isLong) external onlyContract {
        if (isLong) {
            OILong[market] += size;
            require(markets[market].maxOI >= OILong[market], "!max-oi");
        } else {
            OIShort[market] += size;
            require(markets[market].maxOI >= OIShort[market], "!max-oi");
        }
    }

    function decrementOI(string memory market, uint256 size, bool isLong) external onlyContract {
        if (isLong) {
            if (size > OILong[market]) {
                OILong[market] = 0;
            } else {
                OILong[market] -= size;
            }
        } else {
            if (size > OIShort[market]) {
                OIShort[market] = 0;
            } else {
                OIShort[market] -= size;
            }
        }
    }

    function getOILong(string memory market) external view returns(uint256) {
		return OILong[market];
	}

	function getOIShort(string memory market) external view returns(uint256) {
		return OIShort[market];
	}

    function getOrder(uint256 id) external view returns (Order memory _order) {
        return orders[id];
    }

    function addOrder(Order memory order) external onlyContract returns(uint256) {
		uint256 nextOrderId = ++orderId;
        order.orderId = nextOrderId;
		orders[nextOrderId] = order;
		userOrderIds[order.user].add(nextOrderId);
        orderIds.add(nextOrderId);
		return nextOrderId;
	}

    function updateOrder(Order memory order) external onlyContract {
		orders[order.orderId] = order;
	}

    function removeOrder(uint256 _orderId) external onlyContract {
		Order memory order = orders[_orderId];
		if (order.size == 0) return;
		userOrderIds[order.user].remove(_orderId);
        orderIds.remove(orderId);
		delete orders[_orderId];
	}

    function getOrders() external view returns(Order[] memory _orders) {
		uint256 length = orderIds.length();
		_orders = new Order[](length);
		for (uint256 i = 0; i < length; i++) {
			_orders[i] = orders[orderIds.at(i)];
		}
		return _orders;
	}

	function getUserOrders(address user) external view returns(Order[] memory _orders) {
		uint256 length = userOrderIds[user].length();
		_orders = new Order[](length);
		for (uint256 i = 0; i < length; i++) {
			_orders[i] = orders[userOrderIds[user].at(i)];
		}
		return _orders;
	}

    function addOrUpdatePosition(Position memory position) external onlyContract {
		bytes32 key = _getPositionKey(position.user, position.market);
		positions[key] = position;
		positionKeysForUser[position.user].add(key);
		positionKeys.add(key);
	}

    function removePosition(address user, string memory market) external onlyContract {
		bytes32 key = _getPositionKey(user, market);
		positionKeysForUser[user].remove(key);
		positionKeys.remove(key);
		delete positions[key];
	}

    function getPosition(address user, string memory market) public view returns(Position memory position) {
		bytes32 key = _getPositionKey(user, market);
		return positions[key];
	}

    function getUserPositions(address user) external view returns(Position[] memory _positions) {
		uint256 length = positionKeysForUser[user].length();
		_positions = new Position[](length);
		for (uint256 i = 0; i < length; i++) {
			_positions[i] = positions[positionKeysForUser[user].at(i)];
		}
		return _positions;
	}

    function _getPositionKey(address user, string memory market) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, market));
    }

    function getMarket(string memory market) external view returns (Market memory _market) {
        return markets[market];
    }

    function getMarketList() external view returns(string[] memory) {
		return marketList;
	}

    function getFundingLastUpdated(string memory market) external view returns(uint256) {
		return fundingLastUpdated[market];
	}

	function getFundingFactor(string memory market) external view returns(uint256) {
        return markets[market].fundingFactor;
	}

	function getFundingTracker(string memory market) external view returns(int256) {
		return fundingTrackers[market];
	}

    function setFundingLastUpdated(string memory market, uint256 timestamp) external onlyContract {
		fundingLastUpdated[market] = timestamp;
	}

	function updateFundingTracker(string memory market, int256 fundingIncrement) external onlyContract {
		fundingTrackers[market] += fundingIncrement;
	}

    modifier onlyContract() {
        require(msg.sender == capContract, '!contract');
        _;
    }

    modifier onlyGov() {
        require(msg.sender == gov, '!gov');
        _;
    }

}