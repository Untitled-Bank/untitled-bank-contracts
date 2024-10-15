// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IBank, MarketConfigs, Position, Market} from "../interfaces/IBank.sol";

abstract contract BankStorage is IBank {
    bytes32 public immutable DOMAIN_SEPARATOR;

    address public owner;
    address public feeRecipient;
    mapping(uint256 => mapping(address => Position)) public position;
    mapping(uint256 => Market) public market;
    mapping(address => bool) public isIrmRegistered;
    mapping(address => mapping(address => bool)) public isGranted;
    mapping(uint256 => MarketConfigs) public idToMarketConfigs;

    uint256 public lastUsedId;
    uint256 public marketCreationFee;
    uint256 public collectedFees;

    constructor() {
        bytes32 DOMAIN_TYPEHASH = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("Bank")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }
}
