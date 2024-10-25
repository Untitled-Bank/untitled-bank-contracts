// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../core/Bank.sol";

interface IBankFactory {
    event BankCreated(
        address indexed bank,
        address indexed asset,
        string name,
        string symbol
    );

    function market() external view returns (address);
    function isBank(address) external view returns (bool);
    function banks(uint256) external view returns (address);

    function createBank(
        IERC20 asset,
        string memory name,
        string memory symbol,
        uint256 initialFee,
        address initialFeeRecipient,
        uint256 minDelay,
        IBank.BankType bankType
    ) external returns (Bank);

    function getBankCount() external view returns (uint256);
    function getBankAt(uint256 index) external view returns (address);
    function isBankCreatedByFactory(address bank) external view returns (bool);
}