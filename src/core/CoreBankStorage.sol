// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ICoreBank.sol";

contract CoreBankStorage is Initializable {
    ICoreBank.BankAllocation[] public bankAllocations;
    mapping(address => bool) public isBankEnabled;
    mapping(address => uint256) public bankToIndex;

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant BASIS_POINTS_WAD = BASIS_POINTS * 1e18;
    uint256 public fee;
    address public feeRecipient;

    function _initializeCoreBankStorage() internal onlyInitializing {
    }
}
