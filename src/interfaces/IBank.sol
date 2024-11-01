// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBank is IERC4626 {
    enum BankType {
        Public,
        Private
    }

    struct MarketAllocation {
        uint256 id;
        uint256 allocation;
    }

    function scheduleAddMarket(uint256 id, uint256 delay) external;
    function executeAddMarket(uint256 id) external;
    function cancelAddMarket(uint256 id) external;
    function scheduleRemoveMarket(uint256 id, uint256 delay) external;
    function executeRemoveMarket(uint256 id) external;
    function cancelRemoveMarket(uint256 id) external;
    function scheduleUpdateAllocations(MarketAllocation[] calldata newMarketAllocations, uint256 delay) external;
    function executeUpdateAllocations(MarketAllocation[] calldata newMarketAllocations) external;
    function cancelUpdateAllocations(MarketAllocation[] calldata newMarketAllocations) external;
    function scheduleReallocate(uint256[] calldata withdrawIds, uint256[] calldata withdrawAmounts, uint256[] calldata depositIds, uint256[] calldata depositAmounts, uint256 delay) external;
    function executeReallocate(uint256[] calldata withdrawIds, uint256[] calldata withdrawAmounts, uint256[] calldata depositIds, uint256[] calldata depositAmounts) external;
    function cancelReallocate(uint256[] calldata withdrawIds, uint256[] calldata withdrawAmounts, uint256[] calldata depositIds, uint256[] calldata depositAmounts) external;
    function scheduleSetFee(uint256 newFee, uint256 delay) external;
    function executeSetFee(uint256 newFee) external;
    function cancelSetFee(uint256 newFee) external;
    function scheduleSetFeeRecipient(address newFeeRecipient, uint256 delay) external;
    function executeSetFeeRecipient(address newFeeRecipient) external;
    function cancelSetFeeRecipient(address newFeeRecipient) external;
    function scheduleUpdateWhitelist(address account, bool status, uint256 delay) external;
    function executeUpdateWhitelist(address account, bool status) external;
    function cancelUpdateWhitelist(address account, bool status) external;
    function harvest() external;
    function getBankType() external view returns (BankType);
    function getFee() external view returns (uint256);
    function getFeeRecipient() external view returns (address);
    function getMarketAllocations() external view returns (MarketAllocation[] memory);
    function getIsMarketEnabled(uint256 id) external view returns (bool);
    function getUntitledHub() external view returns (address);
    function isWhitelisted(address account) external view returns (bool);

    event BankTypeSet(BankType bankType);
    event MarketAdditionScheduled(
        uint256 indexed id,
        uint256 delay,
        bytes32 operationId
    );
    event MarketAdded(uint256 indexed id);
    event MarketsAdditionScheduled(
        uint256[] ids,
        uint256 delay,
        bytes32 operationId
    );
    event MarketsAdded(uint256[] ids);
    event MarketRemovalScheduled(
        uint256 indexed id,
        uint256 delay,
        bytes32 operationId
    );
    event MarketRemoved(uint256 indexed id);
    event MarketsRemovalScheduled(
        uint256[] ids,
        uint256 delay,
        bytes32 operationId
    );
    event MarketsRemoved(uint256[] ids);
    event AllocationsUpdateScheduled(
        MarketAllocation[] newMarketAllocations,
        uint256 delay,
        bytes32 operationId
    );
    event AllocationsUpdated(MarketAllocation[] newMarketAllocations);
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
    event MarketAdditionCancelled(uint256 indexed id, bytes32 indexed operationId);
    event MarketsAdditionCancelled(uint256[] ids, bytes32 indexed operationId);
    event MarketRemovalCancelled(uint256 indexed id, bytes32 indexed operationId);
    event FeeUpdateCancelled(uint256 newFee, bytes32 indexed operationId);
    event FeeRecipientUpdateCancelled(address newFeeRecipient, bytes32 indexed operationId);
    event WhitelistUpdateCancelled(address account, bool status, bytes32 indexed operationId);
    event AllocationsUpdateCancelled(MarketAllocation[] newMarketAllocations, bytes32 indexed operationId);
    event ReallocationCancelled(uint256[] ids, uint256[] newAllocations, bytes32 indexed operationId);
    event ReallocateScheduled(
        uint256[] withdrawIds,
        uint256[] withdrawAmounts,
        uint256[] depositIds,
        uint256[] depositAmounts,
        uint256 delay,
        bytes32 indexed operationId
    );

    event Reallocated(
        uint256[] withdrawIds,
        uint256[] withdrawAmounts,
        uint256[] depositIds,
        uint256[] depositAmounts
    );

    event ReallocateCancelled(
        uint256[] withdrawIds,
        uint256[] withdrawAmounts,
        uint256[] depositIds,
        uint256[] depositAmounts,
        bytes32 indexed operationId
    );
}
