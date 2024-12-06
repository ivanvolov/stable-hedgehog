// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import "@src/interfaces/ILendingAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

import {IPool} from "@aave-core-v3/contracts/interfaces/IPool.sol";
import {IAaveOracle} from "@aave-core-v3/contracts/interfaces/IAaveOracle.sol";
import {IPoolAddressesProvider} from "@aave-core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPoolDataProvider} from "@aave-core-v3/contracts/interfaces/IPoolDataProvider.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AaveLendingAdapter is Ownable, ILendingAdapter {
    using SafeERC20 for IERC20;

    //aaveV3
    IPoolAddressesProvider constant provider = IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);

    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    mapping(address => bool) public authorizedCallers;

    constructor() Ownable(msg.sender) {
        USDT.forceApprove(getPool(), type(uint256).max);
        USDC.approve(getPool(), type(uint256).max);
    }

    function getPool() public view returns (address) {
        return provider.getPool();
    }

    function addAuthorizedCaller(address _caller) external onlyOwner {
        authorizedCallers[_caller] = true;
    }

    // ** Lending market

    function getBorrowed() external view returns (uint256) {
        (, , address variableDebtTokenAddress) = getAssetAddresses(address(USDT));
        return IERC20(variableDebtTokenAddress).balanceOf(address(this));
    }

    function borrow(uint256 amount) external onlyAuthorizedCaller {
        IPool(getPool()).borrow(address(USDT), amount, 2, 0, address(this)); // Interest rate mode: 2 = variable
        USDT.safeTransfer(msg.sender, amount);
    }

    function repay(uint256 amount) external onlyAuthorizedCaller {
        USDT.safeTransferFrom(msg.sender, address(this), amount);
        IPool(getPool()).repay(address(USDT), amount, 2, address(this));
    }

    function getCollateral() external view returns (uint256) {
        (address aTokenAddress, , ) = getAssetAddresses(address(USDC));
        return IERC20(aTokenAddress).balanceOf(address(this));
    }

    function removeCollateral(uint256 amount) external onlyAuthorizedCaller {
        IPool(getPool()).withdraw(address(USDC), amount, msg.sender);
    }

    function addCollateral(uint256 amount) external onlyAuthorizedCaller {
        USDC.transferFrom(msg.sender, address(this), amount);
        IPool(getPool()).supply(address(USDC), amount, address(this), 0);
    }

    // ** Helpers

    function getAssetAddresses(address underlying) public view returns (address, address, address) {
        return IPoolDataProvider(provider.getPoolDataProvider()).getReserveTokensAddresses(underlying);
    }

    function getAssetPrice(address underlying) external view returns (uint256) {
        return IAaveOracle(provider.getPriceOracle()).getAssetPrice(underlying) * 1e10;
    }

    modifier onlyAuthorizedCaller() {
        require(authorizedCallers[msg.sender] == true, "Caller is not authorized V4 pool");
        _;
    }
}
