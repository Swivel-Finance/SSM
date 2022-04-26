// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.4;

import './ERC/SolmateERC20.sol';
import './Utils/SafeTransferLib.sol';

contract stkSWIV is ERC20 {

    ERC20 immutable SWIV;

    uint256 public totalDeposited;

    constructor (ERC20 s) ERC20("Staked SWIV", "stkSWIV", 18) {
        SWIV = s;
    }

    function exchangeRateCurrent() public view returns (uint256) {
        return ((SWIV.balanceOf(address(this))*1e26)/totalDeposited);
    }

    function mint(uint256 amount) public returns (uint256) {

        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), amount);

        uint256 returned = ((amount * 1e26)/exchangeRateCurrent());

        _mint(msg.sender, returned);

        return (returned);
    }

    function deposit(uint256 amount) public returns (uint256) {

        uint256 sent = (amount * exchangeRateCurrent())/1e26;

        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), sent);        

        _mint(msg.sender, amount);

        return (amount);
    }

    function redeemUnderlying(uint256 amount) public returns (uint256) {

        uint256 sent = ((amount * 1e26)/exchangeRateCurrent());

        _burn(msg.sender, sent);

        SafeTransferLib.transfer(SWIV, msg.sender, amount);

        return (amount);
    }

    function redeemShares(uint256 amount) public returns (uint256) {

        uint256 returned = (amount * exchangeRateCurrent())/1e26;

        _burn(msg.sender, amount);

        SafeTransferLib.transfer(SWIV, msg.sender, returned);

        return (amount);
    }
}