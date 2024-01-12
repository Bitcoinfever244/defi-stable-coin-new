//SPDX-License-Identifier:Mit

pragma solidity ^0.8.19;

import {ERC20Burnable,ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DefiStableCoin is ERC20Burnable, Ownable {
    error DefiStableCoin__MustBeMoreThanZero();
    error DefiStableCoin__BurnAmountExceedBalance();
    error DefiStableCoin__NotZeroAddress();

    constructor() ERC20("DefiStableCoin", "DSC") Ownable() {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DefiStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DefiStableCoin__BurnAmountExceedBalance();
        }
        super.burn(_amount); // super key word, use burn function from parent class.. ERC20 burnable
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DefiStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DefiStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}

