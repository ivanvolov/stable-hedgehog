// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMTestBase} from "@test/core/ALMTestBase.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {ALM} from "@src/ALM.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {AaveLendingAdapter} from "@src/core/AaveLendingAdapter.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IALM} from "@src/interfaces/IALM.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ALMTest is ALMTestBase {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        uint256 mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_955_703);

        deployFreshManagerAndRouters();

        create_accounts_and_tokens();
        init_hook();
        approve_accounts();
    }

    uint256 amountToDep = 1000 * 1e6;

    function test_deposit() public {
        deal(address(USDC), address(alice.addr), amountToDep);
        assertEq(hook.TVL(), 0);
        assertEq(hook.liquidity(), 0);
        assertApproxEqAbs(USDC.balanceOf(alice.addr), amountToDep, 1e10);

        vm.prank(alice.addr);
        hook.deposit(alice.addr, amountToDep);

        assertApproxEqAbs(USDC.balanceOf(alice.addr), 0, 1e10);
        assertApproxEqAbs(hook.balanceOf(alice.addr), amountToDep, 1e10);
        assertEq(hook.TVL(), 996756823);
        assertEq(hook.liquidity(), 18529565944);

        assertApproxEqAbs(lendingAdapter.getCollateral(), 2998556822, 10);
        assertApproxEqAbs(lendingAdapter.getBorrowed(), 2001267479, 10);
    }

    function test_swap_price_up_in() public {
        uint256 usdcToSwap = 100 * 1e6;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwap);
        assertEqBalanceState(swapper.addr, 0, usdcToSwap);

        (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
        assertApproxEqAbs(deltaUSDT, 99 * 1e6, 1e6);

        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertApproxEqAbs(lendingAdapter.getCollateral(), 3098556823, 10);
        assertApproxEqAbs(lendingAdapter.getBorrowed(), 2100730696, 10);

        assertEq(hook.sqrtPriceCurrent(), 78802880669457038464881639888);
    }

    function test_swap_price_up_out() public {
        uint256 usdcToSwapQ = 100542606; // this should be get from quoter
        uint256 usdtToGetFSwap = 100 * 1e6;
        test_deposit();

        deal(address(USDC), address(swapper.addr), usdcToSwapQ);
        assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

        (, uint256 deltaUSDT) = swapUSDC_USDT_Out(usdtToGetFSwap);
        assertApproxEqAbs(deltaUSDT, usdtToGetFSwap, 1e1);

        assertEqBalanceState(swapper.addr, deltaUSDT, 0);
        assertEqBalanceState(address(hook), 0, 0);

        assertApproxEqAbs(lendingAdapter.getCollateral(), 3099099428, 10);
        assertApproxEqAbs(lendingAdapter.getBorrowed(), 2101267478, 10);

        assertEq(hook.sqrtPriceCurrent(), 78800585512440833154126931954);
    }

    function test_swap_price_down_in() public {
        uint256 usdtToSwap = 100 * 1e6;
        test_deposit();

        deal(address(USDT), address(swapper.addr), usdtToSwap);
        assertEqBalanceState(swapper.addr, usdtToSwap, 0);

        (uint256 deltaUSDC, ) = swapUSDT_USDC_In(usdtToSwap);
        // assertEq(deltaUSDC, 4257016319);

        // assertEqBalanceState(swapper.addr, 0, deltaUSDC);
        // assertEqBalanceState(address(hook), 0, 0);

        // assertEqMorphoA(shortMId, 0, 0, 0);
        // assertEqMorphoA(longMId, 0, deltaUSDC, amountToDep + usdtToSwap);

        // assertEq(hook.sqrtPriceCurrent(), 1184338667228746981679537543072454);
    }

    // function test_swap_price_down_out() public {
    //     uint256 usdtToSwapQ = 1048539297596844510; // this should be get from quoter
    //     uint256 usdcToGetFSwap = 4486999802;
    //     test_deposit();

    //     deal(address(USDT), address(swapper.addr), usdtToSwapQ);
    //     assertEqBalanceState(swapper.addr, usdtToSwapQ, 0);

    //     (uint256 deltaUSDC, ) = swapUSDT_USDC_Out(usdcToGetFSwap);
    //     assertEq(deltaUSDC, usdcToGetFSwap);

    //     assertEqBalanceState(swapper.addr, 0, deltaUSDC);
    //     assertEqBalanceState(address(hook), 0, 0);

    //     assertEqMorphoA(shortMId, 0, 0, 0);
    //     assertEqMorphoA(longMId, 0, deltaUSDC, amountToDep + usdtToSwapQ);

    //     assertEq(hook.sqrtPriceCurrent(), 1181128042874516412352801494904863);
    // }

    function test_accessability() public {
        vm.expectRevert(SafeCallback.NotPoolManager.selector);
        hook.afterInitialize(address(0), key, 0, 0, "");

        vm.expectRevert(IALM.AddLiquidityThroughHook.selector);
        hook.beforeAddLiquidity(address(0), key, IPoolManager.ModifyLiquidityParams(0, 0, 0, ""), "");

        PoolKey memory failedKey = key;
        failedKey.tickSpacing = 3;

        vm.expectRevert();
        hook.beforeAddLiquidity(address(0), failedKey, IPoolManager.ModifyLiquidityParams(0, 0, 0, ""), "");

        vm.expectRevert();
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");

        vm.expectRevert();
        hook.beforeSwap(address(0), failedKey, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_pause() public {
        vm.prank(deployer.addr);
        hook.setPaused(true);

        vm.expectRevert(IALM.ContractPaused.selector);
        hook.deposit(address(0), 0);

        vm.prank(address(manager));
        vm.expectRevert(IALM.ContractPaused.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }

    function test_shutdown() public {
        vm.prank(deployer.addr);
        hook.setShutdown(true);

        vm.expectRevert(IALM.ContractShutdown.selector);
        hook.deposit(deployer.addr, 0);

        vm.prank(address(manager));
        vm.expectRevert(IALM.ContractShutdown.selector);
        hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    }
}
