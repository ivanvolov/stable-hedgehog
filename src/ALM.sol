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
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

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
        refreshReserves();

        // if (params.zeroForOne) {
        //     console.log("> WETH price go up...");
        //     // If user is selling Token 0 and buying Token 1 (USDC => WETH)
        //     // TLDR: Here we got USDC and save it on balance. And just give our ETH back to USER.
        //     (
        //         BeforeSwapDelta beforeSwapDelta,
        //         uint256 wethOut,
        //         uint256 usdcIn,
        //         uint160 sqrtPriceNext
        //     ) = getZeroForOneDeltas(params.amountSpecified);

        //     // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
        //     // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
        //     key.currency0.take(poolManager, address(this), usdcIn, false);
        //     repayAndSupply(usdcIn); // Notice: repaying if needed to reduce lending interest.

        //     // We don't have token 1 on our account yet, so we need to withdraw WETH from the Morpho.
        //     // We also need to create a debit so user could take it back from the PM.
        //     lendingAdapter.removeCollateral(wethOut);
        //     key.currency1.settle(poolManager, address(this), wethOut, false);

        //     sqrtPriceCurrent = sqrtPriceNext;
        //     return beforeSwapDelta;
        // } else {
        //     console.log("> WETH price go down...");
        //     // If user is selling Token 1 and buying Token 0 (WETH => USDC)
        //     // TLDR: Here we borrow USDC at Morpho and give it back.

        //     (
        //         BeforeSwapDelta beforeSwapDelta,
        //         uint256 wethIn,
        //         uint256 usdcOut,
        //         uint160 sqrtPriceNext
        //     ) = getOneForZeroDeltas(params.amountSpecified);

        //     // Put extra WETH to Morpho
        //     key.currency1.take(poolManager, address(this), wethIn, false);
        //     lendingAdapter.addCollateral(wethIn);

        //     // Ensure we have enough USDC. Redeem from reserves and borrow if needed.
        //     redeemAndBorrow(usdcOut);
        //     key.currency0.settle(poolManager, address(this), usdcOut, false);

        //     sqrtPriceCurrent = sqrtPriceNext;
        //     return beforeSwapDelta;
        // }
    }

    // --- Internal and view functions ---

    function getZeroForOneDeltas(
        int256 amountSpecified
    ) internal view returns (BeforeSwapDelta beforeSwapDelta, uint256 wethOut, uint256 usdcIn, uint160 sqrtPriceNext) {
        if (amountSpecified > 0) {
            // console.log("> amount specified positive");
            wethOut = uint256(amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneOut(sqrtPriceCurrent, liquidity, wethOut);

            usdcIn = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(wethOut)), // specified token = token1
                int128(uint128(usdcIn)) // unspecified token = token0
            );
        } else {
            // console.log("> amount specified negative");
            usdcIn = uint256(-amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneIn(sqrtPriceCurrent, liquidity, usdcIn);

            wethOut = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(usdcIn)), // specified token = token0
                -int128(uint128(wethOut)) // unspecified token = token1
            );
        }
    }

    function getOneForZeroDeltas(
        int256 amountSpecified
    ) internal view returns (BeforeSwapDelta beforeSwapDelta, uint256 wethIn, uint256 usdcOut, uint160 sqrtPriceNext) {
        if (amountSpecified > 0) {
            // console.log("> amount specified positive");
            usdcOut = uint256(amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroOut(sqrtPriceCurrent, liquidity, usdcOut);

            wethIn = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(usdcOut)), // specified token = token0
                int128(uint128(wethIn)) // unspecified token = token1
            );
        } else {
            // console.log("> amount specified negative");
            wethIn = uint256(-amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroIn(sqrtPriceCurrent, liquidity, wethIn);

            usdcOut = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(wethIn)), // specified token = token1
                -int128(uint128(usdcOut)) // unspecified token = token0
            );
        }
    }

    function redeemAndBorrow(uint256 usdcOut) internal {
        // uint256 withdrawAmount = ALMMathLib.min(lendingAdapter.getSupplied(), usdcOut);
        // if (withdrawAmount > 0) lendingAdapter.withdraw(withdrawAmount);
        // if (usdcOut > withdrawAmount) lendingAdapter.borrow(usdcOut - withdrawAmount);
    }

    function repayAndSupply(uint256 amountUSDC) internal {
        // uint256 repayAmount = ALMMathLib.min(lendingAdapter.getBorrowed(), amountUSDC);
        // if (repayAmount > 0) lendingAdapter.repay(repayAmount);
        // if (amountUSDC > repayAmount) lendingAdapter.supply(amountUSDC - repayAmount);
    }

    function refreshReserves() public {
        // lendingAdapter.syncLong();
        // lendingAdapter.syncShort();
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

    function sharePrice() public view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (TVL() * 1e18) / totalSupply();
    }

    function _calcCurrentPrice() public view returns (uint256) {
        return ALMMathLib.getPriceFromSqrtPriceX96(sqrtPriceCurrent);
    }

    function getCurrentLiquidity() public view returns (uint128 liquidity) {
        uint256 amount0 = lendingAdapter.getCollateral();
        liquidity = ALMMathLib.getLiquidityFromAmount0SqrtPriceX96(
            ALMMathLib.getSqrtPriceAtTick(tickUpper),
            sqrtPriceCurrent,
            amount0
        );
    }

    function adjustForFeesDown(uint256 amount) public pure returns (uint256) {
        return amount;
    }

    function adjustForFeesUp(uint256 amount) public pure returns (uint256) {
        return amount;
    }
}
