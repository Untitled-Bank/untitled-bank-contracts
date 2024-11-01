// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Bank.sol";

contract BankFactory {
    event BankCreated(
        address indexed bank,
        address indexed asset,
        string name,
        string symbol
    );

    UntitledHub public immutable untitledHub;
    mapping(address => bool) public isBank;
    address[] public banks;

    constructor(UntitledHub _untitledHub) {
        untitledHub = _untitledHub;
    }

    function createBank(
        IERC20 asset,
        string memory name,
        string memory symbol,
        uint256 initialFee,
        address initialFeeRecipient,
        uint32 minDelay,
        IBank.BankType bankType
    ) external returns (Bank) {
        Bank newBank = new Bank(
            asset,
            name,
            symbol,
            untitledHub,
            initialFee,
            initialFeeRecipient,
            minDelay,
            msg.sender,
            bankType
        );

        isBank[address(newBank)] = true;
        banks.push(address(newBank));

        emit BankCreated(address(newBank), address(asset), name, symbol);

        return newBank;
    }

    function getBankCount() external view returns (uint256) {
        return banks.length;
    }

    function getBankAt(uint256 index) external view returns (address) {
        require(index < banks.length, "Index out of bounds");
        return banks[index];
    }

    function isBankCreatedByFactory(
        address bank
    ) external view returns (bool) {
        return isBank[bank];
    }
}
