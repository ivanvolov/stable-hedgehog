// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@forks/CurrencySettler.sol";

import {ERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {BaseStrategyHook} from "@src/core/BaseStrategyHook.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC20 {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using SafeERC20 for IERC20;

    constructor(IPoolManager manager) BaseStrategyHook(manager) ERC20("ALM", "stbALM") {
        USDT.forceApprove(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        USDC.forceApprove(ALMBaseLib.SWAP_ROUTER, type(uint256).max);

        USDT.forceApprove(address(LENDING_POOL), type(uint256).max);
        USDC.forceApprove(address(LENDING_POOL), type(uint256).max);
    }

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160 sqrtPrice,
        int24,
        bytes calldata
    ) external override onlyByPoolManager returns (bytes4) {
        console.log("> afterInitialize");
        sqrtPriceCurrent = sqrtPrice;
        _updateBoundaries();
        return ALM.afterInitialize.selector;
    }

    /// @notice  Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    uint256 leverage = 3 ether;
    ILendingPool constant LENDING_POOL = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    function deposit(address to, uint256 amount) external notPaused notShutdown {
        if (amount == 0) revert ZeroLiquidity();
        USDC.transferFrom(msg.sender, address(this), amount);

        uint256 tvl1 = TVL();

        //** flash loan */
        uint256 usdtToFlashLoan = (_USDCtoUSDT(amount) * (leverage - 1 ether)) / 1e18;
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        (assets[0], amounts[0], modes[0]) = (address(USDT), usdtToFlashLoan, 0);
        LENDING_POOL.flashLoan(address(this), assets, amounts, modes, address(this), "", 0);

        uint256 tvl2 = TVL();

        liquidity = getCurrentLiquidity();

        if (tvl1 == 0) {
            _mint(to, tvl2);
        } else {
            uint256 sharesToMint = (totalSupply() * (tvl2 - tvl1)) / tvl1;
            _mint(to, sharesToMint);
        }
    }

    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == address(LENDING_POOL), "M0");

        // ** SWAP USDT => USDC
        ALMBaseLib.swapExactInput(address(USDT), address(USDC), amounts[0]);

        // ** Add collateral USDC
        lendingAdapter.addCollateral(USDC.balanceOf(address(this)));
        console.log("collateral", lendingAdapter.getCollateral() / 1e6);

        // ** Borrow USDT to repay flashloan
        uint256 usdtToBorrow = amounts[0] + premiums[0];
        console.log("want to borrow", usdtToBorrow / 1e6);
        lendingAdapter.borrow(usdtToBorrow);
        return true;
    }

    // --- Swapping logic ---
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override notPaused notShutdown onlyByPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
        return (this.beforeSwap.selector, _beforeSwap(params, key), 0);
    }

    // @Notice: this function is mainly for removing stack too deep error
    function _beforeSwap(
        IPoolManager.SwapParams calldata params,
        PoolKey calldata key
    ) internal returns (BeforeSwapDelta) {
        if (params.zeroForOne) {
            console.log("> USDC->USDT");
            // TLDR: 1) increase USDT debt 2) USDC to collateral

            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 usdtOut,
                uint256 usdcIn,
                uint160 sqrtPriceNext
            ) = getZeroForOneDeltas(params.amountSpecified);

            key.currency0.take(poolManager, address(this), usdcIn, false);
            lendingAdapter.addCollateral(usdcIn);
            // We don't have token 1 on our account yet, so we need to borrow USDT.
            // We also need to create a debit so user could take it back from the PM.
            lendingAdapter.borrow(usdtOut);
            key.currency1.settle(poolManager, address(this), usdtOut, false);
            sqrtPriceCurrent = sqrtPriceNext;
            return beforeSwapDelta;
        } else {
            console.log("> USDT->USDC");
            // TLDR: 1) decrease USDT debt 2) USDC from collateral

            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 usdtIn,
                uint256 usdcOut,
                uint160 sqrtPriceNext
            ) = getOneForZeroDeltas(params.amountSpecified);

            // Repay USDC
            key.currency1.take(poolManager, address(this), usdtIn, false);
            lendingAdapter.repay(usdtIn);

            lendingAdapter.removeCollateral(usdcOut);
            key.currency0.settle(poolManager, address(this), usdcOut, false);
            sqrtPriceCurrent = sqrtPriceNext;
            return beforeSwapDelta;
        }
    }

    // --- Internal and view functions ---

    function getZeroForOneDeltas(
        int256 amountSpecified
    ) internal view returns (BeforeSwapDelta beforeSwapDelta, uint256 usdtOut, uint256 usdcIn, uint160 sqrtPriceNext) {
        if (amountSpecified > 0) {
            // console.log("> amount specified positive");
            usdtOut = uint256(amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneOut(sqrtPriceCurrent, liquidity, usdtOut);

            usdcIn = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(usdtOut)), // specified token = token1
                int128(uint128(usdcIn)) // unspecified token = token0
            );
        } else {
            // console.log("> amount specified negative");
            usdcIn = uint256(-amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneIn(sqrtPriceCurrent, liquidity, usdcIn);

            usdtOut = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(usdcIn)), // specified token = token0
                -int128(uint128(usdtOut)) // unspecified token = token1
            );
        }
    }

    function getOneForZeroDeltas(
        int256 amountSpecified
    ) internal view returns (BeforeSwapDelta beforeSwapDelta, uint256 usdtIn, uint256 usdcOut, uint160 sqrtPriceNext) {
        if (amountSpecified > 0) {
            // console.log("> amount specified positive");
            usdcOut = uint256(amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroOut(sqrtPriceCurrent, liquidity, usdcOut);

            usdtIn = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(usdcOut)), // specified token = token0
                int128(uint128(usdtIn)) // unspecified token = token1
            );
        } else {
            // console.log("> amount specified negative");
            usdtIn = uint256(-amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroIn(sqrtPriceCurrent, liquidity, usdtIn);

            usdcOut = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(usdtIn)), // specified token = token1
                -int128(uint128(usdcOut)) // unspecified token = token0
            );
        }
    }

    // ---- Math functions

    function _USDCtoUSDT(uint256 amount) internal view returns (uint256) {
        return (amount * price()) / 1e18;
    }

    function _USDTtoUSDC(uint256 amount) internal view returns (uint256) {
        return ((amount * 1e18) / price());
    }

    function price() public view returns (uint256) {
        return (lendingAdapter.getAssetPrice(address(USDT)) * 1e18) / lendingAdapter.getAssetPrice(address(USDC));
    }

    function TVL() public view returns (uint256) {
        uint256 usdcColl = lendingAdapter.getCollateral();
        uint256 usdtDebt = lendingAdapter.getBorrowed();
        return usdcColl - _USDTtoUSDC(usdtDebt);
    }

    function getCurrentLiquidity() public view returns (uint128 liquidity) {
        uint256 amount0 = lendingAdapter.getCollateral();
        liquidity = ALMMathLib.getLiquidityFromAmount0SqrtPriceX96(
            ALMMathLib.getSqrtPriceAtTick(tickUpper),
            sqrtPriceCurrent,
            amount0
        );
    }
}
