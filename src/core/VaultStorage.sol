// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/IVault.sol";
import "./Bank.sol";

contract VaultStorage {
    Bank public immutable bank;
    IVault.BankAllocation[] public bankAllocations;
    mapping(uint256 => bool) public isBankEnabled;

    uint256 public constant MAX_BANKS = 10;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant BASIS_POINTS_WAD = BASIS_POINTS * 1e18;
    uint256 public fee;
    address public feeRecipient;

    IVault.VaultType public vaultType;
    mapping(address => bool) public whitelist;

    constructor(Bank _bank, IVault.VaultType _vaultType) {
        bank = _bank;
        vaultType = _vaultType;
    }
}
