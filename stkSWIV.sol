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

    function mint(uint256 shares, address receiver) public returns (uint256) {

        uint256 assets = (shares * exchangeRateCurrent())/1e26;

        totalDeposited += assets;

        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);        

        _mint(receiver, shares);

        return (assets);
    }

    function deposit(uint256 assets, address receiver) public returns (uint256) {

        uint256 shares = ((assets * 1e26)/exchangeRateCurrent());
        
        totalDeposited += assets;

        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);

        _mint(receiver, shares);

        return (shares);
    }

    function withdraw(uint256 assets, address receiver) public returns (uint256) {

        uint256 shares = ((assets * 1e26)/exchangeRateCurrent());

        _burn(msg.sender, shares);

        SafeTransferLib.transfer(SWIV, receiver, assets);

        return (shares);
    }

    function redeem(uint256 shares, address receiver) public returns (uint256) {

        uint256 assets = (shares * exchangeRateCurrent())/1e26;

        _burn(msg.sender, shares);

        SafeTransferLib.transfer(SWIV, receiver, assets);

        return (assets);
    }
}