// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Vault.sol";

contract VaultFactory {
    event VaultCreated(
        address indexed vault,
        address indexed asset,
        string name,
        string symbol
    );

    Bank public immutable bank;
    mapping(address => bool) public isVault;
    address[] public vaults;

    constructor(Bank _bank) {
        bank = _bank;
    }

    function createVault(
        IERC20 asset,
        string memory name,
        string memory symbol,
        uint256 initialFee,
        address initialFeeRecipient,
        uint256 minDelay,
        IVault.VaultType vaultType
    ) external returns (Vault) {
        Vault newVault = new Vault(
            asset,
            name,
            symbol,
            bank,
            initialFee,
            initialFeeRecipient,
            minDelay,
            msg.sender,
            vaultType
        );

        isVault[address(newVault)] = true;
        vaults.push(address(newVault));

        emit VaultCreated(address(newVault), address(asset), name, symbol);

        return newVault;
    }

    function getVaultCount() external view returns (uint256) {
        return vaults.length;
    }

    function getVaultAt(uint256 index) external view returns (address) {
        require(index < vaults.length, "Index out of bounds");
        return vaults[index];
    }

    function isVaultCreatedByFactory(
        address vault
    ) external view returns (bool) {
        return isVault[vault];
    }
}
