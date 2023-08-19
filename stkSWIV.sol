// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.4;

import './ERC/SolmateERC20.sol';
import './Utils/SafeTransferLib.sol';
import './Interfaces/IVault.sol';

contract stkSWIV is ERC20 {

    ERC20 immutable public SWIV;

    ERC20 immutable public balancerLPT;

    Vault immutable public balancerVault;

    bytes32 public balancerPoolID;

    uint256 public cooldownLength = 2 weeks;

    mapping (address => uint256) cooldownTime;

    mapping (address => uint256) cooldownAmount;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    error Exception(uint8, uint256, uint256, address, address);

    constructor (Vault v, ERC20 s, ERC20 b, bytes32 p) ERC20("Staked SWIV", "stkSWIV", 18) {
        Vault = v;
        SWIV = s;
        balancerLPT = b;
        balancerPoolID = p;
    }

    // The number of SWIV/ETH balancer shares owned / the stkSWIV total supply
    // Conversion of 1 stkSWIV share to an amount of SWIV/ETH balancer shares (scaled to 1e26) (starts at 1:1e26)
    function exchangeRateCurrent() public view returns (uint256) {
        return ((SWIV.balanceOf(address(this)) * 1e26) / this.totalSupply());
    }

    // Conversion of amount of SWIV/ETH balancer shares to stkSWIV shares
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        return ((assets * 1e26) / exchangeRateCurrent());
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        return ((shares * exchangeRateCurrent()) / 1e26);
    }

    function maxMint(address receiver) public view returns (uint256 maxShares) {
        return type(uint256).max;
    }

    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        return (this.balanceOf(owner));
    }

    function maxWithdraw(address owner) public view returns (uint256 maxAssets) {
        return (convertToAssets(this.balanceOf(owner)));
    }

    function maxDeposit(address receiver) public view returns (uint256 maxAssets) {
        return type(uint256).max;
    }

    function cooldown(uint256 amount) public returns (uint256) {

        // Require the total amount to be < balanceOf
        if (cooldownAmount[msg.sender] + amount > balanceOf[msg.sender]) {
            revert Exception(3, cooldownAmount[msg.sender] + amount, balanceOf[msg.sender], msg.sender, address(0));
        }
        // Reset cooldown time
        cooldownTime[msg.sender] = block.timestamp + cooldownLength;
        // Add the amount;
        cooldownAmount[msg.sender] = cooldownAmount[msg.sender] + amount;
    }

    function mint(uint256 shares, address receiver) public payable returns (uint256) {

        uint256 assets = convertToAssets(shares);

        SafeTransferLib.transferFrom(balancerLPT, msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        return (assets);
    }

    function redeem(uint256 shares, address receiver) public returns (uint256) {

        uint256 assets = convertToAssets(shares);

        uint256 cTime = cooldownTime[msg.sender];

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        if (cTime > block.timestamp || cTime == 0) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }

        uint256 cAmount = cooldownAmount[msg.sender];
        if (cAmount > assets) {
            revert Exception(1, cAmount, shares, address(0), address(0));
        }

        SafeTransferLib.transfer(balancerLPT, receiver, assets);

        _burn(msg.sender, shares);

        cooldownTime[msg.sender] = 0;

        cooldownAmount[msg.sender] = 0;

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return (assets);
    }

    function deposit(uint256 assets, address receiver) public returns (uint256) {

        uint256 shares = convertToShares(assets);

        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);        

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        return (shares);
    }

    function withdraw(uint256 assets, address receiver) public returns (uint256) {

        uint256 shares = convertToShares(assets);

        uint256 cTime = cooldownTime[msg.sender];

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        if (cTime > block.timestamp || cTime == 0) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }

        uint256 cAmount = cooldownAmount[msg.sender];
        if (cAmount > assets) {
            revert Exception(1, cAmount, shares, address(0), address(0));
        }

        SafeTransferLib.transfer(balancerLPT, receiver, assets);

        _burn(msg.sender, shares);

        cooldownTime[msg.sender] = 0;

        cooldownAmount[msg.sender] = 0;

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return (shares);
    }

    function mintZap(uint256 shares, address receiver) public payable returns (uint256) {

        uint256 assets = convertToAssets(shares);

        SafeTransferLib.transferFrom(balancerLPT, msg.sender, address(this), assets);

        // Todo: balancer tx

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        return (assets);
    }

    function redeemZap(uint256 shares, address receiver, address owner) public returns (uint256) {

        uint256 assets = convertToAssets(shares);

        uint256 cTime = cooldownTime[msg.sender];

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        if (cTime > block.timestamp || cTime == 0) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }

        uint256 cAmount = cooldownAmount[msg.sender];
        if (cAmount > assets) {
            revert Exception(1, cAmount, shares, address(0), address(0));
        }

        // Todo: balancer tx

        SafeTransferLib.transfer(balancerLPT, receiver, assets);

        // Todo: ETH transfer

        _burn(msg.sender, shares);

        cooldownTime[msg.sender] = 0;

        cooldownAmount[msg.sender] = 0;

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return (assets);
    }

    function depositZap(uint256 assets, address receiver) public payable returns (uint256) {

        uint256 shares = convertToShares(assets);

        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);        

        // Todo: balancer tx

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        return (shares);
    }

    function withdrawZap(uint256 assets, address receiver, address owner) public returns (uint256) {

        uint256 shares = convertToShares(assets);

        uint256 cTime = cooldownTime[msg.sender];

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        if (cTime > block.timestamp || cTime == 0) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }

        uint256 cAmount = cooldownAmount[msg.sender];
        if (cAmount > assets) {
            revert Exception(1, cAmount, shares, address(0), address(0));
        }

        // Todo: balancer tx

        SafeTransferLib.transfer(balancerLPT, receiver, assets);

        // Todo: ETH transfer

        _burn(msg.sender, shares);

        cooldownTime[msg.sender] = 0;

        cooldownAmount[msg.sender] = 0;

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return (shares);
    }

}