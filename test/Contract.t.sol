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

    uint256 startingBalance = 100000000000000000000000;

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
        BAL.approve(address(SSM), type(uint256).max);
        LPT.approve(address(SSM), type(uint256).max);
        vm.stopPrank();
    }

    function testDeal() public {
        assertEq(BAL.balanceOf(Constants.userPublicKey), startingBalance);
        assertEq(BAL.allowance(Constants.userPublicKey, address(SSM)), type(uint256).max);
        assertEq(LPT.allowance(Constants.userPublicKey, address(SSM)), type(uint256).max);
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
        vm.warp(block.timestamp+ SSM.cooldownLength() + 1);
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance);
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }

    function testImmediateRedeem() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        vm.warp(block.timestamp+ SSM.cooldownLength() + 1);
        SSM.redeem(amount*1e18, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance);
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }

    function testDepositAfterDonation() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        vm.warp(block.timestamp+ SSM.cooldownLength() + 1);
        SSM.withdraw(amount, Constants.userPublicKey, Constants.userPublicKey);
        SSM.deposit(amount, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), amount);
        assertEq(SSM.balanceOf(Constants.userPublicKey), amount*1e18);
    }

    function testEventualWithdraw() public {
        vm.startPrank(Constants.userPublicKey);
        uint256 amount = startingBalance / 2;
        SSM.deposit(amount, Constants.userPublicKey);
        SSM.cooldown(amount);
        LPT.transfer(address(SSM), amount);
        vm.warp(block.timestamp+ SSM.cooldownLength() + 1);
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
        vm.warp(block.timestamp+ SSM.cooldownLength() + 1);
        SSM.redeem(amount*1e18, Constants.userPublicKey, Constants.userPublicKey);
        assertEq(LPT.balanceOf(Constants.userPublicKey), startingBalance - 1); // -1 to account for donation rounding caused by 4626 inflation prevention
        assertEq(SSM.balanceOf(Constants.userPublicKey), 0);
    }
}
