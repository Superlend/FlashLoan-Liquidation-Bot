// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FlashLiquidations, LiquidationParams} from "../src/flashLiquidations.sol";

contract LiquidationTest is Test {
    FlashLiquidations public liquidation;

    address constant AAVE_ADDRESSES_PROVIDER = 0x5ccF60c7E10547c5389E9cBFf543E5D0Db9F4feC;
    address constant SWAP_ROUTER = 0xE67B7D039b78DE25367EF5E69596075Bbd852BA9;
    function setUp() public {
        
        mainnetFork = vm.createFork("https://node.mainnet.etherlink.com");
        vm.selectFork(mainnetFork);



        liquidation = new FlashLiquidations(AAVE_ADDRESSES_PROVIDER, SWAP_ROUTER);
    }

    function test_Liquidation() public {
        LiquidationParams memory params = LiquidationParams({
            tokenAddress: 0x6982508145454ce325ddbe47a25d4ec6d4baf8d8,
            amount: 1000000000000000000000000,
            colToken: 0x6982508145454ce325ddbe47a25d4ec6d4baf8d8,
            user: address(this),
            decimals: 18,
            poolFee1: 3000,
            poolFee2: 3000,
            pathToken: 0x6982508145454ce325ddbe47a25d4ec6d4baf8d8,
            usePath: true
        });
        liquidation.flashLoan(params);
    }

}
