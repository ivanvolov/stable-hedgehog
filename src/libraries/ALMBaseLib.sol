// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ISwapRouter} from "@forks/ISwapRouter.sol";
import {IUniswapV3Pool} from "@forks/IUniswapV3Pool.sol";

library ALMBaseLib {
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint24 public constant USDT_USDC_POOL_FEE = 100;

    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter constant swapRouter = ISwapRouter(SWAP_ROUTER);

    function swapExactInput(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
        return
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: USDT_USDC_POOL_FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    function swapExactOutput(address tokenIn, address tokenOut, uint256 amountOut) internal returns (uint256) {
        // return
        //     swapRouter.exactOutputSingle(
        //         ISwapRouter.ExactOutputSingleParams({
        //             tokenIn: tokenIn,
        //             tokenOut: tokenOut,
        //             fee: ETH_USDC_POOL_FEE,
        //             recipient: address(this),
        //             deadline: block.timestamp,
        //             amountInMaximum: type(uint256).max,
        //             amountOut: amountOut,
        //             sqrtPriceLimitX96: 0
        //         })
        //     );
    }
}
