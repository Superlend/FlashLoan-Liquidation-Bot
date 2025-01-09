// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPool} from "@aave/contracts/interfaces/IPool.sol";
import {IFlashLoanSimpleReceiver} from "@aave/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import {AaveProtocolDataProvider} from "@aave/contracts/misc/AaveProtocolDataProvider.sol";
import {AaveOracle} from "@aave/contracts/misc/AaveOracle.sol";
import {FlashLoanSimpleReceiverBase} from "@aave/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "@aave/contracts/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "@aave/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract FlashLiquidations is FlashLoanSimpleReceiverBase, Ownable {
    /// Parameters used for _liquidateAndSwap and final transfer of funds to owner
    struct LiquidationParams {
        address collateralAsset;
        address borrowedAsset;
        address user;
        uint256 debtToCover;
        uint24 poolFee1;
        uint24 poolFee2;
        address pathToken;
        bool usePath;
    }

    ///Parameters used for liquidation and swap logic
    struct LiquidationCallLocalVars {
        uint256 initFlashBorrowedBalance;
        uint256 diffFlashBorrowedBalance;
        uint256 initCollateralBalance;
        uint256 diffCollateralBalance;
        uint256 flashLoanDebt;
        uint256 soldAmount;
        uint256 remainingTokens;
        uint256 borrowedAssetLeftovers;
    }

    ISwapRouter public immutable swapRouter;

    constructor(IPoolAddressesProvider _addressProvider, ISwapRouter _swapRouter)
        FlashLoanSimpleReceiverBase(_addressProvider)
        Ownable(msg.sender)
    {
        swapRouter = ISwapRouter(_swapRouter);
    }

    /**
     * @notice This function executes the operation after receiving assets in form of Flash loan
     * @dev Must be ensured that contract can return debt + premium
     * @param asset -> the address of flash-borrowed asset
     * @param amount -> the amount of the flash-borrowed asset
     * @param premium -> fee for flashloan
     * @param params -> The byte-encoded params passed when init flashloan
     * @return true if execution of operation seccess, else false
     */
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {
        require(msg.sender == address(POOL), "FlashLiquidations: Caller must be lending pool");

        LiquidationParams memory decodedParams = _decodeParams(params);

        require(asset == decodedParams.borrowedAsset, "FlashLiquidations: Wrong params passed - asset not the same");
        _liquidateAndSwap(
            decodedParams.collateralAsset,
            decodedParams.borrowedAsset,
            decodedParams.user,
            decodedParams.debtToCover,
            decodedParams.poolFee1,
            decodedParams.poolFee2,
            decodedParams.pathToken,
            decodedParams.usePath,
            amount,
            premium
        );
        return true;
    }

    /**
     * @notice Executes the operation of liquidating the debt position after it swaps collateral asset back to asset borrowed via flashloan
     * @dev Pool contract must be approved for operations
     * @param collateralAsset -> Address of asset received from the liquidation
     * @param borrowedAsset -> Address of the asset borrowed via flashloan
     * @param user -> address of the user being liquidated
     * @param debtToCover -> amount of the debt to be liauidated
     * @param poolFee1 -> fee connected to pool
     * @param poolFee2 -> fee connected to pool
     * @param pathToken -> token which in case needs to be swap between two other tokens from the pool
     * @param usePath -> decicion whether to use single or multihop swap
     * @param flashBorrowedAmount -> amount that was borrowed via flashloan
     * @param premium -> fee for taking out flashloan
     */
    function _liquidateAndSwap(
        address collateralAsset,
        address borrowedAsset,
        address user,
        uint256 debtToCover,
        uint24 poolFee1,
        uint24 poolFee2,
        address pathToken,
        bool usePath,
        uint256 flashBorrowedAmount,
        uint256 premium
    ) internal {
        // Approval for router to spend `amountInMaximum` of colateral
        // In prod the max amount should be spend based on oracles or other data sources to acheive better swap
        LiquidationCallLocalVars memory variables;

        // Initial collateral balance
        variables.initCollateralBalance = IERC20(collateralAsset).balanceOf(address(this));

        // Check whether the initial balance of tokens was borrowed
        if (collateralAsset != borrowedAsset) {
            variables.initFlashBorrowedBalance = IERC20(borrowedAsset).balanceOf(address(this));
            variables.borrowedAssetLeftovers = variables.initFlashBorrowedBalance - flashBorrowedAmount;
        }

        // Calculate the amount which will be send back to Aave pool
        variables.flashLoanDebt = flashBorrowedAmount + premium;

        // Approve the pool to liquidate debt position
        require(IERC20(borrowedAsset).approve(address(POOL), debtToCover), "FlashLiquidations: Error while approving");

        // Liquidating the debt possition
        POOL.liquidationCall(collateralAsset, borrowedAsset, user, debtToCover, false);

        // Compare initial collateral balance with collateral balance after liquidation
        uint256 collateralBalanceAfter = IERC20(collateralAsset).balanceOf(address(this));
        variables.diffCollateralBalance = collateralBalanceAfter - variables.initCollateralBalance;

        // Calculate the swap and necessary collateral tokens to repay flashLoan
        if (collateralAsset != borrowedAsset) {
            uint256 flashBorrowedAssetAfter = IERC20(borrowedAsset).balanceOf(address(this));
            variables.diffFlashBorrowedBalance = flashBorrowedAssetAfter - variables.borrowedAssetLeftovers;
            uint256 amountOut = variables.flashLoanDebt - variables.diffFlashBorrowedBalance;

            variables.soldAmount = swapExactOutputSingle(
                collateralAsset,
                borrowedAsset,
                amountOut,
                variables.diffCollateralBalance,
                poolFee1,
                poolFee2,
                pathToken,
                usePath
            );

            // Check for tokens to transfer to contract owner
            variables.remainingTokens = variables.diffCollateralBalance - variables.soldAmount;
        } else {
            variables.remainingTokens = variables.diffCollateralBalance - premium;
        }

        // Approve for flash loan repayment
        IERC20(borrowedAsset).approve(address(POOL), variables.flashLoanDebt);
    }

    /**
     * @notice This function swaps a minimum possible amount of DAI for fixed amount WETH
     * @dev Calling address must approve this contract to spend DAI for this function to succeed will need to approve for slightly higher amount
     * @param amountOut -> exact amount of WETH to receive from the swap
     * @param amountInMaximum -> amount of DAI we want to spend to receive the specified amount of WETH
     * @return amountIn -> amount of DAI accualy spent in swap
     */
    function swapExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMaximum,
        uint24 poolFee1,
        uint24 poolFee2,
        address pathToken,
        bool usePath
    ) internal returns (uint256 amountIn) {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountInMaximum);
        require(
            IERC20(tokenIn).allowance(address(this), address(swapRouter)) == amountInMaximum,
            "FlashLiquidations: error while approving"
        );

        if (usePath == false) {
            ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee1,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            });

            amountIn = swapRouter.exactOutputSingle(params);
        } else {
            ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(tokenOut, poolFee2, pathToken, poolFee1, tokenIn),
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum
            });

            amountIn = swapRouter.exactOutput(params);
        }

        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
        }

        return amountIn;
    }

    /**
     * @notice This func decodes the params obtained from myFlashLoan function
     * @param params -> params encoded in bytes form passed when initialize the flashloan
     * @return LiquidationParams memory struct
     */
    function _decodeParams(bytes memory params) internal pure returns (LiquidationParams memory) {
        (
            address collateralAsset,
            address borrowedAsset,
            address user,
            uint256 debtToCover,
            uint24 poolFee1,
            uint24 poolFee2,
            address pathToken,
            bool usePath
        ) = abi.decode(params, (address, address, address, uint256, uint24, uint24, address, bool));

        return
            LiquidationParams(collateralAsset, borrowedAsset, user, debtToCover, poolFee1, poolFee2, pathToken, usePath);
    }

    /**
     * @notice flashLoan func initialize a flashLoanSimple and passes the parameters needed to liquidate a position than transfers the collateral received to the owner of contract
     * @param tokenAddress -> address of flash loaned token
     * @param _amount -> amount of flash loaned token
     * @param colToken -> address of collateral token received from liquidating the position
     * @param user -> address of the user whose position is being liquidated
     * @param poolFee1 -> fee associated with Pool
     * @param poolFee2 -> fee associated with Pool
     * @param pathToken -> token needed to be swap between tokens
     * @param usePath -> bool to decide between single and multihop swap
     */
    function flashLoan(
        address tokenAddress,
        uint256 _amount,
        address colToken,
        address user,
        uint24 poolFee1,
        uint24 poolFee2,
        address pathToken,
        bool usePath
    ) external onlyOwner {
        address receiverAddress = address(this);
        address asset = tokenAddress;
        uint256 amount = _amount;
        uint16 referralCode = 0;

        bytes memory params = abi.encode(colToken, asset, user, amount, poolFee1, poolFee2, pathToken, usePath);

        // Init flashLoanSimple
        POOL.flashLoanSimple(receiverAddress, asset, amount, params, referralCode);

        // Transfering remaining collateral token after liquidation with flashloan being repaid
        LiquidationParams memory decodedParams = _decodeParams(params);

        // Transfer remaining debt and collateral to msg.sender
        uint256 allBalance = IERC20(decodedParams.collateralAsset).balanceOf(address(this));
        uint256 debtTokensRemaining = IERC20(decodedParams.borrowedAsset).balanceOf(address(this));

        if (debtTokensRemaining > 0) {
            IERC20(decodedParams.borrowedAsset).transfer(msg.sender, debtTokensRemaining);
        }

        IERC20(decodedParams.collateralAsset).transfer(msg.sender, allBalance);
    }
}
