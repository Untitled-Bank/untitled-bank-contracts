// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../core/Vault.sol";

interface IVaultFactory {
    event VaultCreated(
        address indexed vault,
        address indexed asset,
        string name,
        string symbol
    );

    function bank() external view returns (address);
    function isVault(address) external view returns (bool);
    function vaults(uint256) external view returns (address);

    function createVault(
        IERC20 asset,
        string memory name,
        string memory symbol,
        uint256 initialFee,
        address initialFeeRecipient,
        uint256 minDelay,
        IVault.VaultType vaultType
    ) external returns (Vault);

    function getVaultCount() external view returns (uint256);
    function getVaultAt(uint256 index) external view returns (address);
    function isVaultCreatedByFactory(address vault) external view returns (bool);
}