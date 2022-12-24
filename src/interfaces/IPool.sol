// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IPool {
    // Events

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

    function link(address _trade, address _store) external;

    function addLiquidity(uint256 amount) external;

    function removeLiquidity(uint256 amount) external;

    function creditTraderLoss(
        address user,
        string memory market,
        uint256 amount
    ) external;

    function debitTraderProfit(
        address user,
        string memory market,
        uint256 amount
    ) external;

    function creditFee(
        address user,
        string memory market,
        uint256 fee,
        bool isLiquidation
    ) external;
}
