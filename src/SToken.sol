// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SToken is ERC20Burnable, Ownable {
    error SToken__AmountMustBeMoreThanZero();
    error SToken__BurnAmountExceedsBalance();
    error SToken__NotZeroAddress();

    address public immutable i_underlyingToken;

    constructor(
        address underlyingToken,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) Ownable(msg.sender) {
        i_underlyingToken = underlyingToken;
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert SToken__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert SToken__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert SToken__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert SToken__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    function burnFrom(
        address account,
        uint256 value
    ) public virtual override onlyOwner {
        _burn(account, value);
    }
}
