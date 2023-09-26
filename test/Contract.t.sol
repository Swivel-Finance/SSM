// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import '../src/Interfaces/IQuery.sol';

import {stkSWIV} from 'src/stkSWIV.sol';
import {ERC20} from 'src/ERC/SolmateERC20.sol';
import {IVault} from 'src/Interfaces/IVault.sol';
import {IERC20} from 'src/Interfaces/IERC20.sol';
import {IWETH} from 'src/Interfaces/IWETH.sol';
import {Constants} from 'test/Constants.sol';

contract SSMTest is Test {

    stkSWIV SSM;

    ERC20 BAL = ERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IVault Vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ERC20 LPT = ERC20(0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56);
    IWETH WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    bytes32 poolID = 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;
    uint256 startingBalance = 1923.29 * 2 * 1e18;

function getMappingValue(address targetContract, uint256 mapSlot, address key) public view returns (uint256) {
        bytes32 slotValue = vm.load(targetContract, keccak256(abi.encode(key, mapSlot)));
            return uint256(slotValue);
    }

    function setUp() public {
        // Deploy new SSM contract
        SSM = new stkSWIV(BAL, Vault, LPT, poolID);

    //     deal(address(SSM), 0x7111F9Aeb2C1b9344EC274780dc9e3806bdc60Ef, 3732466346253321461382700026891);
    //     deal(address(LPT), address(SSM), 3732466346253);
    //     deal(0x7111F9Aeb2C1b9344EC274780dc9e3806bdc60Ef, 10000 ether);

    //     // Approve SSM to spend BAL Tokens and LPT
    //     vm.startPrank(0x7111F9Aeb2C1b9344EC274780dc9e3806bdc60Ef);
    //     BAL.approve(address(SSM), type(uint256).max-1);
    //     LPT.approve(address(SSM), type(uint256).max-1);
    //     vm.stopPrank();
    // }

        // Deal BAL and LPT balances to key addresses
        deal(address(BAL), Constants.userPublicKey, startingBalance);
        deal(address(LPT), Constants.userPublicKey, startingBalance);
        deal(Constants.userPublicKey, 10000 ether);

        // Approve SSM to spend BAL Tokens and LPT
        vm.startPrank(Constants.userPublicKey);
        BAL.approve(address(SSM), type(uint256).max-1);
        LPT.approve(address(SSM), type(uint256).max-1);
        vm.stopPrank();
    }

    function testDeal() public {
        assertEq(BAL.balanceOf(Constants.userPublicKey), startingBalance);
        assertEq(BAL.allowance(Constants.userPublicKey, address(SSM)), type(uint256).max-1);
        assertEq(LPT.allowance(Constants.userPublicKey, address(SSM)), type(uint256).max-1);
    }

    function testFirstDeposit() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), amount);
        assertEq(SSM.balanceOf(Constants.userPublicKey), amount*1e18);
        assertEq(SSM.totalSupply(), amount*1e18);
    }

    function testFirstMint() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.mint(amount*1e18, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), amount);
        assertEq(SSM.balanceOf(Constants.userPublicKey), amount*1e18);
        assertEq(SSM.totalSupply(), amount*1e18);
    }

    function testCooldown() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount*1e18);
        assertEq(SSM.cooldownTime(Constants.userPublicKey), block.timestamp + SSM.cooldownLength());
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), amount*1e18);
    }

    function testImmediateWithdrawal() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount*1e18);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance);
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }

    function testImmediateRedeem() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance*1e18 / 2;
        SSM.mint(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        SSM.redeem(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance);
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }

    function testEventualWithdraw() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        (uint256 sharesMinted) = SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount*1e18);
        LPT.transfer(address(SSM), amount);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        (uint256 shares) = SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance/2);
        assertApproxEqRel(SSM.balanceOf(Constants.userPublicKey), sharesMinted/2, 0.0005e18);
    }

    function testEventualRedeem() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance*1e18 / 2;
        SSM.mint(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        uint256 donationAmount = startingBalance/4;
        LPT.transfer(address(SSM), donationAmount);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        SSM.redeem(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance - 1); // Subtract 1 to account for both precision and 4626 inflation attack prevention
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }

    function testSecondaryDepositWithdraw() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount*1e18/2);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        SSM.withdraw(amount/2, Constants.userPublicKey, Constants.userPublicKey);
        SSM.deposit(amount + amount/2, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), 0);
        assertEq(SSM.balanceOf(Constants.userPublicKey), startingBalance*1e18);
    }

    function testSecondaryMintRedeem() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = (startingBalance*1e18) / 2;
        SSM.mint(amount, Constants.userPublicKey);
        SSM.cooldown(amount/2);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        SSM.redeem(amount/2, Constants.userPublicKey, Constants.userPublicKey);
        SSM.mint(amount + amount/2, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), 0);
        assertEq(SSM.balanceOf(Constants.userPublicKey), startingBalance*1e18);
    }
    
    function testPause() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount*1e18);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        vm.stopPrank();
        SSM.pause(true);
        vm.startPrank(Constants.userPublicKey);
        vm.expectRevert(bytes("Paused"));
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
    }

    function testCooldownTooShort() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount*1e18);
        vm.warp(block.timestamp + SSM.cooldownLength() - 100);
        vm.expectRevert();
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
    }

    function testCooldownNotEnough() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount*1e18-1);
        vm.warp(block.timestamp + SSM.cooldownLength());
        vm.expectRevert();
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
    }

    function testWithdrawalWindowLength() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount*1e18);
        vm.warp(block.timestamp + SSM.cooldownLength() + SSM.withdrawalWindow() + 1);
        vm.expectRevert();
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
    }

    function testClearingCooldownTimeOnWithdraw() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        uint256 minted = SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount*1e18);
        assertEq(SSM.cooldownTime(Constants.userPublicKey), block.timestamp + SSM.cooldownLength());
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), amount*1e18);
        vm.warp(block.timestamp + SSM.cooldownLength());
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(SSM.cooldownTime(Constants.userPublicKey), block.timestamp);
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), 0);
    }

    function testClearingCooldownTimeOnRedeem() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = (startingBalance * 1e18) / 2;
        SSM.mint(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        assertEq(SSM.cooldownTime(Constants.userPublicKey), block.timestamp + SSM.cooldownLength());
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), amount);
        vm.warp(block.timestamp + SSM.cooldownLength());
        SSM.redeem(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), 0);
    }

    function testDepositZap() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        uint256 previousLPTBalance = LPT.balanceOf(address(SSM));
        SSM.depositZap{value: 1 ether}(amount, Constants.userPublicKey, 0);
        console.log("LPT Balance: ", LPT.balanceOf(address(SSM)));
        assertGt(LPT.balanceOf(address(SSM)), previousLPTBalance);
        assertEq(BAL.balanceOf(address(SSM)), 0);
        assertEq(WETH.balanceOf(address(SSM)), 0);
    }

    function testMintZap() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = 833211022431743032540000000000000000000;
        uint256 previousLPTBalance = LPT.balanceOf(address(SSM));
        SSM.mintZap{value: 1.1 ether}(amount, Constants.userPublicKey, type(uint256).max);
        assertGe(SSM.balanceOf(address(Constants.userPublicKey)), amount);
        assertGt(LPT.balanceOf(address(SSM)), previousLPTBalance);
        assertEq(LPT.balanceOf(address(SSM)), 908591188526872731418); // only valid for the current block, deprecated for future testing
        assertEq(BAL.balanceOf(address(SSM)), 0);
        assertEq(WETH.balanceOf(address(SSM)), 0);
    }

    function testMintZapTooLittleShares() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = 853211022431743032540000000000000000000;
        uint256 previousLPTBalance = LPT.balanceOf(address(SSM));
        vm.expectRevert();
        SSM.mintZap{value: 1 ether}(amount, Constants.userPublicKey, type(uint256).max); 
    }

    function testRedeemZap() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = 697377559108214882330512;
        (uint256 minBPT,uint256 sharesMinted,) = SSM.mintZap{value: 1 ether}(amount, Constants.userPublicKey, type(uint256).max);
        SSM.cooldown(sharesMinted);
        vm.warp(block.timestamp + SSM.cooldownLength());
        SSM.redeemZap(sharesMinted, payable(Constants.userPublicKey), Constants.userPublicKey, 0, 1 ether);
    }

    function testWithdrawZap() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        uint256 ethAmount = 1 ether;
        (uint256 sharesMinted,,uint256[2] memory balancesSpent) = SSM.depositZap{value: ethAmount}(amount, Constants.userPublicKey, 0);
        uint256 swivDeposited = balancesSpent[0];
        SSM.cooldown(sharesMinted);
        vm.warp(block.timestamp + SSM.cooldownLength());
        uint256 swivWithdrawn = swivDeposited - (swivDeposited*5/10000);
        uint256 ethWithdrawn = ethAmount - (ethAmount*5/10000);
        (uint256 sharesBurnt, ,uint256[2] memory balancesReturned ) = SSM.withdrawZap(swivWithdrawn, ethWithdrawn, payable(Constants.userPublicKey), Constants.userPublicKey, type(uint256).max); 
        assertApproxEqRel(sharesBurnt, sharesMinted, 0.0005e18);
    }

    // function testWithdrawIntegration() public {
        
    //     // Deal BAL and LPT balances to key addresses
    //     vm.startPrank(0x7111F9Aeb2C1b9344EC274780dc9e3806bdc60Ef);
    //     SSM.cooldown(3732466346253321461382700026891);
    //     vm.warp(block.timestamp + SSM.cooldownLength());
    //     console.log("SSM LPT Balance: ", LPT.balanceOf(address(SSM)));
    //     console.log("User SSM Balance: ", SSM.balanceOf(address(0x7111F9Aeb2C1b9344EC274780dc9e3806bdc60Ef)));
    //     uint256 amount = 8678927661945;
    //     uint256 ethAmount = 4518764172;
    //     (uint256 sharesBurnt, ,uint256[2] memory balancesReturned ) = SSM.withdrawZap(amount, ethAmount, payable(0x7111F9Aeb2C1b9344EC274780dc9e3806bdc60Ef), 
    //                                                                                     0x7111F9Aeb2C1b9344EC274780dc9e3806bdc60Ef, 3741797512118);
    //     console.log ("Shares Burnt: ",sharesBurnt);
    //     console.log ("Swiv Burnt: ", balancesReturned[0]); 
    //     assertEq(balancesReturned[0], 867892766194666666);
    // }

    function testExitQueries() public {

        IQuery balancerQuery = IQuery(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);

        IAsset[] memory assetData = new IAsset[](2);
        assetData[0] = IAsset(address(0xba100000625a3754423978a60c9317c58a424e3D));
        assetData[1] = IAsset(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

        uint256[] memory amountData = new uint256[](2);
        amountData[0] = 8678927661945;
        amountData[1] = 4518764172;

        IVault.ExitPoolRequest memory requestData = IVault.ExitPoolRequest({
                    assets: assetData,
                    minAmountsOut: amountData,
                    userData: abi.encode(1, 3732466346253),
                    toInternalBalance: false
                });

        // Query the pool join to get the bpt out
        (uint256 bptOutFE, uint256[] memory amountsInFE) = balancerQuery.queryExit(0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014, address(this), address(this), requestData);

        amountData = amountsInFE;

        requestData = IVault.ExitPoolRequest({
            assets: assetData,
            minAmountsOut: amountData,
            userData: abi.encode(2, amountData, type(uint256).max),
            toInternalBalance: false
        });
        // Query the pool exit to get the amounts out
        (uint256 bptOutContract, uint256[] memory amountsOutContract) = balancerQuery.queryExit(0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014, address(this), address(this), requestData);

        console.log("bpt from exit w/ bptOut (FE derived): ", bptOutFE);
        console.log("amounts from  exit w/ bptOut (FE derived):", amountsInFE[0], amountsInFE[1]);
        console.log("bpt from exit w/ amounts generated:", bptOutContract);
        console.log("amounts from exit w/ amounts generated: ", amountsOutContract[0], amountsOutContract[1]);

        // assertEq(true, false);
    }

    // function testJoinQueries() public {
    //     IQuery balancerQuery = IQuery(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);

    //     IAsset[] memory assetData = new IAsset[](2);
    //     assetData[0] = IAsset(address(0xba100000625a3754423978a60c9317c58a424e3D));
    //     assetData[1] = IAsset(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    //     uint256[] memory amountData = new uint256[](2);
    //     amountData[0] = 8678927661945;
    //     amountData[1] = 4518764172;

    //     // IVault.JoinPoolRequest memory requestData = IVault.JoinPoolRequest({
    //     //     assets: assetData,
    //     //     maxAmountsIn: amountData,
    //     //     userData: abi.encode(1, amountData, 0),
    //     //     fromInternalBalance: false
    //     // });

    //     // // Query the pool join to get the amountsIn
    //     // (uint256 bptOutFE, uint256[] memory amountsInFE) = balancerQuery.queryJoin(0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014, address(this), address(this), requestData);

    //     // console.log("bptOut from join w/ bpt amount: ", bptOutFE);
    //     // console.log("amounts from join w/ bpt amount: ", amountsInFE[0], amountsInFE[1]);

    //     // amountData = amountsInFE;

    //     IVault.JoinPoolRequest memory requestData = IVault.JoinPoolRequest({
    //         assets: assetData,
    //         maxAmountsIn: amountData,
    //         userData: abi.encode(1,  3448318886742),
    //         fromInternalBalance: false
    //     });

    //     // Query the pool join to get the bpt out
    //     (uint256 bptOutContract, uint256[] memory amountsOutContract) = balancerQuery.queryJoin(0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014, address(this), address(this), requestData);

    //     console.log("bptOut from join w/ generated bpt amount: ", bptOutContract);
    //     console.log("amounts from join w/ generated bpt amount: ", amountsOutContract[0], amountsOutContract[1]);

    //     // assertEq(true, false);
    // }
}
