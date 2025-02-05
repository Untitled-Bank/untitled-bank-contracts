// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import {AbstractPyth} from "@pythnetwork/pyth-sdk-solidity/AbstractPyth.sol";
import {PythStructs} from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";

contract UBPythOracle is IPriceProvider {
    using Math for uint256;

    /* IMMUTABLES */

    AbstractPyth public immutable PYTH;
    bytes32 public immutable BASE_ID_1;
    bytes32 public immutable BASE_ID_2;
    bytes32 public immutable QUOTE_ID_1;
    bytes32 public immutable QUOTE_ID_2;
    uint256 public immutable BASE_TOKEN_DECIMALS;
    uint256 public immutable QUOTE_TOKEN_DECIMALS;
    uint256 public immutable ORACLE_PRICE_SCALE;

    error ZeroOrNegativePrice();

    constructor(
        AbstractPyth pyth,
        bytes32 baseId1,
        bytes32 baseId2,
        bytes32 quoteId1,
        bytes32 quoteId2,
        uint256 baseTokenDecimals,
        uint256 quoteTokenDecimals
    ) {
        PYTH = pyth;
        BASE_ID_1 = baseId1;
        BASE_ID_2 = baseId2;
        QUOTE_ID_1 = quoteId1;
        QUOTE_ID_2 = quoteId2;
        BASE_TOKEN_DECIMALS = baseTokenDecimals;
        QUOTE_TOKEN_DECIMALS = quoteTokenDecimals;

        ORACLE_PRICE_SCALE =
            10 **
                (36 +
                    quoteTokenDecimals +
                    _getDecimals(quoteId1) +
                    _getDecimals(quoteId2) -
                    baseTokenDecimals -
                    _getDecimals(baseId1) -
                    _getDecimals(baseId2));
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

        uint256 feedDecimals = _getDecimals(BASE_ID_1) +
            _getDecimals(BASE_ID_2);
        if (feedDecimals > BASE_TOKEN_DECIMALS) {
            return rawPrice / (10 ** (feedDecimals - BASE_TOKEN_DECIMALS));
        } else {
            return rawPrice * (10 ** (BASE_TOKEN_DECIMALS - feedDecimals));
        }
    }

    function getQuotePrice() public view returns (uint256) {
        uint256 rawPrice = _getQuoteRawPrice();

        uint256 feedDecimals = _getDecimals(QUOTE_ID_1) +
            _getDecimals(QUOTE_ID_2);
        if (feedDecimals > QUOTE_TOKEN_DECIMALS) {
            return rawPrice / (10 ** (feedDecimals - QUOTE_TOKEN_DECIMALS));
        } else {
            return rawPrice * (10 ** (QUOTE_TOKEN_DECIMALS - feedDecimals));
        }
    }

    function _getBaseRawPrice() internal view returns (uint256) {
        uint256 price1 = _getFeedPrice(BASE_ID_1);
        uint256 price2 = _getFeedPrice(BASE_ID_2);
        return price1 * price2;
    }

    function _getQuoteRawPrice() internal view returns (uint256) {
        uint256 price1 = _getFeedPrice(QUOTE_ID_1);
        uint256 price2 = _getFeedPrice(QUOTE_ID_2);
        return price1 * price2;
    }

    function _getFeedPrice(bytes32 id) internal view returns (uint256) {
        if (id == bytes32(0)) return 1;

        PythStructs.PriceFeed memory priceFeed = PYTH.queryPriceFeed(id);
        if (priceFeed.price.price <= 0) revert ZeroOrNegativePrice();

        return uint256(uint64(priceFeed.price.price));
    }

    function _getDecimals(bytes32 id) internal view returns (uint256) {
        if (id == bytes32(0)) return 0;

        PythStructs.PriceFeed memory priceFeed = PYTH.queryPriceFeed(id);
        return uint256(uint32(-priceFeed.price.expo));
    }
}
