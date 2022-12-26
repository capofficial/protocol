// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CLP is ERC20 {
    address public store;

    constructor(address _store) ERC20("CLP", "CLP") {
        store = _store;
    }

    function mint(address to, uint256 amount) public {
        require(msg.sender == store, "!authorized");
        require(amount > 0, "!clp-amount");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        require(msg.sender == store, "!authorized");
        require(amount > 0, "!clp-amount");
        _burn(from, amount);
    }
}
