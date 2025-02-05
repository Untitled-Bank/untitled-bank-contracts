// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import {UBPythOracle} from "./UBPythOracle.sol";
import {AbstractPyth} from "@pythnetwork/pyth-sdk-solidity/AbstractPyth.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UBPythOracleFactory is Ownable {
    mapping(address => bool) public isRegisteredOracle;
    mapping(bytes => bool) public isRegisteredParams;

    event OracleCreated(
        address indexed oracle,
        bytes32 baseId1,
        bytes32 baseId2,
        bytes32 quoteId1,
        bytes32 quoteId2,
        uint256 baseTokenDecimals,
        uint256 quoteTokenDecimals
    );
    error OracleAlreadyCreated();
    constructor() Ownable(msg.sender) {}

    function createOracle(
        AbstractPyth pyth,
        bytes32 baseId1,
        bytes32 baseId2,
        bytes32 quoteId1,
        bytes32 quoteId2,
        uint256 baseTokenDecimals,
        uint256 quoteTokenDecimals
    ) external returns (address) {
        UBPythOracle oracle = new UBPythOracle(
            pyth,
            baseId1,
            baseId2,
            quoteId1,
            quoteId2,
            baseTokenDecimals,
            quoteTokenDecimals
        );

        bytes memory encodedParams = abi.encode(
            baseId1,
            baseId2,
            quoteId1,
            quoteId2,
            baseTokenDecimals,
            quoteTokenDecimals
        );
        if (isRegisteredParams[encodedParams]) revert OracleAlreadyCreated();

        isRegisteredParams[encodedParams] = true;
        isRegisteredOracle[address(oracle)] = true;

        emit OracleCreated(
            address(oracle),
            baseId1,
            baseId2,
            quoteId1,
            quoteId2,
            baseTokenDecimals,
            quoteTokenDecimals
        );

        return address(oracle);
    }

    function isOracle(address oracle) external view returns (bool) {
        return isRegisteredOracle[oracle];
    }
}
