// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract Timelock is AccessControl {
    struct TimelockOperation {
        bytes32 id;
        uint256 executionTime;
        bool executed;
    }

    uint256 public minDelay;
    uint256 public constant LB_MIN_DELAY = 10 minutes;
    uint256 public constant MAX_DELAY = 30 days;

    mapping(bytes32 => TimelockOperation) public timelockOperations;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    event OperationScheduled(bytes32 indexed operationId, uint256 executionTime);
    event OperationExecuted(bytes32 indexed operationId);
    event OperationCancelled(bytes32 indexed operationId);

    constructor(uint256 _minDelay, address _initialAdmin) {
        require(_minDelay >= LB_MIN_DELAY && _minDelay <= MAX_DELAY, "Timelock: Invalid delay");        
        minDelay = _minDelay;
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(PROPOSER_ROLE, _initialAdmin);
        _grantRole(EXECUTOR_ROLE, _initialAdmin);
    }

    function scheduleOperation(bytes32 operationId, uint256 delay) internal onlyRole(PROPOSER_ROLE) {
        require(delay >= minDelay && delay <= MAX_DELAY, "Timelock: Invalid delay");
        require(timelockOperations[operationId].id == bytes32(0), "Timelock: Operation already scheduled");

        uint256 executionTime = block.timestamp + delay;
        timelockOperations[operationId] = TimelockOperation({
            id: operationId,
            executionTime: executionTime,
            executed: false
        });

        emit OperationScheduled(operationId, executionTime);
    }

    function executeOperation(bytes32 operationId) internal onlyRole(EXECUTOR_ROLE) {
        TimelockOperation storage operation = timelockOperations[operationId];
        require(operation.id != bytes32(0), "Timelock: Operation doesn't exist");
        require(!operation.executed, "Timelock: Operation already executed");
        require(block.timestamp >= operation.executionTime, "Timelock: Operation is not ready for execution");

        operation.executed = true;
        delete timelockOperations[operationId];

        emit OperationExecuted(operationId);
    }

    function cancelOperation(bytes32 operationId) internal onlyRole(PROPOSER_ROLE) {
        TimelockOperation storage operation = timelockOperations[operationId];
        require(operation.id != bytes32(0), "Timelock: Operation doesn't exist");
        require(!operation.executed, "Timelock: Operation already executed");

        delete timelockOperations[operationId];

        emit OperationCancelled(operationId);
    }

    function updateDelay(uint256 newMinDelay) internal onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMinDelay >= LB_MIN_DELAY && newMinDelay <= MAX_DELAY, "Timelock: Invalid delay");
        minDelay = newMinDelay;
    }

    function getOperation(bytes32 operationId) public view returns (TimelockOperation memory) {
        return timelockOperations[operationId];
    }
}
