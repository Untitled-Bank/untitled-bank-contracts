// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";

contract UBChainlinkOracle is IPriceProvider {
    using Math for uint256;

    /* IMMUTABLES */

    AggregatorV3Interface public immutable BASE_FEED_1;
    AggregatorV3Interface public immutable BASE_FEED_2;
    AggregatorV3Interface public immutable QUOTE_FEED_1;
    AggregatorV3Interface public immutable QUOTE_FEED_2;
    uint256 public immutable BASE_TOKEN_DECIMALS;
    uint256 public immutable QUOTE_TOKEN_DECIMALS;
    uint256 public immutable ORACLE_PRICE_SCALE;

    error ZeroPriceFeed();

    constructor(
        AggregatorV3Interface baseFeed1,
        AggregatorV3Interface baseFeed2,
        uint256 baseTokenDecimals,
        AggregatorV3Interface quoteFeed1,
        AggregatorV3Interface quoteFeed2,
        uint256 quoteTokenDecimals
    ) {
        BASE_FEED_1 = baseFeed1;
        BASE_FEED_2 = baseFeed2;
        QUOTE_FEED_1 = quoteFeed1;
        QUOTE_FEED_2 = quoteFeed2;
        BASE_TOKEN_DECIMALS = baseTokenDecimals;
        QUOTE_TOKEN_DECIMALS = quoteTokenDecimals;

        ORACLE_PRICE_SCALE =
            10 **
                (36 +
                    quoteTokenDecimals +
                    _getDecimals(quoteFeed1) +
                    _getDecimals(quoteFeed2) -
                    baseTokenDecimals -
                    _getDecimals(baseFeed1) -
                    _getDecimals(baseFeed2));
    }

    function isPriceProvider() external pure returns (bool) {
        return true;
    }

    function getCollateralTokenPrice() external view returns (uint256) {
        return
            ORACLE_PRICE_SCALE.mulDiv(_getBaseRawPrice(), _getQuoteRawPrice());
    }

    function getBasePrice() public view returns (uint256) {
        uint256 rawPrice = _getBaseRawPrice();

        uint256 feedDecimals = _getDecimals(BASE_FEED_1) +
            _getDecimals(BASE_FEED_2);
        if (feedDecimals > BASE_TOKEN_DECIMALS) {
            return rawPrice / (10 ** (feedDecimals - BASE_TOKEN_DECIMALS));
        } else {
            return rawPrice * (10 ** (BASE_TOKEN_DECIMALS - feedDecimals));
        }
    }

    function getQuotePrice() public view returns (uint256) {
        uint256 rawPrice = _getQuoteRawPrice();

        uint256 feedDecimals = _getDecimals(QUOTE_FEED_1) +
            _getDecimals(QUOTE_FEED_2);
        if (feedDecimals > QUOTE_TOKEN_DECIMALS) {
            return rawPrice / (10 ** (feedDecimals - QUOTE_TOKEN_DECIMALS));
        } else {
            return rawPrice * (10 ** (QUOTE_TOKEN_DECIMALS - feedDecimals));
        }
    }

    function _getBaseRawPrice() internal view returns (uint256) {
        uint256 price1 = _getFeedPrice(BASE_FEED_1);
        uint256 price2 = _getFeedPrice(BASE_FEED_2);
        return price1 * price2;
    }

    function _getQuoteRawPrice() internal view returns (uint256) {
        uint256 price1 = _getFeedPrice(QUOTE_FEED_1);
        uint256 price2 = _getFeedPrice(QUOTE_FEED_2);
        return price1 * price2;
    }

    function _getFeedPrice(
        AggregatorV3Interface feed
    ) internal view returns (uint256) {
        if (address(feed) == address(0)) return 1;

        (, int256 latestPrice, , , ) = feed.latestRoundData();
        if (latestPrice <= 0) revert ZeroPriceFeed();

        return uint256(latestPrice);
    }

    function _getDecimals(
        AggregatorV3Interface feed
    ) internal view returns (uint256) {
        if (address(feed) == address(0)) return 0;
        return feed.decimals();
    }
}
