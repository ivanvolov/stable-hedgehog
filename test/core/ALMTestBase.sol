// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ALM} from "@src/ALM.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {AaveLendingAdapter} from "@src/core/AaveLendingAdapter.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ALMTestBase is Test, Deployers {
    using TestAccountLib for TestAccount;
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    ALM hook;

    IERC20 USDC;
    IERC20 USDT;

    ILendingAdapter lendingAdapter;

    TestAccount marketCreator;
    TestAccount morphoLpProvider;

    TestAccount deployer;
    TestAccount alice;
    TestAccount swapper;
    TestAccount zero;

    uint256 almId;

    function init_hook() internal {
        vm.startPrank(deployer.addr);

        // MARK: Usual UniV4 hook deployment process
        address hookAddress = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo("ALM.sol", abi.encode(manager), hookAddress);
        hook = ALM(hookAddress);
        vm.label(address(hook), "hook");
        assertEq(hook.hookDeployer(), deployer.addr);
        // MARK END

        lendingAdapter = new AaveLendingAdapter();

        lendingAdapter.addAuthorizedCaller(address(hook));

        // MARK: Pool deployment
        // pre-compute key in order to restrict hook to this pool
        PoolKey memory _key = PoolKey(Currency.wrap(address(USDC)), Currency.wrap(address(USDT)), 100, 1, hook);

        hook.setAuthorizedPool(_key);
        (key, ) = initPool(
            Currency.wrap(address(USDC)),
            Currency.wrap(address(USDT)),
            hook,
            100,
            Deployers.SQRT_PRICE_1_1,
            ""
        );

        hook.setLendingAdapter(address(lendingAdapter));
        // MARK END

        // This is needed in order to simulate proper accounting
        deal(address(USDC), address(manager), 1000 ether);
        deal(address(USDT), address(manager), 1000 ether);
        vm.stopPrank();
    }

    function create_accounts_and_tokens() public {
        USDT = IERC20(ALMBaseLib.USDT);
        vm.label(address(USDT), "USDT");
        USDC = IERC20(ALMBaseLib.USDC);
        vm.label(address(USDC), "USDC");

        deployer = TestAccountLib.createTestAccount("deployer");
        alice = TestAccountLib.createTestAccount("alice");
        swapper = TestAccountLib.createTestAccount("swapper");
        zero = TestAccountLib.createTestAccount("zero");
    }

    function approve_accounts() public {
        vm.startPrank(alice.addr);
        USDC.approve(address(hook), type(uint256).max);
        USDT.forceApprove(address(hook), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        USDC.approve(address(swapRouter), type(uint256).max);
        USDT.forceApprove(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    // -- Uniswap V4 -- //

    function swapUSDT_USDC_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, int256(amount), key);
    }

    function swapUSDT_USDC_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(false, -int256(amount), key);
    }

    function swapUSDC_USDT_Out(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, int256(amount), key);
    }

    function swapUSDC_USDT_In(uint256 amount) public returns (uint256, uint256) {
        return _swap(true, -int256(amount), key);
    }

    function _swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (uint256, uint256) {
        vm.prank(swapper.addr);
        BalanceDelta delta = swapRouter.swap(
            _key,
            IPoolManager.SwapParams(
                zeroForOne,
                amount,
                zeroForOne == true ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        return (uint256(int256(delta.amount0())), uint256(int256(delta.amount1())));
    }

    function __swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (int256, int256) {
        // console.log("> __swap");
        uint256 usdtBefore = USDT.balanceOf(swapper.addr);
        uint256 usdcBefore = USDC.balanceOf(swapper.addr);

        vm.prank(swapper.addr);
        BalanceDelta delta = swapRouter.swap(
            _key,
            IPoolManager.SwapParams(
                zeroForOne,
                amount,
                zeroForOne == true ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        if (zeroForOne) {
            assertEq(usdcBefore - USDC.balanceOf(swapper.addr), uint256(int256(-delta.amount0())));
            assertEq(USDT.balanceOf(swapper.addr) - usdtBefore, uint256(int256(delta.amount1())));
        } else {
            assertEq(USDC.balanceOf(swapper.addr) - usdcBefore, uint256(int256(delta.amount0())));
            assertEq(usdtBefore - USDT.balanceOf(swapper.addr), uint256(int256(-delta.amount1())));
        }
        return (int256(delta.amount0()), int256(delta.amount1()));
    }

    // -- Custom assertions -- //
    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0, 0);
    }

    function assertEqBalanceState(address owner, uint256 _balanceUSDT, uint256 _balanceUSDC) public view {
        assertEqBalanceState(owner, _balanceUSDT, _balanceUSDC, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceUSDT,
        uint256 _balanceUSDC,
        uint256 _balanceETH
    ) public view {
        assertApproxEqAbs(USDT.balanceOf(owner), _balanceUSDT, 1000, "Balance USDT not equal");
        assertApproxEqAbs(USDC.balanceOf(owner), _balanceUSDC, 10, "Balance USDC not equal");
        assertApproxEqAbs(owner.balance, _balanceETH, 10, "Balance ETH not equal");
    }
}
