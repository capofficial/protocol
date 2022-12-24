// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CLP is ERC20 {
    address public store;

    constructor(address _store) ERC20("CLP", "CLP") {
        store = _store;
    }

    function mint(address to, uint256 amount) public {
        _storeOnly();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _storeOnly();
        _burn(from, amount);
    }

    function _storeOnly() private view {
        address store_ = store;
        require(msg.sender == store_, "!authorized");
    }
}
