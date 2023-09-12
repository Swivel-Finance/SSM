// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.4;
import "forge-std/console.sol";
import './ERC/SolmateERC20.sol';
import './Utils/SafeTransferLib.sol';
import './Utils/FixedPointMathLib.sol';
import './Interfaces/IVault.sol';
import './Interfaces/IWETH.sol';
import './Interfaces/IQuery.sol';

contract stkSWIV is ERC20 {
    using FixedPointMathLib for uint256;

    // The Swivel Multisig (or should be)
    address public admin;
    // The Swivel Token
    ERC20 immutable public SWIV;
    // The Swivel/ETH balancer LP token
    ERC20 immutable public balancerLPT;
    // The Static Balancer Vault
    IVault immutable public balancerVault;
    // The Static Balancer Query Helper
    IQuery immutable public balancerQuery;

    // The Balancer Pool ID
    bytes32 public balancerPoolID;
    // The withdrawal cooldown length
    uint256 public cooldownLength = 2 weeks;
    // The window to withdraw after cooldown
    uint256 public withdrawalWindow = 1 weeks;
    // Mapping of user address -> unix timestamp for cooldown
    mapping (address => uint256) public cooldownTime;
    // Mapping of user address -> amount of stkSWIV shares to be withdrawn
    mapping (address => uint256) public cooldownAmount;
    // Determines whether the contract is paused or not
    bool public paused;
    // The most recently withdrawn BPT timestamp in unix (only when paying out insurance)
    uint256 public lastWithdrawnBPT;
    // The WETH address
    IWETH immutable public WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    error Exception(uint8, uint256, uint256, address, address);

    event TestException(uint256, address, string);

    constructor (ERC20 s, IVault v, ERC20 b, bytes32 p) ERC20("Staked SWIV/ETH", "stkSWIV", s.decimals() + 18) {
        SWIV = s;
        balancerVault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        balancerLPT = b;
        balancerPoolID = p;
        balancerQuery = IQuery(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);
        admin = msg.sender;
        SafeTransferLib.approve(SWIV, address(balancerVault), type(uint256).max);
        SafeTransferLib.approve(ERC20(address(WETH)), address(balancerVault), type(uint256).max);
    }

    fallback() external payable {
    }

    function asset() public view returns (address) {
        return (address(balancerLPT));
    }

    function totalAssets() public view returns (uint256 assets) {
        return (balancerLPT.balanceOf(address(this)));
    }

    // The number of SWIV/ETH balancer shares owned / the stkSWIV total supply
    // Conversion of 1 stkSWIV share to an amount of SWIV/ETH balancer shares (scaled to 1e18) (starts at 1:1e18)
    // Buffered by 1e18 to avoid 4626 inflation attacks -- https://ethereum-magicians.org/t/address-eip-4626-inflation-attacks-with-virtual-shares-and-assets/12677
    // @returns: the exchange rate
    function exchangeRateCurrent() public view returns (uint256) {
        return (this.totalSupply() + 1e18 / totalAssets() + 1);
    }

    // Conversion of amount of SWIV/ETH balancer assets to stkSWIV shares
    // @param: assets - amount of SWIV/ETH balancer pool tokens
    // @returns: the amount of stkSWIV shares
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        return (assets.mulDivDown(this.totalSupply() + 1e18, totalAssets() + 1));
    }

    // Conversion of amount of stkSWIV shares to SWIV/ETH balancer assets
    // @param: shares - amount of stkSWIV shares
    // @returns: the amount of SWIV/ETH balancer pool tokens
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        return (shares.mulDivDown(totalAssets() + 1, this.totalSupply() + 1e18));
    }

    // Preview of the amount of balancerLPT required to mint `shares` of stkSWIV
    // @param: shares - amount of stkSWIV shares
    // @returns: assets the amount of balancerLPT tokens required
    function previewMint(uint256 shares) public view virtual returns (uint256 assets) {
        return (shares.mulDivUp(totalAssets() + 1, this.totalSupply() + 1e18));
    }

    // Preview of the amount of balancerLPT received from redeeming `shares` of stkSWIV
    // @param: shares - amount of stkSWIV shares
    // @returns: assets the amount of balancerLPT tokens received
    function previewRedeem(uint256 shares) public view virtual returns (uint256 assets) {
        return (convertToAssets(shares));
    }

    // Preview of the amount of stkSWIV received from depositing `assets` of balancerLPT
    // @param: assets - amount of balancerLPT tokens
    // @returns: shares the amount of stkSWIV shares received
    function previewDeposit(uint256 assets) public view virtual returns (uint256 shares) {
        return (convertToShares(assets));
    }

    // Preview the amount of stkSWIV received from zapping and depositing `swivelAmount` of SWIV alongside a proportional amount of ETH
    // @param: swivelAmount - amount of SWIV tokens
    // @returns: shares the amount of stkSWIV shares received
    function previewDepositZap(uint256 swivelAmount) public returns (uint256 shares) {
        // Instantiate balancer request struct using SWIV and ETH alongside the amounts sent
        IAsset[] memory assetData = new IAsset[](2);
        assetData[0] = IAsset(address(SWIV));
        assetData[1] = IAsset(address(WETH));

        uint256[] memory amountData = new uint256[](2);
        amountData[0] = swivelAmount;
        amountData[1] = type(uint256).max;

        IVault.JoinPoolRequest memory requestData = IVault.JoinPoolRequest({
                    assets: assetData,
                    maxAmountsIn: amountData,
                    userData: abi.encode(1, amountData, 0),
                    fromInternalBalance: false
                });
        // Query the pool join to get the bpt out
        (uint256 bptOut, uint256[] memory amountsIn) = balancerQuery.queryJoin(balancerPoolID, msg.sender, address(this), requestData);

        return (convertToShares(bptOut));
    }

    // Preview of the amount of stkSWIV required to withdraw `assets` of balancerLPT
    // @param: assets - amount of balancerLPT tokens
    // @returns: shares the amount of stkSWIV shares required
    function previewWithdraw(uint256 assets) public view virtual returns (uint256 shares) {
        return (assets.mulDivUp(this.totalSupply() + 1e18, totalAssets() + 1));
    }

    // Maximum amount a given receiver can mint
    // @param: receiver - address of the receiver
    // @returns: the maximum amount of stkSWIV shares
    function maxMint(address receiver) public pure returns (uint256 maxShares) {
        return (type(uint256).max);
    }

    // Maximum amount a given owner can redeem
    // @param: owner - address of the owner
    // @returns: the maximum amount of stkSWIV shares
    function maxRedeem(address owner) public view returns (uint256 maxShares) {
        return (this.balanceOf(owner));
    }

    // Maximum amount a given owner can withdraw
    // @param: owner - address of the owner
    // @returns: the maximum amount of balancerLPT assets
    function maxWithdraw(address owner) public view returns (uint256 maxAssets) {
        return (convertToAssets(this.balanceOf(owner)));
    }

    // Maximum amount a given receiver can deposit
    // @param: receiver - address of the receiver
    // @returns: the maximum amount of balancerLPT assets
    function maxDeposit(address receiver) public pure returns (uint256 maxAssets) {
        return (type(uint256).max);
    }

    // Queues `amount` of balancerLPT assets to be withdrawn after the cooldown period
    // @param: amount - amount of balancerLPT assets to be withdrawn
    // @returns: the total amount of balancerLPT assets to be withdrawn
    function cooldown(uint256 shares) public returns (uint256) {
        // Require the total amount to be < balanceOf
        if (cooldownAmount[msg.sender] + shares > balanceOf[msg.sender]) {
            revert Exception(3, cooldownAmount[msg.sender] + shares, balanceOf[msg.sender], msg.sender, address(0));
        }
        // Reset cooldown time
        cooldownTime[msg.sender] = block.timestamp + cooldownLength;
        // Add the amount;
        cooldownAmount[msg.sender] = cooldownAmount[msg.sender] + shares;

        return(cooldownAmount[msg.sender]);
    }

    // Mints `shares` to `receiver` and transfers `assets` of balancerLPT tokens from `msg.sender`
    // @param: shares - amount of stkSWIV shares to mint
    // @param: receiver - address of the receiver
    // @returns: the amount of balancerLPT tokens deposited
    function mint(uint256 shares, address receiver) public payable returns (uint256) {
        // Convert shares to assets
        uint256 assets = previewMint(shares);
        // Transfer assets of balancer LP tokens from sender to this contract
        SafeTransferLib.transferFrom(balancerLPT, msg.sender, address(this), assets);
        // Mint shares to receiver
        _mint(receiver, shares);
        // Emit deposit event
        emit Deposit(msg.sender, receiver, assets, shares);

        return (assets);
    }

    // Redeems `shares` from `owner` and transfers `assets` of balancerLPT tokens to `receiver`
    // @param: shares - amount of stkSWIV shares to redeem
    // @param: receiver - address of the receiver
    // @param: owner - address of the owner
    // @returns: the amount of balancerLPT tokens withdrawn
    function redeem(uint256 shares, address receiver, address owner) Unpaused() public returns (uint256) {
        // Convert shares to assets
        uint256 assets = previewRedeem(shares);
        // Get the cooldown time
        uint256 cTime = cooldownTime[msg.sender];
        // If the sender is not the owner check allowances
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            // If the allowance is not max, subtract the shares from the allowance, reverts on underflow if not enough allowance
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        // If the cooldown time is in the future or 0, revert
        if (cTime > block.timestamp || cTime == 0 || cTime + withdrawalWindow < block.timestamp) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }
        // If the redeemed shares is greater than the cooldown amount, revert
        uint256 cAmount = cooldownAmount[msg.sender];
        if (shares > cAmount) {
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

    // Deposits `assets` of balancerLPT tokens from `msg.sender` and mints `shares` to `receiver`
    // @param: assets - amount of balancerLPT tokens to deposit
    // @param: receiver - address of the receiver
    // @returns: the amount of stkSWIV shares minted
    function deposit(uint256 assets, address receiver) public returns (uint256) {
        // Convert assets to shares          
        uint256 shares = previewDeposit(assets);
        // Transfer assets of balancer LP tokens from sender to this contract
        SafeTransferLib.transferFrom(balancerLPT, msg.sender, address(this), assets);        
        // Mint shares to receiver
        _mint(receiver, shares);
        // Emit deposit event
        emit Deposit(msg.sender, receiver, assets, shares);

        return (shares);
    }

    // Withdraws `assets` of balancerLPT tokens to `receiver` and burns `shares` from `owner`
    // @param: assets - amount of balancerLPT tokens to withdraw
    // @param: receiver - address of the receiver
    // @param: owner - address of the owner
    // @returns: the amount of stkSWIV shares withdrawn
    function withdraw(uint256 assets, address receiver, address owner) Unpaused()  public returns (uint256) {
        // Convert assets to shares
        uint256 shares = previewWithdraw(assets);(assets);
        // Get the cooldown time
        uint256 cTime = cooldownTime[msg.sender];
        // If the sender is not the owner check allowances
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            // If the allowance is not max, subtract the shares from the allowance, reverts on underflow if not enough allowance
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        // If the cooldown time is in the future or 0, revert
        if (cTime > block.timestamp || cTime == 0 || cTime + withdrawalWindow < block.timestamp) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }
        // If the redeemed shares is greater than the cooldown amount, revert
        uint256 cAmount = cooldownAmount[msg.sender];
        if (shares > cAmount) {
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

    //////////////////// ZAP METHODS ////////////////////

    // Transfers `assets` of SWIV tokens from `msg.sender` while receiving `msg.value` of ETH
    // Then joins the balancer pool with the SWIV and ETH before minting minBPT of shares to `receiver`
    // @notice: The amounts transacted in this method are based on msg.value -- `shares` is the minimum amount of shares to mint
    // @param: shares - minimum amount of stkSWIV shares to mint
    // @param: receiver - address of the receiver
    // @returns: assets the amount of SWIV tokens deposited
    // @returns: sharesToMint the actual amount of shares minted
    function mintZap(uint256 shares, address receiver) public payable returns (uint256 assets, uint256 sharesToMint, uint256[2] memory balancesSpent) {
        // Instantiate balancer request struct using SWIV and ETH alongside the amounts sent
        IAsset[] memory assetData = new IAsset[](2);
        assetData[0] = IAsset(address(SWIV));
        assetData[1] = IAsset(address(WETH));
        // Get token info from vault
        (,uint256[] memory balances,) = balancerVault.getPoolTokens(balancerPoolID);
        // Calculate SWIV transfer amount from msg.value (expecting at least enough msg.value and SWIV available to cover `shares` minted)
        uint256 swivAmount = msg.value * balances[0] / balances[1];

        uint256[] memory amountData = new uint256[](2);
        amountData[0] = swivAmount;
        amountData[1] = msg.value;

        IVault.JoinPoolRequest memory requestData = IVault.JoinPoolRequest({
                    assets: assetData,
                    maxAmountsIn: amountData,
                    userData: abi.encode(1, amountData, 0),
                    fromInternalBalance: false
                });
        // Query the pool join to get the bpt out (assets)
        (uint256 minBPT, uint256[] memory amountsIn) = balancerQuery.queryJoin(balancerPoolID, msg.sender, address(this), requestData);
        // Calculate expected shares to mint before transfering funds 
        sharesToMint = convertToShares(minBPT);
        // Wrap msg.value into WETH
        WETH.deposit{value: msg.value}();
        // Transfer assets of SWIV tokens from sender to this contract
        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), amountsIn[0]); 
        // Encode new userData with queried amountsIn and bptOut
        requestData.userData = abi.encode(1, amountsIn, minBPT);
        // Join the balancer pool using the request struct
        IVault(balancerVault).joinPool(balancerPoolID, address(this), address(this), requestData);
        // If the shares to mint is less than the minimum shares, revert
        if (sharesToMint < shares) {
            revert Exception(4, sharesToMint, shares, address(0), address(0));
        }
        // Mint shares to receiver
        _mint(receiver, sharesToMint);
        {
            // If there is any leftover SWIV, transfer it to the msg.sender
            uint256 remainingSWIV = SWIV.balanceOf(address(this));
            if (remainingSWIV > 0) {
                // Transfer the SWIV to the receiver
                SafeTransferLib.transfer(SWIV, msg.sender, remainingSWIV);
            }
            uint256 remainingWETH = WETH.balanceOf(address(this));
            // If there is any leftover ETH, transfer it to the msg.sender
            if (remainingWETH > 0) {
                // Transfer the ETH to the receiver
                WETH.withdraw(remainingWETH);
                payable(msg.sender).transfer(remainingWETH);
            }
        }
        // Emit deposit event
        emit Deposit(msg.sender, receiver, minBPT, sharesToMint);

        return (minBPT, sharesToMint, [amountsIn[0], amountsIn[1]]);
    }

    // Exits the balancer pool and transfers `assets` of SWIV tokens and the current balance of ETH to `receiver`
    // Then burns `shares` from `owner`
    // @param: shares - amount of stkSWIV shares to redeem
    // @param: receiver - address of the receiver
    // @param: owner - address of the owner
    // @returns: assets the amount of bpt withdrawn
    // @returns: sharesBurnt the amount of stkSWIV shares burnt
    function redeemZap(uint256 shares, address payable receiver, address owner) Unpaused()  public returns (uint256 assets, uint256 sharesBurnt, uint256[2] memory balancesReturned) {
        // Convert shares to assets
        assets = previewRedeem(shares);
        {
            // Get the cooldown time
            uint256 cTime = cooldownTime[msg.sender];
            // If the sender is not the owner check allowances
            if (msg.sender != owner) {
                uint256 allowed = allowance[owner][msg.sender];
                // If the allowance is not max, subtract the shares from the allowance, reverts on underflow if not enough allowance
                if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
            }
            // If the cooldown time is in the future or 0, revert
            if (cTime > block.timestamp || cTime == 0 || cTime + withdrawalWindow < block.timestamp) {
                revert Exception(0, cTime, block.timestamp, address(0), address(0));
            }
            {
                // If the redeemed shares is greater than the cooldown amount, revert
                uint256 cAmount = cooldownAmount[msg.sender];
                if (shares > cAmount) {
                    revert Exception(1, cAmount, shares, address(0), address(0));
                }
            }
        }
        // If the shares are greater than the balance of the owner, revert
        if (shares > this.balanceOf(owner)) {
            revert Exception(2, shares, this.balanceOf(owner), address(0), address(0));
        }
        // Instantiate balancer request struct using SWIV and ETH alongside the asset amount and 0 ETH
        IAsset[] memory assetData = new IAsset[](2);
        assetData[0] = IAsset(address(SWIV));
        assetData[1] = IAsset(address(WETH));

        uint256[] memory amountData = new uint256[](2);
        amountData[0] = 0;
        amountData[1] = 0;

        IVault.ExitPoolRequest memory requestData = IVault.ExitPoolRequest({
            assets: assetData,
            minAmountsOut: amountData,
            userData: abi.encode(1, assets),
            toInternalBalance: false
        });
        // Query the pool exit to get the amounts out
        (uint256 bptIn, uint256[] memory amountsOut) = balancerQuery.queryExit(balancerPoolID, address(this), address(this), requestData);
        // if bptIn isnt equivalent to assets, overwrite shares
        if (bptIn != assets) {
            shares = convertToShares(bptIn);
            // Require the bptIn <= shares converted to assets (to account for slippage)
            if (bptIn > convertToAssets(shares)) {
                revert Exception(5, bptIn, convertToAssets(shares), address(0), address(0));
            }
        }
        // Encode new userData with queried amountsOut and bptIn
        requestData.userData = abi.encode(1, bptIn);
        // Exit the balancer pool using the request struct
        IVault(balancerVault).exitPool(balancerPoolID, payable(address(this)), payable(address(this)), requestData);
        // // Transfer the SWIV tokens to the receiver
        SafeTransferLib.transfer(SWIV, receiver, SWIV.balanceOf(address(this)));
        // // Transfer the ETH to the receiver
        receiver.transfer(address(this).balance);
        // Burn the shares
        _burn(msg.sender, shares);
        // // Reset the cooldown time
        cooldownTime[msg.sender] = 0;
        // // Reset the cooldown amount
        cooldownAmount[msg.sender] = 0;
        // // Emit withdraw event
        emit Withdraw(msg.sender, receiver, owner, bptIn, shares);

        return (assets, shares, [amountsOut[0], amountsOut[1]]);
    }

    // Transfers `assets` of SWIV tokens from `msg.sender` while receiving `msg.value` of ETH
    // Then joins the balancer pool with the SWIV and ETH before minting `shares` to `receiver`
    // @param: assets - maximum amount of SWIV tokens to deposit
    // @param: receiver - address of the receiver
    // @param: minimumBPT - minimum amount of balancerLPT tokens to mint
    // @returns: the amount of stkSWIV shares minted
    // @returns: the amount of swiv actually deposited
    function depositZap(uint256 assets, address receiver, uint256 minimumBPT) public payable returns (uint256 sharesMinted, uint256 bptIn, uint256[2] memory balancesSpent) {
        // Transfer assets of SWIV tokens from sender to this contract
        SafeTransferLib.transferFrom(SWIV, msg.sender, address(this), assets);
        // Wrap msg.value into WETH
        WETH.deposit{value: msg.value}();
        // Instantiate balancer request struct using SWIV and ETH alongside the amounts sent
        IAsset[] memory assetData = new IAsset[](2);
        assetData[0] = IAsset(address(SWIV));
        assetData[1] = IAsset(address(WETH));

        uint256[] memory amountData = new uint256[](2);
        amountData[0] = assets;
        amountData[1] = msg.value;

        IVault.JoinPoolRequest memory requestData = IVault.JoinPoolRequest({
                    assets: assetData,
                    maxAmountsIn: amountData,
                    userData: abi.encode(1, amountData, 0),
                    fromInternalBalance: false
                });
        // Query the pool join to get the bpt out
        (uint256 bptOut, uint256[] memory amountsIn) = balancerQuery.queryJoin(balancerPoolID, msg.sender, address(this), requestData);
        // If the bptOut is less than the minimum bpt, revert (to account for slippage)
        if (bptOut < minimumBPT) {
            revert Exception(5, bptOut, minimumBPT, address(0), address(0));
        }
        //  Calculate shares to mint
        sharesMinted = convertToShares(bptOut);
        // Encode new userData with queried amountsIn and bptOut
        requestData.userData = abi.encode(1, amountsIn, bptOut);
        // Join the balancer pool using the request struct
        IVault(balancerVault).joinPool(balancerPoolID, address(this), address(this), requestData);
        // // Mint shares to receiver
        _mint(receiver, sharesMinted);
        // If there is any leftover SWIV, transfer it to the msg.sender
        uint256 swivBalance = SWIV.balanceOf(address(this));
        if (swivBalance > 0) {
            // Transfer the SWIV to the receiver
            SafeTransferLib.transfer(SWIV, msg.sender, swivBalance);
        }
        // If there is any leftover ETH, transfer it to the msg.sender
        if (WETH.balanceOf(address(this)) > 0) {
            // Transfer the ETH to the receiver
            uint256 wethAmount = WETH.balanceOf(address(this));
            WETH.withdraw(wethAmount);
            payable(msg.sender).transfer(wethAmount);
        }
        // Emit deposit event
        emit Deposit(msg.sender, receiver, assets, sharesMinted);

        return (sharesMinted, bptOut, [amountsIn[0], amountsIn[1]]);
    }

    // Exits the balancer pool and transfers `assets` of SWIV tokens and the current balance of ETH to `receiver`
    // Then burns `shares` from `owner`
    // @param: assets - amount of SWIV tokens to withdraw
    // @param: receiver - address of the receiver
    // @param: owner - address of the owner
    // @param: maximumBPT - maximum amount of balancerLPT tokens to redeem
    // @returns: the amount of stkSWIV shares burnt
    function withdrawZap(uint256 assets, uint256 ethAssets, address payable receiver, address owner, uint256 maximumBPT) Unpaused() public returns (uint256 sharesRedeemed, uint256 bptOut, uint256[2] memory balancesReturned) {
        // Get the cooldown time
        uint256 cTime = cooldownTime[msg.sender];
        // If the sender is not the owner check allowances
        // If the cooldown time is in the future or 0, revert
        if (cTime > block.timestamp || cTime == 0 || cTime + withdrawalWindow < block.timestamp) {
            revert Exception(0, cTime, block.timestamp, address(0), address(0));
        }
        // Query pool info from balancer vault
        (,uint256[] memory balances,) = balancerVault.getPoolTokens(balancerPoolID);
        // Instantiate balancer request struct using SWIV and ETH alongside the asset amount and 0 ETH
        IAsset[] memory assetData = new IAsset[](2);
        assetData[0] = IAsset(address(SWIV));
        assetData[1] = IAsset(address(WETH));

        uint256[] memory amountData = new uint256[](2);
        amountData[0] = assets;
        amountData[1] = ethAssets;

        IVault.ExitPoolRequest memory requestData = IVault.ExitPoolRequest({
            assets: assetData,
            minAmountsOut: amountData,
            userData: abi.encode(2, amountData, type(uint256).max),
            toInternalBalance: false
        });
        // Query the pool exit to get the amounts out
        (uint256 bptOut, uint256[] memory amountsOut) = balancerQuery.queryExit(balancerPoolID, address(this), address(this), requestData);
        // Require the bptOut to be less than the maximum bpt (to account for slippage)
        if (bptOut > maximumBPT) {
            revert Exception(5, bptOut, maximumBPT, address(0), address(0));
        }
        // Calculate shares to redeem
        sharesRedeemed = convertToShares(bptOut);
        // Encode new userData with queried amountsOut and bptIn
        requestData.userData = abi.encode(2, amountsOut, bptOut);
        // Convert bptIn to shares
        // This method is unique in that we cannot check against cAmounts before calculating shares
        // If the redeemed shares is greater than the cooldown amount, revert
        {
            uint256 cAmount = cooldownAmount[msg.sender];
            if (sharesRedeemed > cAmount) {
                revert Exception(1, cAmount, sharesRedeemed, address(0), address(0));
            }
        }
        // If the shares are greater than the balance of the owner, revert
        if (sharesRedeemed > this.balanceOf(owner)) {
            revert Exception(2, sharesRedeemed, this.balanceOf(owner), address(0), address(0));
        }
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            // If the allowance is not max, subtract the shares from the allowance, reverts on underflow if not enough allowance
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - sharesRedeemed;
        }
        // Exit the balancer pool using the request struct
        IVault(balancerVault).exitPool(balancerPoolID, payable(address(this)), payable(address(this)), requestData);
        // Unwrap the WETH
        WETH.withdraw(amountsOut[1]);
        // Transfer the SWIV tokens to the receiver
        SafeTransferLib.transfer(SWIV, receiver, amountsOut[0]);
        // Transfer the ETH to the receiver
        receiver.transfer(amountsOut[1]);
        // Burn the shares
        _burn(msg.sender, sharesRedeemed);
        // Reset the cooldown time
        cooldownTime[msg.sender] = 0;
        // Reset the cooldown amount
        cooldownAmount[msg.sender] = 0;
        // Emit withdraw event
        emit Withdraw(msg.sender, receiver, owner, bptOut, sharesRedeemed);

        return (sharesRedeemed, bptOut, [amountsOut[0], amountsOut[1]]);
    }

    //////////////////// ADMIN FUNCTIONS ////////////////////

    // Method to redeem and withdraw BAL incentives or other stuck tokens / those needing recovery
    // @param: token - address of the token to withdraw
    // @param: receiver - address of the receiver
    // @returns: the amount of tokens withdrawn
    function adminWithdraw(address token, address payable receiver) Authorized(admin) public returns (uint256) {
        if (token == address(0)) {
            receiver.transfer(address(this).balance);
            return (address(this).balance);
        }
        else {
            // If the token is balancerBPT, transfer 30% of the held balancerBPT to receiver
            if (token == address(balancerLPT)) {
                // Require a week between bpt withdrawals
                require(block.timestamp >= lastWithdrawnBPT + 1 weeks, "Admin already withdrawn recently");
                // Calculate max balance that can be withdrawn
                uint256 bptToTransfer = balancerLPT.balanceOf(address(this)) / 3;
                // Transfer the balancer LP tokens to the receiver
                SafeTransferLib.transfer(balancerLPT, receiver, bptToTransfer);
                // Reset the last withdrawn timestamp
                lastWithdrawnBPT = block.timestamp;
                return (bptToTransfer);
            }
            else {
                // Get the balance of the token
                uint256 balance = IERC20(token).balanceOf(address(this));
                // Transfer the token to the receiver
                SafeTransferLib.transfer(ERC20(token), receiver, balance);
                return (balance);
            }
        }
    }

    // Sets a new admin address
    // @param: _admin - address of the new admin
    function setAdmin(address _admin) Authorized(admin) public {
        admin = _admin;
    }

    // Pauses all withdrawing
    function pause(bool b) Authorized(admin) public {
        paused = b;
    }

    // Authorized modifier
    modifier Authorized(address) {
        require(msg.sender == admin || msg.sender == address(this), "Not authorized");
        _;
    }

    // Unpaused modifier
    modifier Unpaused() {
        require(!paused, "Paused");
        _;
    }
}