// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/ICoreVault.sol";

contract CoreVaultStorage {
    ICoreVault.VaultAllocation[] public vaultAllocations;
    mapping(address => bool) public isVaultEnabled;

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant BASIS_POINTS_WAD = BASIS_POINTS * 1e18;
    uint256 public fee;
    address public feeRecipient;

    constructor() {}
}
