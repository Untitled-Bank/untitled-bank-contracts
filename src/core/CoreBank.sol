// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/ICoreBank.sol";
import "./CoreBankInternal.sol";
import "../libraries/Timelock.sol";

contract CoreBank is ICoreBank, CoreBankInternal, Timelock {
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _minDelay,
        address _initialAdmin
    )
        ERC4626(_asset)
        ERC20(_name, _symbol)
        CoreBankStorage()
        Timelock(_minDelay, _initialAdmin)
    {}

    function scheduleAddBank(
        address bank,
        uint256 allocation,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(bank != address(0), "CoreBank: Invalid bank address");
        require(!isBankEnabled[bank], "CoreBank: Bank already added");
        require(
            allocation > 0 && allocation <= BASIS_POINTS,
            "CoreBank: Invalid allocation"
        );
        require(IBank(bank).asset() == asset(), "CoreBank: Bank asset mismatch");
        require(
            IBank(address(bank)).getBankType() == IBank.BankType.Public,
            "CoreBank: Not a Public Bank"
        );

        bytes32 operationId = keccak256(abi.encode(
            "addBank",
            bank,
            allocation
        ));

        scheduleOperation(operationId, delay);

        emit BankAdditionScheduled(bank, allocation, delay, operationId);
    }

    function executeAddBank(address bank, uint256 allocation) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addBank",
            bank,
            allocation
        ));

        executeOperation(operationId);

        require(bank != address(0), "CoreBank: Invalid bank address");
        require(!isBankEnabled[bank], "CoreBank: Bank already added");
        require(
            allocation > 0 && allocation <= BASIS_POINTS,
            "CoreBank: Invalid allocation"
        );
        require(IBank(bank).asset() == asset(), "CoreBank: Bank asset mismatch");
        require(
            IBank(address(bank)).getBankType() == IBank.BankType.Public,
            "CoreBank: Not a Public Bank"
        );

        uint256 totalAllocation = allocation;
        for (uint256 i = 0; i < bankAllocations.length; i++) {
            totalAllocation += bankAllocations[i].allocation;
        }
        require(
            totalAllocation <= BASIS_POINTS,
            "CoreBank: Total allocation exceeds 100%"
        );

        bankAllocations.push(BankAllocation(IBank(bank), allocation));
        isBankEnabled[bank] = true;

        emit BankAdded(bank, allocation);
    }

    function scheduleRemoveBank(address bank, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(isBankEnabled[bank], "Bank not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "removeBank",
            bank
        ));

        scheduleOperation(operationId, delay);

        emit BankRemovalScheduled(bank, delay, operationId);
    }

    function executeRemoveBank(address bank) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeBank",
            bank
        ));

        executeOperation(operationId);

        require(isBankEnabled[bank], "Bank not enabled");

        for (uint256 i = 0; i < bankAllocations.length; i++) {
            if (address(bankAllocations[i].bank) == bank) {
                bankAllocations[i] = bankAllocations[bankAllocations.length - 1];
                bankAllocations.pop();
                break;
            }
        }
        isBankEnabled[bank] = false;

        emit BankRemoved(bank);
    }

    function scheduleUpdateAllocation(address bank, uint256 newAllocation, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(isBankEnabled[bank], "Bank not enabled");
        require(
            newAllocation > 0 && newAllocation <= BASIS_POINTS,
            "CoreBank: Invalid allocation"
        );

        bytes32 operationId = keccak256(abi.encode(
            "updateAllocation",
            bank,
            newAllocation
        ));

        scheduleOperation(operationId, delay);

        emit AllocationUpdateScheduled(bank, newAllocation, delay, operationId);
    }

    function executeUpdateAllocation(address bank, uint256 newAllocation) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateAllocation",
            bank,
            newAllocation
        ));

        executeOperation(operationId);

        require(isBankEnabled[bank], "Bank not enabled");

        uint256 totalAllocation = newAllocation;
        for (uint256 i = 0; i < bankAllocations.length; i++) {
            if (address(bankAllocations[i].bank) != bank) {
                totalAllocation += bankAllocations[i].allocation;
            }
        }
        require(
            totalAllocation <= BASIS_POINTS,
            "Total allocation exceeds 100%"
        );

        for (uint256 i = 0; i < bankAllocations.length; i++) {
            if (address(bankAllocations[i].bank) == bank) {
                bankAllocations[i].allocation = newAllocation;
                break;
            }
        }

        emit AllocationUpdated(bank, newAllocation);
    }

    function getBankAllocations()
        external
        view
        returns (BankAllocation[] memory)
    {
        return bankAllocations;
    }
}
