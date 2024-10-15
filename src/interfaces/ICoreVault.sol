// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IVault.sol";

interface ICoreVault is IERC4626 {
    struct VaultAllocation {
        IVault vault;
        uint256 allocation;
    }

    function scheduleAddVault(address vault, uint256 allocation, uint256 delay) external;
    function executeAddVault(address vault, uint256 allocation) external;
    function scheduleRemoveVault(address vault, uint256 delay) external;
    function executeRemoveVault(address vault) external;
    function scheduleUpdateAllocation(address vault, uint256 newAllocation, uint256 delay) external;
    function executeUpdateAllocation(address vault, uint256 newAllocation) external;
    function getVaultAllocations() external view returns (VaultAllocation[] memory);

    event VaultAdditionScheduled(
        address indexed vault,
        uint256 allocation,
        uint256 delay,
        bytes32 operationId
    );
    event VaultAdded(address indexed vault, uint256 allocation);
    event VaultRemovalScheduled(
        address indexed vault,
        uint256 delay,
        bytes32 operationId
    );
    event VaultRemoved(address indexed vault);
    event AllocationUpdateScheduled(
        address indexed vault,
        uint256 newAllocation,
        uint256 delay,
        bytes32 operationId
    );
    event AllocationUpdated(address indexed vault, uint256 newAllocation);
}
