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

    function scheduleAddMarket(uint256 id, uint256 allocation, uint256 delay) external;
    function executeAddMarket(uint256 id, uint256 allocation) external;
    function scheduleAddMarkets(uint256[] calldata ids, uint256[] calldata allocations, uint256 delay) external;
    function executeAddMarkets(uint256[] calldata ids, uint256[] calldata allocations) external;
    function scheduleRemoveMarket(uint256 id, uint256 delay) external;
    function executeRemoveMarket(uint256 id) external;
    function scheduleRemoveMarkets(uint256[] calldata ids, uint256 delay) external;
    function executeRemoveMarkets(uint256[] calldata ids) external;
    function scheduleUpdateAllocation(uint256 id, uint256 newAllocation, uint256 delay) external;
    function executeUpdateAllocation(uint256 id, uint256 newAllocation) external;
    function scheduleSetFee(uint256 newFee, uint256 delay) external;
    function executeSetFee(uint256 newFee) external;
    function scheduleSetFeeRecipient(address newFeeRecipient, uint256 delay) external;
    function executeSetFeeRecipient(address newFeeRecipient) external;
    function scheduleUpdateWhitelist(address account, bool status, uint256 delay) external;
    function executeUpdateWhitelist(address account, bool status) external;
    function harvest() external;
    function getBankType() external view returns (BankType);
    function getFee() external view returns (uint256);
    function getFeeRecipient() external view returns (address);
    function getMarketAllocations() external view returns (MarketAllocation[] memory);
    function isWhitelisted(address account) external view returns (bool);

    event BankTypeSet(BankType bankType);
    event MarketAdditionScheduled(
        uint256 indexed id,
        uint256 allocation,
        uint256 delay,
        bytes32 operationId
    );
    event MarketAdded(uint256 indexed id, uint256 allocation);
    event MarketsAdditionScheduled(
        uint256[] ids,
        uint256[] allocations,
        uint256 delay,
        bytes32 operationId
    );
    event MarketsAdded(uint256[] ids, uint256[] allocations);
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
