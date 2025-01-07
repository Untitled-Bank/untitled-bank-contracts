// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IBank.sol";
import "./UntitledHub.sol";

contract BankStorage is Initializable {
    UntitledHub public untitledHub;
    IBank.MarketAllocation[] public marketAllocations;
    mapping(uint256 => bool) public isMarketEnabled;
    mapping(uint256 => uint256) public marketIdToIndex;

    uint256 public fee;
    address public feeRecipient;

    IBank.BankType public bankType;
    mapping(address => bool) public whitelist;

    function _initializeBankStorage(UntitledHub _untitledHub, IBank.BankType _bankType) internal onlyInitializing {
        untitledHub = _untitledHub;
        bankType = _bankType;
    }
}
