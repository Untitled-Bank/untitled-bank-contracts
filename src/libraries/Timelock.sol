// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract Timelock is AccessControlUpgradeable {
    struct TimelockOperation {
        uint256 executionTime;
        bool executed;
    }

    uint32 public minDelay;
    uint32 public constant LB_MIN_DELAY = 10 minutes;
    uint32 public constant MAX_DELAY = 30 days;

    mapping(bytes32 => TimelockOperation) public timelockOperations;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    event OperationScheduled(bytes32 indexed operationId, uint256 executionTime);
    event OperationExecuted(bytes32 indexed operationId);
    event OperationCancelled(bytes32 indexed operationId);

    error InvalidDelay();
    error AlreadyScheduled();
    error OperationNotExists();
    error AlreadyExecuted();
    error NotReady();

    function _initializeTimelock(uint32 _minDelay, address _initialAdmin) internal onlyInitializing {
        __AccessControl_init();
        
        require(_minDelay >= LB_MIN_DELAY && _minDelay <= MAX_DELAY, "Timelock: Invalid delay");        
        minDelay = _minDelay;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(PROPOSER_ROLE, _initialAdmin);
        _grantRole(EXECUTOR_ROLE, _initialAdmin);
    }

    function scheduleOperation(bytes32 operationId, uint32 delay) internal onlyRole(PROPOSER_ROLE) {
        if(delay < minDelay || delay > MAX_DELAY) revert InvalidDelay();
        if(timelockOperations[operationId].executionTime != 0) revert AlreadyScheduled();

        timelockOperations[operationId] = TimelockOperation({
            executionTime: uint256(block.timestamp + delay),
            executed: false
        });

        emit OperationScheduled(operationId, block.timestamp + delay);
    }

    function executeOperation(bytes32 operationId) internal onlyRole(EXECUTOR_ROLE) {
        TimelockOperation storage operation = timelockOperations[operationId];
        if(operation.executionTime == 0) revert OperationNotExists();
        if(operation.executed) revert AlreadyExecuted();
        if(block.timestamp < operation.executionTime) revert NotReady();

        delete timelockOperations[operationId];

        emit OperationExecuted(operationId);
    }

    function cancelOperation(bytes32 operationId) internal onlyRole(PROPOSER_ROLE) {
        TimelockOperation storage operation = timelockOperations[operationId];
        if(operation.executionTime == 0) revert OperationNotExists();
        if(operation.executed) revert AlreadyExecuted();

        delete timelockOperations[operationId];

        emit OperationCancelled(operationId);
    }

    function getOperation(bytes32 operationId) external view returns (TimelockOperation memory) {
        return timelockOperations[operationId];
    }
}
