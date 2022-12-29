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

    function BPS_DIVIDER() external view returns (uint256);

    function MAX_FEE() external view returns (uint256);

    function MAX_KEEPER_FEE_SHARE() external view returns (uint256);

    function MAX_POOL_WITHDRAWAL_FEE() external view returns (uint256);

    function addOrUpdatePosition(Position memory position) external;

    function addOrder(Order memory order) external returns (uint256);

    function bufferBalance() external view returns (uint256);

    function bufferPayoutPeriod() external view returns (uint256);

    function burnCLP(address user, uint256 amount) external;

    function clp() external view returns (address);

    function currency() external view returns (address);

    function decrementBalance(address user, uint256 amount) external;

    function decrementBufferBalance(uint256 amount) external;

    function decrementOI(string memory market, uint256 size, bool isLong) external;

    function decrementPoolBalance(uint256 amount) external;

    function fundingInterval() external view returns (uint256);

    function getBalance(address user) external view returns (uint256);

    function getCLPSupply() external view returns (uint256);

    function getEstimatedOutputTokens(uint256 amountIn, address tokenIn, uint24 poolFee)
        external
        returns (uint256 amountOut);

    function getFundingFactor(string memory market) external view returns (uint256);

    function getFundingLastUpdated(string memory market) external view returns (uint256);

    function getFundingTracker(string memory market) external view returns (int256);

    function getLockedMargin(address user) external view returns (uint256);

    function getMarket(string memory market) external view returns (Market memory _market);

    function getMarketList() external view returns (string[] memory);

    function getOILong(string memory market) external view returns (uint256);

    function getOIShort(string memory market) external view returns (uint256);

    function getOrder(uint256 id) external view returns (Order memory _order);

    function getOrders() external view returns (Order[] memory _orders);

    function getPosition(address user, string memory market) external view returns (Position memory position);

    function getUserOrders(address user) external view returns (Order[] memory _orders);

    function getUserPoolBalance(address user) external view returns (uint256);

    function getUserPositions(address user) external view returns (Position[] memory _positions);

    function getUserWithLockedMargin(uint256 i) external view returns (address);

    function getUsersWithLockedMarginLength() external view returns (uint256);

    function gov() external view returns (address);

    function incrementBalance(address user, uint256 amount) external;

    function incrementBufferBalance(uint256 amount) external;

    function incrementOI(string memory market, uint256 size, bool isLong) external;

    function incrementPoolBalance(uint256 amount) external;

    function keeperFeeShare() external view returns (uint256);

    function link(address _trade, address _pool, address _currency, address _clp) external;

    function linkUniswap(address _swapRouter, address _quoter, address _weth) external;

    function lockMargin(address user, uint256 amount) external;

    function marketList(uint256) external view returns (string memory);

    function minimumMarginLevel() external view returns (uint256);

    function mintCLP(address user, uint256 amount) external;

    function pool() external view returns (address);

    function poolBalance() external view returns (uint256);

    function poolFeeShare() external view returns (uint256);

    function poolLastPaid() external view returns (uint256);

    function poolWithdrawalFee() external view returns (uint256);

    function quoter() external view returns (address);

    function removeOrder(uint256 _orderId) external;

    function removePosition(address user, string memory market) external;

    function setBufferPayoutPeriod(uint256 amount) external;

    function setFundingLastUpdated(string memory market, uint256 timestamp) external;

    function setKeeperFeeShare(uint256 amount) external;

    function setMarket(string memory market, Market memory marketInfo) external;

    function setMinimumMarginLevel(uint256 amount) external;

    function setPoolFeeShare(uint256 amount) external;

    function setPoolLastPaid(uint256 timestamp) external;

    function setPoolWithdrawalFee(uint256 amount) external;

    function swapExactInputSingle(address user, uint256 amountIn, uint256 amountOutMin, address tokenIn, uint24 poolFee)
        external
        payable
        returns (uint256 amountOut);

    function swapRouter() external view returns (address);

    function trade() external view returns (address);

    function transferIn(address user, uint256 amount) external;

    function transferOut(address user, uint256 amount) external;

    function unlockMargin(address user, uint256 amount) external;

    function updateFundingTracker(string memory market, int256 fundingIncrement) external;

    function updateGov(address _gov) external;

    function updateOrder(Order memory order) external;

    function weth() external view returns (address);
}
