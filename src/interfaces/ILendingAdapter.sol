// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

interface ILendingAdapter {
    function borrow(uint256 amount) external;

    function addCollateral(uint256 amount) external;

    function repay(uint256 amount) external;

    function getCollateral() external view returns (uint256);

    function removeCollateral(uint256 amount) external;

    function getBorrowed() external view returns (uint256);

    // ** Params
    function addAuthorizedCaller(address) external;

    function getAssetPrice(address underlying) external view returns (uint256);
}
