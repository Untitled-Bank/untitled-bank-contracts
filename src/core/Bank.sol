// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IBank.sol";
import "./BankInternal.sol";
import "../libraries/Timelock.sol";
import "../libraries/math/WadMath.sol";
import "../libraries/BankActions.sol";

contract Bank is 
    Initializable, 
    UUPSUpgradeable,     
    IBank, 
    BankInternal, 
    Timelock 
{
    using BankActions for *;
    using WadMath for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        UntitledHub _untitledHub,
        uint256 _fee,
        address _feeRecipient,
        uint32 _minDelay,
        address _initialAdmin,
        IBank.BankType _bankType
    ) public initializer {
        __ERC4626_init(_asset);
        __ERC20_init(_name, _symbol);
        __AccessControl_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        
        if (_fee > 1000) revert FeeTooHigh();
        fee = _fee;
        emit FeeUpdated(_fee);

        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);

        _initializeTimelock(_minDelay, _initialAdmin);
        _initializeBankStorage(_untitledHub, _bankType);

        emit BankTypeSet(_bankType);

        lastTotalAssets = totalAssets();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function scheduleAddMarket(
        uint256 id,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addMarket",
            id
        ));

        scheduleOperation(operationId, uint32(delay));

        emit MarketAdditionScheduled(id, uint32(delay), operationId);
    }

    function executeAddMarket(uint256 id) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addMarket",
            id
        ));

        executeOperation(operationId);

        BankActions.executeAddMarket(
            id,
            marketAllocations,
            marketIdToIndex,
            isMarketEnabled,
            untitledHub,
            asset()
        );
    }

    function cancelAddMarket(uint256 id) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addMarket",
            id
        ));
        
        cancelOperation(operationId);
        
        emit MarketAdditionCancelled(id, operationId);
    }

    function scheduleRemoveMarket(uint256 id, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeMarket",
            id
        ));

        scheduleOperation(operationId, uint32(delay));

        emit MarketRemovalScheduled(id, uint32(delay), operationId);
    }

    function executeRemoveMarket(uint256 id) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeMarket",
            id
        ));

        executeOperation(operationId);

        BankActions.executeRemoveMarket(
            id,
            marketAllocations,
            marketIdToIndex,
            isMarketEnabled,
            untitledHub,
            asset()
        );
    }

    function cancelRemoveMarket(uint256 id) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeMarket",
            id
        ));
        
        cancelOperation(operationId);
        
        emit MarketRemovalCancelled(id, operationId);
    }

    function scheduleUpdateAllocations(
        MarketAllocation[] calldata newMarketAllocations,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateAllocations",
            newMarketAllocations
        ));

        scheduleOperation(operationId, uint32(delay));

        emit AllocationsUpdateScheduled(newMarketAllocations, uint32(delay), operationId);
    }

    function executeUpdateAllocations(
        MarketAllocation[] calldata newMarketAllocations
    ) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateAllocations",
            newMarketAllocations
        ));

        executeOperation(operationId);

        BankActions.executeUpdateAllocations(
            newMarketAllocations,
            marketAllocations,
            isMarketEnabled
        );
    }

    function cancelUpdateAllocations(
        MarketAllocation[] calldata newMarketAllocations
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateAllocations",
            newMarketAllocations
        ));
        
        cancelOperation(operationId);
        
        emit AllocationsUpdateCancelled(newMarketAllocations, operationId);
    }

    function scheduleReallocate(
        uint256[] calldata withdrawIds,
        uint256[] calldata withdrawAmounts,
        uint256[] calldata depositIds,
        uint256[] calldata depositAmounts,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "reallocate",
            withdrawIds,
            withdrawAmounts,
            depositIds,
            depositAmounts
        ));

        scheduleOperation(operationId, uint32(delay));

        emit ReallocateScheduled(withdrawIds, withdrawAmounts, depositIds, depositAmounts, uint32(delay), operationId);
    }

    function executeReallocate(
        uint256[] calldata withdrawIds,
        uint256[] calldata withdrawAmounts,
        uint256[] calldata depositIds,
        uint256[] calldata depositAmounts
    ) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "reallocate",
            withdrawIds,
            withdrawAmounts,
            depositIds,
            depositAmounts
        ));

        executeOperation(operationId);

        BankActions.executeReallocate(
            withdrawIds,
            withdrawAmounts,
            depositIds,
            depositAmounts,
            isMarketEnabled,
            untitledHub,
            asset()
        );
    }

    function cancelReallocate(
        uint256[] calldata withdrawIds,
        uint256[] calldata withdrawAmounts,
        uint256[] calldata depositIds,
        uint256[] calldata depositAmounts
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "reallocate",
            withdrawIds,
            withdrawAmounts,
            depositIds,
            depositAmounts
        ));
        
        cancelOperation(operationId);
        
        emit ReallocateCancelled(withdrawIds, withdrawAmounts, depositIds, depositAmounts, operationId);
    }

    function scheduleSetFee(uint256 newFee, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "setFee",
            newFee
        ));

        scheduleOperation(operationId, uint32(delay));

        emit FeeUpdateScheduled(newFee, uint32(delay), operationId);
    }

    function executeSetFee(uint256 newFee) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "setFee",
            newFee
        ));

        executeOperation(operationId);

        if (newFee > 1000) revert FeeTooHigh();
        _accrueFee();
        fee = newFee;
        emit FeeUpdated(newFee);
    }

    function cancelSetFee(uint256 newFee) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "setFee",
            newFee
        ));
        
        cancelOperation(operationId);
        
        emit FeeUpdateCancelled(newFee, operationId);
    }

    function scheduleSetFeeRecipient(address newFeeRecipient, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "setFeeRecipient",
            newFeeRecipient
        ));

        scheduleOperation(operationId, uint32(delay));

        emit FeeRecipientUpdateScheduled(newFeeRecipient, uint32(delay), operationId);
    }

    function executeSetFeeRecipient(address newFeeRecipient) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "setFeeRecipient",
            newFeeRecipient
        ));

        executeOperation(operationId);

        _accrueFee();
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(newFeeRecipient);
    }

    function cancelSetFeeRecipient(address newFeeRecipient) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "setFeeRecipient",
            newFeeRecipient
        ));
        
        cancelOperation(operationId);
        
        emit FeeRecipientUpdateCancelled(newFeeRecipient, operationId);
    }

    function scheduleUpdateWhitelist(
        address account,
        bool status,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateWhitelist",
            account,
            status
        ));
        scheduleOperation(operationId, uint32(delay));
        emit WhitelistUpdateScheduled(account, status, uint32(delay), operationId);
    }

    function executeUpdateWhitelist(address account, bool status) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateWhitelist",
            account,
            status
        ));
        executeOperation(operationId);
        whitelist[account] = status;
        emit WhitelistUpdated(account, status);
    }

    function cancelUpdateWhitelist(address account, bool status) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateWhitelist",
            account,
            status
        ));
        
        cancelOperation(operationId);
        
        emit WhitelistUpdateCancelled(account, status, operationId);
    }

    function harvest() external {
        _accrueFee();
    }

    function getBankType() external view returns (BankType) {
        return bankType;
    }

    function getFee() external view returns (uint256) {
        return fee;
    }

    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }

    function getMarketAllocations()
        external
        view
        returns (MarketAllocation[] memory)
    {
        return marketAllocations;
    }

    function getIsMarketEnabled(uint256 id) external view returns (bool) {
        return isMarketEnabled[id];
    }

    function getUntitledHub() external view returns (address) {
        return address(untitledHub);
    }

    function isWhitelisted(address account) external view returns (bool) {
        return whitelist[account];
    }
}