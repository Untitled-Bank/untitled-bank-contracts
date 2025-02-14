// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IPriceProvider} from "../interfaces/IPriceProvider.sol";

contract PriceProvider is IPriceProvider {
    uint256 public price;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function isPriceProvider() external pure returns (bool) {
        return true;
    }

    function getCollateralTokenPrice() external view returns (uint256) {
        return price;
    }

    function setCollateralTokenPrice(uint256 _price) external {
        require(msg.sender == owner, "Only owner can set price");
        price = _price;
    }
}
