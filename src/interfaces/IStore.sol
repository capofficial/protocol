// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IStore {
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
        bool isLong;
        bool isReduceOnly;
        uint8 orderType; // 0 = market, 1 = limit, 2 = stop
        string market;
        uint256 price;
        uint256 margin;
        uint256 size;
        uint256 fee;
        uint256 timestamp;
    }

    struct Position {
        address user;
        bool isLong;
        string market;
        uint256 size;
        uint256 margin;
        int256 fundingTracker;
        uint256 price;
        uint256 timestamp;
    }

    function link(
        address _trade,
        address _pool,
        address _currency,
        address _clp
    ) external;

    // Gov methods

    function setTreasuryAddress(address payable _treasuryAddress) external;

    function setPoolFeeShare(uint256 amount) external;

    function setKeeperFeeShare(uint256 amount) external;

    function setPoolWithdrawalFee(uint256 amount) external;

    function setMinimumMarginLevel(uint256 amount) external;

    function setBufferPayoutPeriod(uint256 amount) external;

    function setMarket(string memory market, Market memory marketInfo) external;

    // Methods

    function transferIn(address user, uint256 amount) external;

    function transferOut(address user, uint256 amount) external;

    function getCLPSupply() external view returns (uint256);

    function mintCLP(address user, uint256 amount) external;

    function burnCLP(address user, uint256 amount) external;

    function payTreasuryFee(uint256 amount) external;

    function incrementBalance(address user, uint256 amount) external;

    function decrementBalance(address user, uint256 amount) external;

    function getBalance(address user) external view returns (uint256);

    function incrementPoolBalance(uint256 amount) external;

    function decrementPoolBalance(uint256 amount) external;

    function getUserPoolBalance(address user) external view returns (uint256);

    function incrementBufferBalance(uint256 amount) external;

    function decrementBufferBalance(uint256 amount) external;

    function setPoolLastPaid(uint256 timestamp) external;

    function lockMargin(address user, uint256 amount) external;

    function unlockMargin(address user, uint256 amount) external;

    function getLockedMargin(address user) external view returns (uint256);

    function getUsersWithLockedMarginLength() external view returns (uint256);

    function getUserWithLockedMargin(uint256 i) external view returns (address);

    function incrementOI(
        string memory market,
        uint256 size,
        bool isLong
    ) external;

    function decrementOI(
        string memory market,
        uint256 size,
        bool isLong
    ) external;

    function getOILong(string memory market) external view returns (uint256);

    function getOIShort(string memory market) external view returns (uint256);

    function getOrder(uint256 id) external view returns (Order memory _order);

    function addOrder(Order memory order) external returns (uint256);

    function updateOrder(Order memory order) external;

    function removeOrder(uint256 _orderId) external;

    function getOrders() external view returns (Order[] memory _orders);

    function getUserOrders(address user)
        external
        view
        returns (Order[] memory _orders);

    function addOrUpdatePosition(Position memory position) external;

    function removePosition(address user, string memory market) external;

    function getPosition(address user, string memory market)
        external
        view
        returns (Position memory position);

    function getUserPositions(address user)
        external
        view
        returns (Position[] memory _positions);

    function getMarket(string memory market)
        external
        view
        returns (Market memory _market);

    function getMarketList() external view returns (string[] memory);

    function getFundingLastUpdated(string memory market)
        external
        view
        returns (uint256);

    function getFundingFactor(string memory market)
        external
        view
        returns (uint256);

    function getFundingTracker(string memory market)
        external
        view
        returns (int256);

    function setFundingLastUpdated(string memory market, uint256 timestamp)
        external;

    function updateFundingTracker(string memory market, int256 fundingIncrement)
        external;

    function getPoolBalance() external view returns (uint256);

    function getPoolWithdrawalFee() external view returns (uint256);

    function getPoolLastPaid() external view returns (uint256);

    function getBufferBalance() external view returns (uint256);

    function getBufferPayoutPeriod() external view returns (uint256);

    function getPoolFeeShare() external view returns (uint256);

    function getKeeperFeeShare() external view returns (uint256);

    function getMinimumMarginLevel() external view returns (uint256);

    function getFundingInterval() external view returns (uint256);
}
