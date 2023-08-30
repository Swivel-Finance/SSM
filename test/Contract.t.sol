// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
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


    function setUp() public {

        // Deploy new SSM contract
        SSM = new stkSWIV(BAL, Vault, LPT, poolID);

        // Deal balance to key addresses
        deal(Constants.USDC, Constants.userPublicKey, startingBalance);

        // Approve SSM to spend BAL Tokens and LPT
        vm.startPrank(Constants.userPublicKey);
        BAL.approve(address(SSM), type(uint256).max);
        LPT.approve(address(SSM), type(uint256).max);
        vm.stopPrank();
    }

    function testExample() public {
        assertTrue(true);
        console.log(BAL.balanceOf(Constants.userPublicKey));
    }
}
