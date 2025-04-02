// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/IUntitledHub.sol";

contract MockInterestRateModel {
    function isIrm() external pure returns (bool) {
        return true;
    }

    function borrowRate(
        MarketConfigs memory,
        Market memory
    ) external pure returns (uint256) {
        uint256 util = 0.05 * 1e18;
        return util / 365 days;
    }
}

contract MockInvalidInterestRateModel {
    function borrowRate(
        MarketConfigs memory,
        Market memory
    ) external pure returns (uint256) {
        uint256 util = 0.05 * 1e18;
        return util / 365 days;
    }
}