// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {MarketConfigs, Market} from "../interfaces/IBank.sol";

import {WadMath} from "../libraries/math/WadMath.sol";

contract InterestRateModel is IInterestRateModel {
    using WadMath for uint128;

    function isIrm() external pure returns (bool) {
        return true;
    }

    function borrowRateView(
        MarketConfigs memory,
        Market memory market
    ) public pure returns (uint256) {
        if (market.totalSupplyAssets == 0) return 0;

        uint256 utilization = market.totalBorrowAssets.divWadDown(
            market.totalSupplyAssets
        );

        return utilization / 365 days;
    }

    function borrowRate(
        MarketConfigs memory marketConfigs,
        Market memory market
    ) external pure returns (uint256) {
        return borrowRateView(marketConfigs, market);
    }
}
