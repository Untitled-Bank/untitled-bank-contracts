// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/IBank.sol";
import "./UntitledHub.sol";

contract BankStorage {
    UntitledHub public immutable untitledHub;
    IBank.MarketAllocation[] public marketAllocations;
    mapping(uint256 => bool) public isMarketEnabled;

    uint256 public constant MAX_MARKETS = 10;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant BASIS_POINTS_WAD = BASIS_POINTS * 1e18;
    uint256 public fee;
    address public feeRecipient;

    IBank.BankType public bankType;
    mapping(address => bool) public whitelist;

    constructor(UntitledHub _untitledHub, IBank.BankType _bankType) {
        untitledHub = _untitledHub;
        bankType = _bankType;
    }
}
