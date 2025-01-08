// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FlashLiquidations} from "../src/flashLiquidations.sol";
import {IPoolAddressesProvider} from "../lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {ISwapRouter} from "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@aave/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {AaveOracle} from "@aave/contracts/misc/AaveOracle.sol";

contract LiquidationTest is Test {
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

    function setUp() public {
        mainnetFork = vm.createFork("https://node.mainnet.etherlink.com");
        vm.selectFork(mainnetFork);

        userToLiquidate = makeAddr("borrower");
        vm.deal(userToLiquidate, 100 ether);

        liquidation = new FlashLiquidations(IPoolAddressesProvider(AAVE_ADDRESSES_PROVIDER), ISwapRouter(SWAP_ROUTER));

        deal(WETH, userToLiquidate, 20 ether);
        deal(USDC, userToLiquidate, 10_000 * 1e6);

        vm.startPrank(userToLiquidate);

        // Approve AAVE pool to spend tokens
        IERC20(WETH).approve(address(POOL), type(uint256).max);
        IERC20(USDC).approve(address(POOL), type(uint256).max);

        // Supply collateral (WETH)
        POOL.supply(WETH, 1 ether, userToLiquidate, 0);

        // Borrow USDC against the WETH collateral
        POOL.borrow(USDC, 1000 * 1e6, 2, 0, userToLiquidate);

        vm.stopPrank();
    }

    function test_CreateLiquidatablePosition() public {
        // Check initial health factor
        (,,,,, uint256 healthFactorBefore) = POOL.getUserAccountData(userToLiquidate);
        console.log("Health factor before:", healthFactorBefore);

        // Manipulate WETH price down to make position liquidatable
        // Original price might be around 2000 USD, we'll drop it by 50%
        vm.mockCall(
            AAVE_ORACLE,
            abi.encodeWithSelector(AaveOracle.getAssetPrice.selector, WETH),
            abi.encode(1000 * 1e8) // $1000 per ETH
        );

        // Check new health factor
        (,,,,, uint256 healthFactorAfter) = POOL.getUserAccountData(userToLiquidate);
        console.log("Health factor after:", healthFactorAfter);

        // Verify position is now liquidatable
        assertTrue(healthFactorAfter < 1e18, "Position should be liquidatable");

        // Execute flash loan liquidation
        uint256 debtToCover = 500 * 1e6; // Liquidate 1000 USDC worth of debt

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

        // Verify liquidation was successful
        (,,,,, uint256 healthFactorFinal) = POOL.getUserAccountData(userToLiquidate);
        console.log("Health factor after liquidation:", healthFactorFinal);

        // Check liquidator received collateral
        uint256 liquidatorWethBalance = IERC20(WETH).balanceOf(address(this));
        console.log("Liquidator WETH balance:", liquidatorWethBalance);
        assertTrue(liquidatorWethBalance > 0, "Liquidator should have received WETH");
    }

    // Helper function to check user's position
    function _logUserPosition(address user) internal view {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = POOL.getUserAccountData(user);

        console.log("Total Collateral:", totalCollateralBase);
        console.log("Total Debt:", totalDebtBase);
        console.log("Available Borrows:", availableBorrowsBase);
        console.log("Liquidation Threshold:", currentLiquidationThreshold);
        console.log("LTV:", ltv);
        console.log("Health Factor:", healthFactor);
    }
}
