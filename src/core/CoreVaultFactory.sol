// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./CoreVault.sol";

contract CoreVaultFactory {
    event CoreVaultCreated(
        address indexed coreVault,
        address indexed asset,
        string name,
        string symbol,
        uint256 minDelay,
        address initialAdmin
    );

    mapping(address => bool) public isCoreVault;
    address[] public coreVaults;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "CoreVaultFactory: caller is not the owner");
        _;
    }

    function createCoreVault(
        IERC20 asset,
        string memory name,
        string memory symbol,
        uint256 minDelay,
        address initialAdmin
    ) external onlyOwner returns (CoreVault) {
        CoreVault newCoreVault = new CoreVault(
            asset,
            name,
            symbol,
            minDelay,
            initialAdmin
        );

        isCoreVault[address(newCoreVault)] = true;
        coreVaults.push(address(newCoreVault));

        emit CoreVaultCreated(address(newCoreVault), address(asset), name, symbol, minDelay, initialAdmin);        
        return newCoreVault;
    }

    function getCoreVaultCount() external view returns (uint256) {
        return coreVaults.length;
    }

    function getCoreVaultAt(uint256 index) external view returns (address) {
        require(index < coreVaults.length, "Index out of bounds");
        return coreVaults[index];
    }

    function isCoreVaultCreatedByFactory(
        address coreVault
    ) external view returns (bool) {
        return isCoreVault[coreVault];
    }

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
