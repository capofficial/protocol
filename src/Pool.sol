// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./interfaces/IStore.sol";

contract Pool {
    uint256 public constant UNIT = 10**18;
    uint256 public constant BPS_DIVIDER = 10000;

    address public gov;
    address public trade;
    IStore public store;

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

    // Methods

    constructor() {
        gov = msg.sender;
    }

    function link(address _trade, address _store) external onlyGov {
        trade = _trade;
        store = IStore(_store);
    }

    function addLiquidity(uint256 amount) external {
        require(amount > 0, "!amount");
        uint256 balance = store.getPoolBalance();
        address user = msg.sender;
        store.transferIn(user, amount);

        uint256 clpSupply = store.getCLPSupply();

        uint256 clpAmount = balance == 0 || clpSupply == 0
            ? amount
            : (amount * clpSupply) / balance;

        store.mintCLP(user, clpAmount);
        store.incrementPoolBalance(amount);

        emit AddLiquidity(user, amount, clpAmount, store.getPoolBalance());
    }

    function removeLiquidity(uint256 amount) external {
        require(amount > 0, "!amount");

        address user = msg.sender;
        uint256 balance = store.getPoolBalance();
        uint256 clpSupply = store.getCLPSupply();
        require(balance > 0 && clpSupply > 0, "!empty");

        uint256 userBalance = store.getUserPoolBalance(user);
        if (amount > userBalance) amount = userBalance;

        uint256 feeAmount = (amount * store.getPoolWithdrawalFee()) /
            BPS_DIVIDER;
        uint256 amountMinusFee = amount - feeAmount;

        // CLP amount
        uint256 clpAmount = (amountMinusFee * clpSupply) / balance;

        store.burnCLP(user, clpAmount);
        store.decrementPoolBalance(amountMinusFee);

        store.transferOut(user, amountMinusFee);

        emit RemoveLiquidity(
            user,
            amount,
            feeAmount,
            clpAmount,
            store.getPoolBalance()
        );
    }

    function creditTraderLoss(
        address user,
        string memory market,
        uint256 amount
    ) external onlyTrade {
        store.incrementBufferBalance(amount);

        uint256 lastPaid = store.getPoolLastPaid();
        uint256 _now = block.timestamp;

        if (lastPaid == 0) {
            store.setPoolLastPaid(_now);
            return;
        }

        uint256 bufferBalance = store.getBufferBalance();
        uint256 bufferPayoutPeriod = store.getBufferPayoutPeriod();

        uint256 amountToSendPool = (bufferBalance *
            (block.timestamp - lastPaid)) / bufferPayoutPeriod;

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
            store.getPoolBalance(),
            store.getBufferBalance()
        );
    }

    function debitTraderProfit(
        address user,
        string memory market,
        uint256 amount
    ) external onlyTrade {
        if (amount == 0) return;

        uint256 bufferBalance = store.getBufferBalance();

        store.decrementBufferBalance(amount);

        if (amount > bufferBalance) {
            uint256 diffToPayFromPool = amount - bufferBalance;
            uint256 poolBalance = store.getPoolBalance();
            require(diffToPayFromPool < poolBalance, "!pool-balance");
            store.decrementPoolBalance(diffToPayFromPool);
        }

        store.incrementBalance(user, amount);

        emit PoolPayOut(
            user,
            market,
            amount,
            store.getPoolBalance(),
            store.getBufferBalance()
        );
    }

    function creditFee(
        address user,
        string memory market,
        uint256 fee,
        bool isLiquidation
    ) external onlyTrade {
        if (fee == 0) return;

        uint256 poolFee = (fee * store.getPoolFeeShare()) / BPS_DIVIDER;
        uint256 treasuryFee = fee - poolFee;

        store.incrementPoolBalance(poolFee);
        store.payTreasuryFee(treasuryFee);

        emit FeePaid(
            user,
            market,
            fee, // paid by user //
            poolFee,
            isLiquidation
        );
    }

    modifier onlyTrade() {
        require(msg.sender == trade, "!trade");
        _;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "!gov");
        _;
    }
}
