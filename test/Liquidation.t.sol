// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FlashLiquidations} from "../src/flashLiquidations.sol";
import {IPoolAddressesProvider} from "../lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract LiquidationTest is Test {
    FlashLiquidations public liquidation;

    address constant AAVE_ADDRESSES_PROVIDER = 0x5ccF60c7E10547c5389E9cBFf543E5D0Db9F4feC;
    address constant SWAP_ROUTER = 0xE67B7D039b78DE25367EF5E69596075Bbd852BA9;
    uint256 mainnetFork;

    function setUp() public {
        mainnetFork = vm.createFork("https://node.mainnet.etherlink.com");
        vm.selectFork(mainnetFork);

        liquidation = new FlashLiquidations(IPoolAddressesProvider(AAVE_ADDRESSES_PROVIDER), ISwapRouter(SWAP_ROUTER));
    }

    function test_Liquidation() public {
        liquidation.flashLoan({
            tokenAddress: 0x6982508145454ce325dDbe47a25D4eC6D4BaF8d8,
            _amount: 1000000000000000000000000,
            colToken: 0x6982508145454ce325dDbe47a25D4eC6D4BaF8d8,
            user: address(this),
            decimals: 18,
            poolFee1: 3000,
            poolFee2: 3000,
            pathToken: 0x6982508145454ce325dDbe47a25D4eC6D4BaF8d8,
            usePath: false
        });
    }
}
