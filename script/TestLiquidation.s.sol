// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FlashLiquidations} from "../src/flashLiquidations.sol";
import {IPoolAddressesProvider} from "../lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@aave/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {AaveOracle} from "@aave/contracts/misc/AaveOracle.sol";
import {Script} from "forge-std/Script.sol";

contract LiquidationTest is Script {
    FlashLiquidations public liquidation;

    address constant AAVE_ADDRESSES_PROVIDER = 0x5ccF60c7E10547c5389E9cBFf543E5D0Db9F4feC;
    address public constant AAVE_ORACLE = 0xeCF313dE38aA85EF618D06D1A602bAa917D62525;
    address constant SWAP_ROUTER = 0xE67B7D039b78DE25367EF5E69596075Bbd852BA9;
    address public constant USDC = 0x796Ea11Fa2dD751eD01b53C372fFDB4AAa8f00F9;
    address public constant WETH = 0xfc24f770F94edBca6D6f885E12d4317320BcB401;
    address public constant WXTZ = 0xc9B53AB2679f573e480d01e0f49e2B5CFB7a3EAb;
    IPool public constant POOL = IPool(0x3bD16D195786fb2F509f2E2D7F69920262EF114D);
    uint256 mainnetFork;
    address public userToLiquidate;

    function run() public {
        mainnetFork = vm.createFork("https://node.mainnet.etherlink.com");
        vm.selectFork(mainnetFork);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        userToLiquidate = 0x1Aa5d50fDF8544Cace0DFBBe4ACb100780C8E5f8;
        liquidation = FlashLiquidations(0xd6f28DbAad70cBB3F8Df1447e58C0b99aB71E100);
        // Check initial health factor
        (,,,,, uint256 healthFactor) = POOL.getUserAccountData(userToLiquidate);
        console.log("Health factor :", healthFactor);

        // Execute flash loan liquidation
        uint256 debtToCover = 0.000072 * 1e6; // Liquidate 1000 USDC worth of debt

        liquidation.flashLoan(
            USDC, // token to flash loan
            debtToCover, // amount to flash loan
            WETH, // collateral token
            userToLiquidate, // user to liquidate
            500, // pool fee 1
            500, // pool fee 2
            WXTZ, // path token (not used in this case)
            true // use path
        );
        vm.stopBroadcast();
        // Verify liquidation was successful
        (,,,,, uint256 healthFactorFinal) = POOL.getUserAccountData(userToLiquidate);
        console.log("Health factor after liquidation:", healthFactorFinal);

        // Check liquidator received collateral
        uint256 liquidatorWethBalance = IERC20(WETH).balanceOf(address(this));
        console.log("Liquidator WETH balance:", liquidatorWethBalance);
    }
}
