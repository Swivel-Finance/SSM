// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.4;

import './ERC/SolmateERC20.sol';
import './Utils/SafeTransferLib.sol';

contract stkSWIV is ERC20 {

    ERC20 public immutable SWIV;

    uint256 public totalDeposited;

    constructor (ERC20 s) ERC20("Staked SWIV", "stkSWIV", 18) {
        SWIV = s;
    }

    ////////////////// READ METHODS //////////////////
    function exchangeRateCurrent() public view returns (uint256) {
        return ((SWIV.balanceOf(address(this))*1e26)/totalDeposited);
    }

    function totalAssets() public view returns (uint256 totalManagedAssets) {
        return (SWIV.balanceOf(address(this)));
    }

    function asset() public view returns (ERC20 assetTokenAddress) {
        return(SWIV);
    }

    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        return((assets * 1e26)/exchangeRateCurrent());
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        return((shares * exchangeRateCurrent())/1e26);
    }

    function maxDeposit(address receiver) public pure returns (uint256 maxAssets) {
        return(2 ** 256 - 1);
    }

    function maxMint(address receiver) public pure returns (uint256 maxShares) {
        return(2 ** 256 - 1);
    }   

    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        return(balanceOf[owner]);
    }      

    function maxWithdraw(address owner) public view returns (uint256 maxAssets) {
        return(convertToAssets(balanceOf[owner]));
    }

    function previewMint(uint256 shares) public view returns (uint256 assets) {
        return(convertToAssets(shares));
    }

    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        return(convertToShares(assets));
    }

    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        return(convertToAssets(shares));
    }

    function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
        return(convertToShares(assets));
    }

    ////////////////// WRITE METHODS //////////////////
    function mint(uint256 shares, address receiver) public returns (uint256 assets) {

        assets = convertToAssets(shares);

        totalDeposited += assets;

        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);        

        _mint(receiver, shares);

        return (assets);
    }

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {

        shares = convertToAssets(assets);
        
        totalDeposited += assets;

        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);

        _mint(receiver, shares);

        return (shares);
    }

    function withdraw(uint256 assets, address receiver) public returns (uint256 shares) {

        shares = convertToAssets(assets);

        _burn(msg.sender, shares);

        SafeTransferLib.transfer(SWIV, receiver, assets);

        return (shares);
    }

    function redeem(uint256 shares, address receiver) public returns (uint256 assets) {

        assets = convertToAssets(shares);

        _burn(msg.sender, shares);

        SafeTransferLib.transfer(SWIV, receiver, assets);

        return (assets);
    }
}