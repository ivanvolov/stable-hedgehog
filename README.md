# TurboStable

Leveraged LP vault that boosts stablecoin and pegged asset liquidity up to 20x. Achieved via looping leveraged long and short positions on Euler and deploying them on Uniswap V4 using the NoOp approach for on-demand liquidity management.

Provides up to 20x more liquidity for stables, earns up to 20x more trading fees, while also collecting interest rate.

## Problem

How can we increase stablecoins and pegged asset pools capital efficiency and LP profitability?

## Solution

Leveraged USDC-USDT position achieved via looping.

## How it works?

TurboStable loops long and short positions on AAVE to create leveraged exposure, amplifying liquidity. These positions are deployed on Uniswap V4 using the NoOp approach, enabling efficient liquidity management and earning both trading fees and interest income.

1. Leverage Creation:

* Supply USDC as collateral.
* Borrow USDT via a flash loan.
* Swap USDT into USDC.
* Add the received USDC as collateral.
* Borrow USDT again and repay the flash loan.

2. Liquidity Deployment:

Use the collateral/debt state as liquidity on Uniswap V4, utilizing the NoOp hook for efficient deployment.

3. During Swaps: USDC → USDT:
* Accept USDC from the user and add it to our collateral.
* Increase USDT debt and transfer the borrowed USDT to the user.

## Benefits

* Increased Liquidity: Amplifies stablecoin pool liquidity up to 20x.
* Higher Earnings: Earns trading fees and lending interest simultaneously.
* Capital Efficiency: Optimizes asset utilization with dynamic liquidity management.
* Enhanced LP Profitability: Provides competitive yields for liquidity providers.

## Setting up

```
forge install
```

### Build

```shell
forge build
```

### Format

```shell
forge fmt
```

### Test all project

```
make test_all
```
