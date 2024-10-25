// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IBank.sol";

interface ICoreBank is IERC4626 {
    struct BankAllocation {
        IBank bank;
        uint256 allocation;
    }

    function scheduleAddBank(address bank, uint256 allocation, uint256 delay) external;
    function executeAddBank(address bank, uint256 allocation) external;
    function scheduleRemoveBank(address bank, uint256 delay) external;
    function executeRemoveBank(address bank) external;
    function scheduleUpdateAllocation(address bank, uint256 newAllocation, uint256 delay) external;
    function executeUpdateAllocation(address bank, uint256 newAllocation) external;
    function getBankAllocations() external view returns (BankAllocation[] memory);

    event BankAdditionScheduled(
        address indexed bank,
        uint256 allocation,
        uint256 delay,
        bytes32 operationId
    );
    event BankAdded(address indexed bank, uint256 allocation);
    event BankRemovalScheduled(
        address indexed bank,
        uint256 delay,
        bytes32 operationId
    );
    event BankRemoved(address indexed bank);
    event AllocationUpdateScheduled(
        address indexed bank,
        uint256 newAllocation,
        uint256 delay,
        bytes32 operationId
    );
    event AllocationUpdated(address indexed bank, uint256 newAllocation);
}
