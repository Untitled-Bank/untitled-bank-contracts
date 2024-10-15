// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/ICoreVault.sol";
import "./CoreVaultInternal.sol";
import "../libraries/Timelock.sol";

contract CoreVault is ICoreVault, CoreVaultInternal, Timelock {
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _minDelay,
        address _initialAdmin
    )
        ERC4626(_asset)
        ERC20(_name, _symbol)
        CoreVaultStorage()
        Timelock(_minDelay, _initialAdmin)
    {}

    function scheduleAddVault(
        address vault,
        uint256 allocation,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(vault != address(0), "CoreVault: Invalid vault address");
        require(!isVaultEnabled[vault], "CoreVault: Vault already added");
        require(
            allocation > 0 && allocation <= BASIS_POINTS,
            "CoreVault: Invalid allocation"
        );
        require(IVault(vault).asset() == asset(), "CoreVault: Vault asset mismatch");
        require(
            IVault(address(vault)).getVaultType() == IVault.VaultType.Public,
            "CoreVault: Not a Public Vault"
        );

        bytes32 operationId = keccak256(abi.encode(
            "addVault",
            vault,
            allocation
        ));

        scheduleOperation(operationId, delay);

        emit VaultAdditionScheduled(vault, allocation, delay, operationId);
    }

    function executeAddVault(address vault, uint256 allocation) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addVault",
            vault,
            allocation
        ));

        executeOperation(operationId);

        require(vault != address(0), "CoreVault: Invalid vault address");
        require(!isVaultEnabled[vault], "CoreVault: Vault already added");
        require(
            allocation > 0 && allocation <= BASIS_POINTS,
            "CoreVault: Invalid allocation"
        );
        require(IVault(vault).asset() == asset(), "CoreVault: Vault asset mismatch");
        require(
            IVault(address(vault)).getVaultType() == IVault.VaultType.Public,
            "CoreVault: Not a Public Vault"
        );

        uint256 totalAllocation = allocation;
        for (uint256 i = 0; i < vaultAllocations.length; i++) {
            totalAllocation += vaultAllocations[i].allocation;
        }
        require(
            totalAllocation <= BASIS_POINTS,
            "CoreVault: Total allocation exceeds 100%"
        );

        vaultAllocations.push(VaultAllocation(IVault(vault), allocation));
        isVaultEnabled[vault] = true;

        emit VaultAdded(vault, allocation);
    }

    function scheduleRemoveVault(address vault, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(isVaultEnabled[vault], "Vault not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "removeVault",
            vault
        ));

        scheduleOperation(operationId, delay);

        emit VaultRemovalScheduled(vault, delay, operationId);
    }

    function executeRemoveVault(address vault) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeVault",
            vault
        ));

        executeOperation(operationId);

        require(isVaultEnabled[vault], "Vault not enabled");

        for (uint256 i = 0; i < vaultAllocations.length; i++) {
            if (address(vaultAllocations[i].vault) == vault) {
                vaultAllocations[i] = vaultAllocations[vaultAllocations.length - 1];
                vaultAllocations.pop();
                break;
            }
        }
        isVaultEnabled[vault] = false;

        emit VaultRemoved(vault);
    }

    function scheduleUpdateAllocation(address vault, uint256 newAllocation, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(isVaultEnabled[vault], "Vault not enabled");
        require(
            newAllocation > 0 && newAllocation <= BASIS_POINTS,
            "CoreVault: Invalid allocation"
        );

        bytes32 operationId = keccak256(abi.encode(
            "updateAllocation",
            vault,
            newAllocation
        ));

        scheduleOperation(operationId, delay);

        emit AllocationUpdateScheduled(vault, newAllocation, delay, operationId);
    }

    function executeUpdateAllocation(address vault, uint256 newAllocation) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateAllocation",
            vault,
            newAllocation
        ));

        executeOperation(operationId);

        require(isVaultEnabled[vault], "Vault not enabled");

        uint256 totalAllocation = newAllocation;
        for (uint256 i = 0; i < vaultAllocations.length; i++) {
            if (address(vaultAllocations[i].vault) != vault) {
                totalAllocation += vaultAllocations[i].allocation;
            }
        }
        require(
            totalAllocation <= BASIS_POINTS,
            "Total allocation exceeds 100%"
        );

        for (uint256 i = 0; i < vaultAllocations.length; i++) {
            if (address(vaultAllocations[i].vault) == vault) {
                vaultAllocations[i].allocation = newAllocation;
                break;
            }
        }

        emit AllocationUpdated(vault, newAllocation);
    }

    function getVaultAllocations()
        external
        view
        returns (VaultAllocation[] memory)
    {
        return vaultAllocations;
    }
}
