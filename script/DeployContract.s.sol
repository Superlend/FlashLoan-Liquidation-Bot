// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlashLiquidations} from "../src/flashLiquidations.sol";
import {IPoolAddressesProvider} from "../lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract DeployContract is Script {
    address constant AAVE_ADDRESSES_PROVIDER = 0x5ccF60c7E10547c5389E9cBFf543E5D0Db9F4feC;
    address constant SWAP_ROUTER = 0xE67B7D039b78DE25367EF5E69596075Bbd852BA9;

    function run() external {
        vm.createSelectFork("etherlink");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        FlashLiquidations flashLiquidations =
            new FlashLiquidations(IPoolAddressesProvider(AAVE_ADDRESSES_PROVIDER), ISwapRouter(SWAP_ROUTER));
        console.log("FlashLiquidations deployed at:", address(flashLiquidations));
    }
}
