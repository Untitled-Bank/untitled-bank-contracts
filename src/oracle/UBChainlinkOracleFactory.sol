// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import {UBChainlinkOracle} from "./UBChainlinkOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UBChainlinkOracleFactory is Ownable {
    mapping(address => bool) public isRegisteredOracle;
    mapping(bytes => bool) public isRegisteredParams;

    event OracleCreated(
        address indexed oracle,
        address baseFeed1,
        address baseFeed2,
        address quoteFeed1,
        address quoteFeed2
    );
    error OracleAlreadyCreated();

    constructor() Ownable(msg.sender) {}

    function createOracle(
        AggregatorV3Interface baseFeed1,
        AggregatorV3Interface baseFeed2,
        uint256 baseTokenDecimals,
        AggregatorV3Interface quoteFeed1,
        AggregatorV3Interface quoteFeed2,
        uint256 quoteTokenDecimals
    ) external returns (address) {
        UBChainlinkOracle oracle = new UBChainlinkOracle(
            baseFeed1,
            baseFeed2,
            baseTokenDecimals,
            quoteFeed1,
            quoteFeed2,
            quoteTokenDecimals
        );

        // duplicated check with encoding parameters
        bytes memory encodedParams = abi.encode(
            baseFeed1,
            baseFeed2,
            baseTokenDecimals,
            quoteFeed1,
            quoteFeed2,
            quoteTokenDecimals
        );

        if (isRegisteredParams[encodedParams]) revert OracleAlreadyCreated();

        isRegisteredParams[encodedParams] = true;
        isRegisteredOracle[address(oracle)] = true;

        emit OracleCreated(
            address(oracle),
            address(baseFeed1),
            address(baseFeed2),
            address(quoteFeed1),
            address(quoteFeed2)
        );

        return address(oracle);
    }

    function isOracle(address oracle) external view returns (bool) {
        return isRegisteredOracle[oracle];
    }
}
