// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract MockChainlink {
    mapping(address => uint256) prices;

    constructor() {}

    function setPrice(address feed, uint256 price) external {
        prices[feed] = price;
    }

    function getPrice(address feed) external view returns (uint256) {
        return prices[feed];
    }
}
