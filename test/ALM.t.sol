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

contract ALMTest is ALMTestBase {
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

    function test_aave_lending_adapter_long() public {
        // ** Enable Alice to call the adapter
        vm.prank(deployer.addr);
        lendingAdapter.addAuthorizedCaller(address(alice.addr));

        // // ** Approve to Morpho
        // vm.startPrank(alice.addr);
        // USDT.approve(address(lendingAdapter), type(uint256).max);
        // USDC.approve(address(lendingAdapter), type(uint256).max);

        // // ** Add collateral
        // uint256 usdtToSupply = 4000 * 1e18;
        // deal(address(USDT), address(alice.addr), usdtToSupply);
        // lendingAdapter.addCollateralLong(usdtToSupply);
        // assertApproxEqAbs(lendingAdapter.getCollateralLong(), usdtToSupply, 1e1);
        // assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        // assertEqBalanceStateZero(alice.addr);

        // // ** Borrow
        // uint256 usdcToBorrow = ((usdtToSupply * 4500) / 1e12) / 2;
        // lendingAdapter.borrowLong(usdcToBorrow);
        // assertApproxEqAbs(lendingAdapter.getCollateralLong(), usdtToSupply, 1e1);
        // assertApproxEqAbs(lendingAdapter.getBorrowedLong(), usdcToBorrow, 1e1);
        // assertEqBalanceState(alice.addr, 0, usdcToBorrow);

        // // ** Repay
        // lendingAdapter.repayLong(usdcToBorrow);
        // assertApproxEqAbs(lendingAdapter.getCollateralLong(), usdtToSupply, 1e1);
        // assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        // assertEqBalanceStateZero(alice.addr);

        // // ** Remove collateral
        // lendingAdapter.removeCollateralLong(usdtToSupply);
        // assertApproxEqAbs(lendingAdapter.getCollateralLong(), 0, 1e1);
        // assertApproxEqAbs(lendingAdapter.getBorrowedLong(), 0, 1e1);
        // assertEqBalanceState(alice.addr, usdtToSupply, 0);

        vm.stopPrank();
    }

    uint256 amountToDep = 100 ether;

    function test_deposit() public {
        // assertEq(hook.TVL(), 0);
        // deal(address(USDT), address(alice.addr), amountToDep);
        // vm.prank(alice.addr);
        // (, uint256 shares) = hook.deposit(alice.addr, amountToDep);
        // assertApproxEqAbs(shares, amountToDep, 1e10);
        // assertEqBalanceStateZero(alice.addr);
        // assertEqBalanceStateZero(address(hook));
        // assertEqMorphoA(longMId, 0, 0, amountToDep);
        // assertEqMorphoA(shortMId, 0, 0, 0);
        // assertEq(hook.sqrtPriceCurrent(), 1182773400228691521900860642689024);
        // assertEq(hook._calcCurrentPrice(), 4486999999999999769339);
        // assertApproxEqAbs(hook.TVL(), amountToDep, 1e10);
    }

    // function test_swap_price_up_in() public {
    //     uint256 usdcToSwap = 4487 * 1e6;
    //     test_deposit();

    //     deal(address(USDC), address(swapper.addr), usdcToSwap);
    //     assertEqBalanceState(swapper.addr, 0, usdcToSwap);

    //     (, uint256 deltaUSDT) = swapUSDC_USDT_In(usdcToSwap);
    //     assertApproxEqAbs(deltaUSDT, 948744443889899008, 1e1);

    //     assertEqBalanceState(swapper.addr, deltaUSDT, 0);
    //     assertEqBalanceState(address(hook), 0, 0);

    //     assertEqMorphoA(shortMId, usdcToSwap, 0, 0);
    //     assertEqMorphoA(longMId, 0, 0, amountToDep - deltaUSDT);

    //     assertEq(hook.sqrtPriceCurrent(), 1181210201945000124313491613764168);
    // }

    // function test_swap_price_up_out() public {
    //     uint256 usdcToSwapQ = 4469867134; // this should be get from quoter
    //     uint256 usdtToGetFSwap = 1 ether;
    //     test_deposit();

    //     deal(address(USDC), address(swapper.addr), usdcToSwapQ);
    //     assertEqBalanceState(swapper.addr, 0, usdcToSwapQ);

    //     (, uint256 deltaUSDT) = swapUSDC_USDT_Out(usdtToGetFSwap);
    //     assertApproxEqAbs(deltaUSDT, 1 ether, 1e1);

    //     assertEqBalanceState(swapper.addr, deltaUSDT, 0);
    //     assertEqBalanceState(address(hook), 0, 0);

    //     assertEqMorphoA(shortMId, usdcToSwapQ, 0, 0);
    //     assertEqMorphoA(longMId, 0, 0, amountToDep - deltaUSDT);

    //     assertEq(hook.sqrtPriceCurrent(), 1184338667228746981679537543072454);
    // }

    // function test_swap_price_down_in() public {
    //     uint256 usdtToSwap = 1 ether;
    //     test_deposit();

    //     deal(address(USDT), address(swapper.addr), usdtToSwap);
    //     assertEqBalanceState(swapper.addr, usdtToSwap, 0);

    //     (uint256 deltaUSDC, ) = swapUSDT_USDC_In(usdtToSwap);
    //     assertEq(deltaUSDC, 4257016319);

    //     assertEqBalanceState(swapper.addr, 0, deltaUSDC);
    //     assertEqBalanceState(address(hook), 0, 0);

    //     assertEqMorphoA(shortMId, 0, 0, 0);
    //     assertEqMorphoA(longMId, 0, deltaUSDC, amountToDep + usdtToSwap);

    //     assertEq(hook.sqrtPriceCurrent(), 1184338667228746981679537543072454);
    // }

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

    // function test_swap_price_down_rebalance() public {
    //     test_swap_price_down_in();

    //     vm.expectRevert();
    //     rebalanceAdapter.rebalance();

    //     vm.prank(deployer.addr);
    //     vm.expectRevert(SRebalanceAdapter.NoRebalanceNeeded.selector);
    //     rebalanceAdapter.rebalance();

    //     // Swap some more
    //     uint256 usdtToSwap = 10 * 1e18;
    //     deal(address(USDT), address(swapper.addr), usdtToSwap);
    //     swapUSDT_USDC_In(usdtToSwap);

    //     assertEq(hook.sqrtPriceCurrent(), 1199991337229301579466306546906758);

    //     assertEqBalanceState(address(hook), 0, 0);
    //     assertEqMorphoA(shortMId, 0, 0, 0);
    //     assertEqMorphoA(longMId, 0, 46216366450, 110999999999999999712);

    //     assertEq(rebalanceAdapter.sqrtPriceLastRebalance(), initialSQRTPrice);

    //     vm.prank(deployer.addr);
    //     rebalanceAdapter.rebalance();

    //     assertEq(rebalanceAdapter.sqrtPriceLastRebalance(), 1199991337229301579466306546906758);

    //     assertEqBalanceState(address(hook), 0, 0);
    //     assertEqMorphoA(shortMId, 0, 0, 0);
    //     assertEqMorphoA(longMId, 0, 0, 98956727267096030628);
    // }

    // function test_swap_price_down_rebalance_withdraw() public {
    //     test_swap_price_down_rebalance();

    //     uint256 shares = hook.balanceOf(alice.addr);
    //     assertEqBalanceStateZero(alice.addr);
    //     assertApproxEqAbs(shares, 100 ether, 1e10);

    //     vm.prank(alice.addr);
    //     hook.withdraw(alice.addr, shares / 2);

    //     assertApproxEqAbs(hook.balanceOf(alice.addr), shares / 2, 1e10);
    //     assertEqBalanceState(alice.addr, 49478363633548016058, 0);
    // }

    // function test_swap_price_down_withdraw() public {
    //     test_swap_price_down_in();

    //     uint256 shares = hook.balanceOf(alice.addr);
    //     assertEqBalanceStateZero(alice.addr);
    //     assertApproxEqAbs(shares, 100 ether, 1e10);

    //     vm.prank(alice.addr);
    //     hook.withdraw(alice.addr, shares / 10);

    //     // assertApproxEqAbs(hook.balanceOf(alice.addr), shares / 2, 1e10);
    //     // assertEqBalanceState(alice.addr, 49478363633548016058, 0);
    // }

    // function test_swap_price_up_withdraw() public {
    //     test_swap_price_up_in();

    //     uint256 shares = hook.balanceOf(alice.addr);
    //     assertEqBalanceStateZero(alice.addr);
    //     assertApproxEqAbs(shares, 100 ether, 1e10);

    //     vm.prank(alice.addr);
    //     hook.withdraw(alice.addr, shares / 2);

    //     assertApproxEqAbs(hook.balanceOf(alice.addr), shares / 2, 1e10);
    //     assertEqBalanceState(alice.addr, 49525627778055050818, 2243500000);
    // }

    // function test_accessability() public {
    //     vm.expectRevert(SafeCallback.NotPoolManager.selector);
    //     hook.afterInitialize(address(0), key, 0, 0, "");

    //     vm.expectRevert(IALM.AddLiquidityThroughHook.selector);
    //     hook.beforeAddLiquidity(address(0), key, IPoolManager.ModifyLiquidityParams(0, 0, 0, ""), "");

    //     PoolKey memory failedKey = key;
    //     failedKey.tickSpacing = 3;

    //     vm.expectRevert(IALM.UnauthorizedPool.selector);
    //     hook.beforeAddLiquidity(address(0), failedKey, IPoolManager.ModifyLiquidityParams(0, 0, 0, ""), "");

    //     vm.expectRevert(SafeCallback.NotPoolManager.selector);
    //     hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");

    //     vm.expectRevert(IALM.UnauthorizedPool.selector);
    //     hook.beforeSwap(address(0), failedKey, IPoolManager.SwapParams(true, 0, 0), "");
    // }

    // function test_pause() public {
    //     vm.prank(deployer.addr);
    //     hook.setPaused(true);

    //     vm.expectRevert(IALM.ContractPaused.selector);
    //     hook.deposit(address(0), 0);

    //     vm.expectRevert(IALM.ContractPaused.selector);
    //     hook.withdraw(deployer.addr, 0);

    //     vm.prank(address(manager));
    //     vm.expectRevert(IALM.ContractPaused.selector);
    //     hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    // }

    // function test_shutdown() public {
    //     vm.prank(deployer.addr);
    //     hook.setShutdown(true);

    //     vm.expectRevert(IALM.ContractShutdown.selector);
    //     hook.deposit(deployer.addr, 0);

    //     vm.prank(address(manager));
    //     vm.expectRevert(IALM.ContractShutdown.selector);
    //     hook.beforeSwap(address(0), key, IPoolManager.SwapParams(true, 0, 0), "");
    // }
}
