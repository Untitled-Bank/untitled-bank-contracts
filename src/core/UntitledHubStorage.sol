// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IUntitledHub, MarketConfigs, Position, Market} from "../interfaces/IUntitledHub.sol";

abstract contract UntitledHubStorage is IUntitledHub {
    bytes32 public immutable DOMAIN_SEPARATOR;

    address public owner;
    address public feeRecipient;
    mapping(uint256 => mapping(address => Position)) public position;
    mapping(uint256 => Market) public market;
    mapping(address => bool) public isIrmRegistered;
    mapping(address => mapping(address => bool)) public isGranted;
    mapping(uint256 => MarketConfigs) public idToMarketConfigs;
    mapping(bytes32 => uint256) public marketConfigsHashToId;

    uint256 public flashLoanFeeRate = 0.0005e18; // 0.05% fee as default

    uint256 public lastUsedId;
    uint256 public marketCreationFee;
    uint256 public collectedFees;
    mapping(address => uint256) public tokenFees;

    constructor() {
        bytes32 DOMAIN_TYPEHASH = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("UntitledHub")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }
}
