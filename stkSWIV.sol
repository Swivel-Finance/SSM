// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.4;

import './ERC/SolmateERC20.sol';
import './Utils/SafeTransferLib.sol';
import './Interfaces/IVault.sol';

contract stkSWIV is ERC20 {

    address public admin;

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
        // Convert shares to assets
        uint256 assets = convertToAssets(shares);
        // Transfer assets of balancer LP tokens from sender to this contract
        SafeTransferLib.transferFrom(balancerLPT, msg.sender, address(this), assets);
        // Mint shares to receiver
        _mint(receiver, shares);
        // Emit deposit event
        emit Deposit(msg.sender, receiver, assets, shares);

        return (assets);
    }

    function redeem(uint256 shares, address receiver) public returns (uint256) {
        // Convert shares to assets
        uint256 assets = convertToAssets(shares);
        // Get the cooldown time
        uint256 cTime = cooldownTime[msg.sender];
        // If the sender is not the owner check allowances
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            // If the allowance is not max, subtract the shares from the allowance, reverts on underflow if not enough allowance
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        // If the cooldown time is in the future or 0, revert
        if (cTime > block.timestamp || cTime == 0) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }
        // If the cooldown amount is greater than the assets, revert
        uint256 cAmount = cooldownAmount[msg.sender];
        if (cAmount > assets) {
            revert Exception(1, cAmount, shares, address(0), address(0));
        }
        // If the shares are greater than the balance of the owner, revert
        if (shares > this.balanceOf(owner)) {
            revert Exception(2, shares, this.balanceOf(owner), address(0), address(0));
        }
        // Transfer the balancer LP tokens to the receiver
        SafeTransferLib.transfer(balancerLPT, receiver, assets);
        // Burn the shares
        _burn(msg.sender, shares);
        // Reset the cooldown time
        cooldownTime[msg.sender] = 0;
        // Reset the cooldown amount
        cooldownAmount[msg.sender] = 0;
        // Emit withdraw event
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return (assets);
    }

    function deposit(uint256 assets, address receiver) public returns (uint256) {
        // Convert assets to shares          
        uint256 shares = convertToShares(assets);
        // Transfer assets of balancer LP tokens from sender to this contract
        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);        
        // Mint shares to receiver
        _mint(receiver, shares);
        // Emit deposit event
        emit Deposit(msg.sender, receiver, assets, shares);

        return (shares);
    }

    function withdraw(uint256 assets, address receiver) public returns (uint256) {
        // Convert assets to shares
        uint256 shares = convertToShares(assets);
        // Get the cooldown time
        uint256 cTime = cooldownTime[msg.sender];
        // If the sender is not the owner check allowances
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            // If the allowance is not max, subtract the shares from the allowance, reverts on underflow if not enough allowance
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        // If the cooldown time is in the future or 0, revert
        if (cTime > block.timestamp || cTime == 0) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }
        // If the cooldown amount is greater than the assets, revert
        uint256 cAmount = cooldownAmount[msg.sender];
        if (cAmount > assets) {
            revert Exception(1, cAmount, shares, address(0), address(0));
        }
        // If the shares are greater than the balance of the owner, revert
        if (shares > this.balanceOf(owner)) {
            revert Exception(2, shares, this.balanceOf(owner), address(0), address(0));
        }
        // Transfer the balancer LP tokens to the receiver
        SafeTransferLib.transfer(balancerLPT, receiver, assets);
        // Burn the shares   
        _burn(msg.sender, shares);
        // Reset the cooldown time
        cooldownTime[msg.sender] = 0;
        // Reset the cooldown amount
        cooldownAmount[msg.sender] = 0;
        // Emit withdraw event
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return (shares);
    }

    function mintZap(uint256 shares, address receiver) public payable returns (uint256) {
        // Convert shares to assets
        uint256 assets = convertToAssets(shares);
        // Transfer assets of SWIV tokens from sender to this contract
        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);

        // Instantiate balancer request struct using SWIV and ETH alongside the amounts sent
        JoinPoolRequest memory requestData = JoinPoolRequest({
            assets: [SWIV, address(0)],
            maxAmountsIn: [assets, msg.value],
            userData: new bytes(0),
            fromInternalBalance: false
        });
        // Join the balancer pool using the request struct
        IVault(balancerVault).joinPool(poolId, address(this), address(this), request);
        // Mint shares to receiver
        _mint(receiver, shares);
        // Emit deposit event
        emit Deposit(msg.sender, receiver, assets, shares);

        return (assets);
    }

    function redeemZap(uint256 shares, address receiver, address owner) public returns (uint256) {
        // Convert shares to assets
        uint256 assets = convertToAssets(shares);
        // Get the cooldown time
        uint256 cTime = cooldownTime[msg.sender];
        // If the sender is not the owner check allowances
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            // If the allowance is not max, subtract the shares from the allowance, reverts on underflow if not enough allowance
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        // If the cooldown time is in the future or 0, revert
        if (cTime > block.timestamp || cTime == 0) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }
        // If the cooldown amount is greater than the assets, revert
        uint256 cAmount = cooldownAmount[msg.sender];
        if (cAmount > assets) {
            revert Exception(1, cAmount, shares, address(0), address(0));
        }
        // If the shares are greater than the balance of the owner, revert
        if (shares > this.balanceOf(owner)) {
            revert Exception(2, shares, this.balanceOf(owner), address(0), address(0));
        }
        // Instantiate balancer request struct using SWIV and ETH alongside the asset amount and 0 ETH 
        // TODO: consider how to set the ETH amount
        ExitPoolRequest memory requestData = ExitPoolRequest({
            assets: [SWIV, address(0)],
            minAmountsOut: [assets, 0],
            userData: new bytes(0),
            toInternalBalance: false
        });
        // Exit the balancer pool using the request struct
        IVault(balancerVault).exitPool(poolId, address(this), address(this), request);
        // Transfer the SWIV tokens to the receiver
        SafeTransferLib.transfer(SWIV, receiver, SWIV.balanceOf(address(this)));
        // Transfer the ETH to the receiver
        reciever.transfer(address(this).balance);
        // Burn the shares
        _burn(msg.sender, shares);
        // Reset the cooldown time
        cooldownTime[msg.sender] = 0;
        // Reset the cooldown amount
        cooldownAmount[msg.sender] = 0;
        // Emit withdraw event
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return (assets);
    }

    function depositZap(uint256 assets, address receiver) public payable returns (uint256) {
        // Convert assets to shares
        uint256 shares = convertToShares(assets);
        // Transfer assets of SWIV tokens from sender to this contract
        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);        
        // Instantiate balancer request struct using SWIV and ETH alongside the amounts sent
        JoinPoolRequest memory requestData = JoinPoolRequest({
            assets: [SWIV, address(0)],
            maxAmountsIn: [assets, msg.value],
            userData: new bytes(0),
            fromInternalBalance: false
        });
        // Join the balancer pool using the request struct
        IVault(balancerVault).joinPool(poolId, address(this), address(this), request);
        // Mint shares to receiver
        _mint(receiver, shares);
        // Emit deposit event
        emit Deposit(msg.sender, receiver, assets, shares);

        return (shares);
    }

    function withdrawZap(uint256 assets, address receiver, address owner) public returns (uint256) {
        // Convert assets to shares
        uint256 shares = convertToShares(assets);
        // Get the cooldown time
        uint256 cTime = cooldownTime[msg.sender];
        // If the sender is not the owner check allowances
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            // If the allowance is not max, subtract the shares from the allowance, reverts on underflow if not enough allowance
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        // If the cooldown time is in the future or 0, revert
        if (cTime > block.timestamp || cTime == 0) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }
        // If the cooldown amount is greater than the assets, revert
        uint256 cAmount = cooldownAmount[msg.sender];
        if (cAmount > assets) {
            revert Exception(1, cAmount, shares, address(0), address(0));
        }
        // If the shares are greater than the balance of the owner, revert
        if (shares > this.balanceOf(owner)) {
            revert Exception(2, shares, this.balanceOf(owner), address(0), address(0));
        }
        // Instantiate balancer request struct using SWIV and ETH alongside the asset amount and 0 ETH
        ExitPoolRequest memory requestData = ExitPoolRequest({
            assets: [SWIV, address(0)],
            minAmountsOut: [assets, 0],
            userData: new bytes(0),
            toInternalBalance: false
        });
        // Exit the balancer pool using the request struct
        IVault(balancerVault).exitPool(poolId, address(this), address(this), request);
        // Transfer the SWIV tokens to the receiver
        SafeTransferLib.transfer(SWIV, receiver, SWIV.balanceOf(address(this)));
        // Transfer the ETH to the receiver
        reciever.transfer(address(this).balance);
        // Burn the shares
        _burn(msg.sender, shares);
        // Reset the cooldown time
        cooldownTime[msg.sender] = 0;
        // Reset the cooldown amount
        cooldownAmount[msg.sender] = 0;
        // Emit withdraw event
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return (shares);
    }

    // Method to redeem and withdraw BAL incentives or other stuck tokens / those needing recovery
    function BALWithdraw(address token, address receiver) public returns (uint256) {
        if (token == address(0)) {
            receiver.transfer(address(this).balance);
        }
        else {
            // Get the balance of the token
            uint256 balance = IERC20(token).balanceOf(address(this));
            // Transfer the token to the receiver
            SafeTransferLib.transfer(IERC20(token), receiver, balance);
        }
        return (balance);
    }

    // Authorized modifier
    modifier authorized(address) {
        require(msg.sender == owner || msg.sender == address(this), "Not authorized");
        _;
    }

}