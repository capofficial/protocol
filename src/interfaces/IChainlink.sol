// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IChainlink {
    function setPrice(address feed, uint256 price) external;

    function getPrice(address feed) external view returns (uint256);
}
