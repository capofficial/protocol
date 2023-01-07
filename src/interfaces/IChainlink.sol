// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IChainlink {
    function getPrice(address feed) external view returns (uint256);
}
