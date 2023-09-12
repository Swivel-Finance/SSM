// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import "forge-std/console.sol";


import {stkSWIV} from 'src/stkSWIV.sol';
import {ERC20} from 'src/ERC/SolmateERC20.sol';
import {IVault} from 'src/Interfaces/IVault.sol';
import {IERC20} from 'src/Interfaces/IERC20.sol';

import {Constants} from 'test/Constants.sol';

contract SSMTest is Test {

    stkSWIV SSM;

    ERC20 BAL = ERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IVault Vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ERC20 LPT = ERC20(0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56);
    bytes32 poolID = 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;
    uint256 startingBalance = 1923.29 * 2 * 1e18;

function getMappingValue(address targetContract, uint256 mapSlot, address key) public view returns (uint256) {
        bytes32 slotValue = vm.load(targetContract, keccak256(abi.encode(key, mapSlot)));
            return uint256(slotValue);
    }


    function setUp() public {

        // Deploy new SSM contract
        SSM = new stkSWIV(BAL, Vault, LPT, poolID);

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
    }

    function testFirstMint() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.mint(amount*1e18, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), amount);
        assertEq(SSM.balanceOf(Constants.userPublicKey), amount*1e18);
    }

    function testCooldown() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);

        SSM.cooldown(amount);
        assertEq(SSM.cooldownTime(Constants.userPublicKey), block.timestamp + SSM.cooldownLength());
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), amount*1e18);
    }

    function testImmediateWithdrawal() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance);
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }

    function testImmediateRedeem() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        SSM.redeem(amount*1e18, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance);
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }

    function testEventualWithdraw() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        LPT.transfer(address(SSM), amount);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        SSM.redeem(amount*1e18, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance - 1); // -1 to account for donation rounding caused by 4626 inflation prevention
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }

    function testEventualRedeem() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        LPT.transfer(address(SSM), amount);
        vm.warp(block.timestamp+ SSM.cooldownLength());
        SSM.redeem(amount*1e18, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance - 1); // -1 to account for donation rounding caused by 4626 inflation prevention
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }

    function testSecondaryDepositWithdraw() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount/2);
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
        SSM.cooldown(amount/1e18/2);
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
        SSM.cooldown(amount);
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
        SSM.cooldown(amount);
        vm.warp(block.timestamp + SSM.cooldownLength() - 100);
        vm.expectRevert();
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
    }

    function testCooldownNotEnough() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount-1);
        vm.warp(block.timestamp + SSM.cooldownLength());
        vm.expectRevert();
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
    }

    function testWithdrawalWindowLength() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        vm.warp(block.timestamp + SSM.cooldownLength() + SSM.withdrawalWindow() + 1);
        vm.expectRevert();
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
    }

    function testClearingCooldownTimeOnWithdraw() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);

        SSM.cooldown(amount);
        assertEq(SSM.cooldownTime(Constants.userPublicKey), block.timestamp + SSM.cooldownLength());
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), amount*1e18);
        vm.warp(block.timestamp + SSM.cooldownLength());

        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(SSM.cooldownTime(Constants.userPublicKey), 0);
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), 0);
    }

    function testClearingCooldownTimeOnRedeem() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = (startingBalance * 1e18) / 2;
        SSM.mint(amount, Constants.userPublicKey);

        SSM.cooldown(amount/1e18);
        assertEq(SSM.cooldownTime(Constants.userPublicKey), block.timestamp + SSM.cooldownLength());
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), amount);
        vm.warp(block.timestamp + SSM.cooldownLength());

        SSM.redeem(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(SSM.cooldownTime(Constants.userPublicKey), 0);
        assertEq(SSM.cooldownAmount(Constants.userPublicKey), 0);
    }

    function testDepositZap() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
<<<<<<< Updated upstream
        SSM.depositZap{value: 1 ether}(amount, Constants.userPublicKey);
        // assertEq(LPT.balanceOf(Constants.userPublicKey), amount);
        // assertEq(SSM.balanceOf(Constants.userPublicKey), amount*1e18);
=======
        uint256 previousLPTBalance = LPT.balanceOf(address(SSM));
        SSM.depositZap{value: 1 ether}(amount, Constants.userPublicKey, 0);
        console.log("LPT Balance: ", LPT.balanceOf(address(SSM)));
        assertGt(LPT.balanceOf(address(SSM)), previousLPTBalance);
        assertEq(BAL.balanceOf(address(SSM)), 0);
        assertEq(BAL.balanceOf(address(WETH)), 0);
    }

    function testMintZap() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = 833211022431743032540000000000000000000;
        uint256 previousLPTBalance = LPT.balanceOf(address(SSM));
        SSM.mintZap{value: 1 ether}(amount, Constants.userPublicKey);
        assertGe(SSM.balanceOf(address(Constants.userPublicKey)), amount);
        console.log("LPT Balance: ", LPT.balanceOf(address(SSM)));
        assertGt(LPT.balanceOf(address(SSM)), previousLPTBalance);
        assertEq(BAL.balanceOf(address(SSM)), 0);
        assertEq(BAL.balanceOf(address(WETH)), 0);
    }

    function testMintZapTooLittleShares() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = 853211022431743032540000000000000000001;
        uint256 previousLPTBalance = LPT.balanceOf(address(SSM));
        vm.expectRevert();
        SSM.mintZap{value: 1 ether}(amount, Constants.userPublicKey); 
    }

    function testRedeemZap() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = 697377559108214882330512;
        (uint256 minBPT,uint256 sharesMinted) = SSM.mintZap{value: 1 ether}(amount, Constants.userPublicKey);
        SSM.cooldown(sharesMinted);
        vm.warp(block.timestamp + SSM.cooldownLength());
        SSM.redeemZap(sharesMinted, payable(Constants.userPublicKey), Constants.userPublicKey);
    }

    function testWithdrawZap() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        uint256 ethAmount = 1 ether;
        (uint256 sharesMinted, ,uint256[2] memory balancesSpent) = SSM.depositZap{value: ethAmount}(amount, Constants.userPublicKey, 0);
        uint256 swivDeposited = balancesSpent[0];
        console.log("Shares Minted: ", sharesMinted);
        console.log("Swiv Deposited: ", swivDeposited);
        SSM.cooldown(sharesMinted);
        vm.warp(block.timestamp + SSM.cooldownLength());
        uint256 swivWithdrawn = swivDeposited - (swivDeposited*5/10000);
        uint256 ethWithdrawn = ethAmount - (ethAmount*5/10000);
        (uint256 sharesBurnt, ,uint256[2] memory balancesReturned ) = SSM.withdrawZap(swivWithdrawn, ethWithdrawn, payable(Constants.userPublicKey), Constants.userPublicKey, type(uint256).max); 
        assertApproxEqRel(SSM.convertToShares(853211022431743032540), SSM.convertToShares(853282338599770425535),0.005e18);
>>>>>>> Stashed changes
    }
}
