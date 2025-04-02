// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract MockPriceProvider {
    uint256 public price = 1e36;

    function isPriceProvider() external pure returns (bool) {
        return true;
    }

    function getCollateralTokenPrice() external view returns (uint256) {
        return price;
    }

    function setCollateralTokenPrice(uint256 _price) external {
        price = _price;
    }
}