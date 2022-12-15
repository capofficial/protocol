// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface ITrade {
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

}