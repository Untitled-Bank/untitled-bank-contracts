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

    function scheduleAddBank(address bank, uint32 delay) external;
    function executeAddBank(address bank) external;
    function cancelAddBank(address bank) external;
    function scheduleRemoveBank(address bank, uint32 delay) external;
    function executeRemoveBank(address bank) external;
    function cancelRemoveBank(address bank) external;
    function scheduleUpdateAllocations(BankAllocation[] calldata newBankAllocations, uint32 delay) external;
    function executeUpdateAllocations(BankAllocation[] calldata newBankAllocations) external;
    function cancelUpdateAllocations(BankAllocation[] calldata newBankAllocations) external;
    function scheduleReallocate(address[] calldata withdrawBanks, uint256[] calldata withdrawAmounts, address[] calldata depositBanks, uint256[] calldata depositAmounts, uint32 delay) external;
    function executeReallocate(address[] calldata withdrawBanks, uint256[] calldata withdrawAmounts, address[] calldata depositBanks, uint256[] calldata depositAmounts) external;
    function cancelReallocate(address[] calldata withdrawBanks, uint256[] calldata withdrawAmounts, address[] calldata depositBanks, uint256[] calldata depositAmounts) external;
    function getBankAllocations() external view returns (BankAllocation[] memory);

    event BankAdditionScheduled(
        address indexed bank,
        uint32 delay,
        bytes32 operationId
    );
    event BankAdded(address indexed bank);
    event BankRemovalScheduled(
        address indexed bank,
        uint32 delay,
        bytes32 operationId
    );
    event BankRemoved(address indexed bank);
    event AllocationsUpdateScheduled(
        BankAllocation[] newBankAllocations,
        uint32 delay,
        bytes32 operationId
    );
    event AllocationsUpdated(BankAllocation[] newBankAllocations);
    event BankAdditionCancelled(address indexed bank, bytes32 indexed operationId);
    event BankRemovalCancelled(address indexed bank, bytes32 indexed operationId);
    event AllocationsUpdateCancelled(BankAllocation[] newBankAllocations, bytes32 indexed operationId);
    event ReallocateScheduled(address[] withdrawBanks, uint256[] withdrawAmounts, address[] depositBanks, uint256[] depositAmounts, uint32 delay, bytes32 indexed operationId);
    event ReallocateExecuted(address[] withdrawBanks, uint256[] withdrawAmounts, address[] depositBanks, uint256[] depositAmounts);
    event ReallocateCancelled(address[] withdrawBanks, uint256[] withdrawAmounts, address[] depositBanks, uint256[] depositAmounts, bytes32 indexed operationId);
}
