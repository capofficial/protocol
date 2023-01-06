// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./IStore.sol";

interface ITrade {
    event Deposit(address indexed user, uint256 amount);
    event FundingUpdated(string market, int256 fundingTracker, int256 fundingIncrement);
    event GovernanceUpdated(address indexed oldGov, address indexed newGov);
    event OrderCancelled(uint256 indexed orderId, address indexed user);
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
    event Withdraw(address indexed user, uint256 amount);

    function BPS_DIVIDER() external view returns (uint256);

    function UNIT() external view returns (uint256);

    function cancelOrder(uint256 orderId) external;

    function cancelOrders(uint256[] memory orderIds) external;

    function closePositionWithoutProfit(string memory _market) external;

    function deposit(uint256 amount) external;

    function depositThroughUniswap(address tokenIn, uint256 amountIn, uint256 amountOutMin, uint24 poolFee)
        external
        payable;

    function executeOrders() external;

    function getAccruedFunding(string memory market, uint256 intervals) external view returns (int256);

    function getExecutableOrderIds() external view returns (uint256[] memory orderIdsToExecute);

    function getLiquidatableUsers() external view returns (address[] memory usersToLiquidate);

    function getMarketsWithPrices() external view returns (IStore.Market[] memory _markets, uint256[] memory _prices);

    function getUpl(address user) external view returns (int256 upl);

    function getUserPositionsWithUpls(address user)
        external
        view
        returns (IStore.Position[] memory _positions, int256[] memory _upls);

    function gov() external view returns (address);

    function link(address _chainlink, address _pool, address _store) external;

    function liquidateUsers() external;

    function submitOrder(IStore.Order memory params, uint256 tpPrice, uint256 slPrice) external;

    function updateGov(address _gov) external;

    function updateOrder(uint256 orderId, uint256 price) external;

    function withdraw(uint256 amount) external;
}
