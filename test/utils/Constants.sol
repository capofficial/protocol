// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract Constants is Test {
    uint256 public constant UNIT = 10 ** 18;
    uint256 public constant BPS_DIVIDER = 10000;
    uint256 public constant CURRENCY_UNIT = 10 ** 6;
    uint256 public constant INITIAL_BALANCE = 1000_000 * CURRENCY_UNIT;
    uint256 public constant INITIAL_TRADE_DEPOSIT = 5000 * CURRENCY_UNIT;

    // 1 ETH = 5k USD, 1 BTC = 100k USD
    uint256 public constant ETH_PRICE = 5000 * UNIT;
    uint256 public constant BTC_PRICE = 100_000 * UNIT;
    // stop loss 2% below current price
    uint256 public constant ETH_SL_PRICE = 4900 * UNIT;
    uint256 public constant BTC_SL_PRICE = 98000 * UNIT;
    // take profit 2% above current price
    uint256 public constant ETH_TP_PRICE = 5100 * UNIT;
    uint256 public constant BTC_TP_PRICE = 102_000 * UNIT;

    address public treasury = makeAddr("Treasury");
    address public user = address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);
    address public user2 = address(0x90F79bf6EB2c4f870365E785982E1f101E93b906);

    address public ethFeed = makeAddr("ETH-USD");
    address public btcFeed = makeAddr("BTC-USD");
}
