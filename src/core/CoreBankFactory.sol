// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./CoreBank.sol";

contract CoreBankFactory {
    event CoreBankCreated(
        address indexed coreBank,
        address indexed asset,
        string name,
        string symbol,
        uint256 minDelay,
        address initialAdmin
    );

    mapping(address => bool) public isCoreBank;
    address[] public coreBanks;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "CoreBankFactory: caller is not the owner");
        _;
    }

    function createCoreBank(
        IERC20 asset,
        string memory name,
        string memory symbol,
        uint32 minDelay,
        address initialAdmin
    ) external onlyOwner returns (CoreBank) {
        CoreBank newCoreBank = new CoreBank(
            asset,
            name,
            symbol,
            minDelay,
            initialAdmin
        );

        isCoreBank[address(newCoreBank)] = true;
        coreBanks.push(address(newCoreBank));

        emit CoreBankCreated(address(newCoreBank), address(asset), name, symbol, minDelay, initialAdmin);        
        return newCoreBank;
    }

    function getCoreBankCount() external view returns (uint256) {
        return coreBanks.length;
    }

    function getCoreBankAt(uint256 index) external view returns (address) {
        require(index < coreBanks.length, "Index out of bounds");
        return coreBanks[index];
    }

    function isCoreBankCreatedByFactory(
        address coreBank
    ) external view returns (bool) {
        return isCoreBank[coreBank];
    }

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
