// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault is IERC4626 {
    enum VaultType {
        Public,
        Private
    }

    struct BankAllocation {
        uint256 id;
        uint256 allocation;
    }

    function scheduleAddBank(uint256 id, uint256 allocation, uint256 delay) external;
    function executeAddBank(uint256 id, uint256 allocation) external;
    function scheduleAddBanks(uint256[] calldata ids, uint256[] calldata allocations, uint256 delay) external;
    function executeAddBanks(uint256[] calldata ids, uint256[] calldata allocations) external;
    function scheduleRemoveBank(uint256 id, uint256 delay) external;
    function executeRemoveBank(uint256 id) external;
    function scheduleRemoveBanks(uint256[] calldata ids, uint256 delay) external;
    function executeRemoveBanks(uint256[] calldata ids) external;
    function scheduleUpdateAllocation(uint256 id, uint256 newAllocation, uint256 delay) external;
    function executeUpdateAllocation(uint256 id, uint256 newAllocation) external;
    function scheduleSetFee(uint256 newFee, uint256 delay) external;
    function executeSetFee(uint256 newFee) external;
    function scheduleSetFeeRecipient(address newFeeRecipient, uint256 delay) external;
    function executeSetFeeRecipient(address newFeeRecipient) external;
    function scheduleUpdateWhitelist(address account, bool status, uint256 delay) external;
    function executeUpdateWhitelist(address account, bool status) external;
    function harvest() external;
    function getVaultType() external view returns (VaultType);
    function getFee() external view returns (uint256);
    function getFeeRecipient() external view returns (address);
    function getBankAllocations() external view returns (BankAllocation[] memory);
    function isWhitelisted(address account) external view returns (bool);

    event VaultTypeSet(VaultType vaultType);
    event BankAdditionScheduled(
        uint256 indexed id,
        uint256 allocation,
        uint256 delay,
        bytes32 operationId
    );
    event BankAdded(uint256 indexed id, uint256 allocation);
    event BanksAdditionScheduled(
        uint256[] ids,
        uint256[] allocations,
        uint256 delay,
        bytes32 operationId
    );
    event BanksAdded(uint256[] ids, uint256[] allocations);
    event BankRemovalScheduled(
        uint256 indexed id,
        uint256 delay,
        bytes32 operationId
    );
    event BankRemoved(uint256 indexed id);
    event BanksRemovalScheduled(
        uint256[] ids,
        uint256 delay,
        bytes32 operationId
    );
    event BanksRemoved(uint256[] ids);
    event AllocationUpdateScheduled(
        uint256 indexed id,
        uint256 newAllocation,
        uint256 delay,
        bytes32 operationId
    );
    event AllocationUpdated(uint256 indexed id, uint256 newAllocation);
    event FeeUpdateScheduled(
        uint256 newFee,
        uint256 delay,
        bytes32 operationId
    );
    event FeeUpdated(uint256 newFee);
    event FeeRecipientUpdateScheduled(
        address newFeeRecipient,
        uint256 delay,
        bytes32 operationId
    );
    event FeeRecipientUpdated(address newFeeRecipient);
    event WhitelistUpdateScheduled(
        address indexed account,
        bool status,
        uint256 delay,
        bytes32 operationId
    );
    event WhitelistUpdated(address indexed account, bool status);
}
