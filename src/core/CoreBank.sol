// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/ICoreBank.sol";
import "./CoreBankInternal.sol";
import "../libraries/Timelock.sol";
import "../libraries/math/WadMath.sol";

contract CoreBank is ICoreBank, CoreBankInternal, Timelock {
    using WadMath for uint256;

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
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(bank != address(0), "CoreBank: Invalid bank address");
        require(!isBankEnabled[bank], "CoreBank: Bank already added");
        require(IBank(bank).asset() == asset(), "CoreBank: Bank asset mismatch");
        require(
            IBank(address(bank)).getBankType() == IBank.BankType.Public,
            "CoreBank: Not a Public Bank"
        );

        bytes32 operationId = keccak256(abi.encode(
            "addBank",
            bank
        ));

        scheduleOperation(operationId, delay);

        emit BankAdditionScheduled(bank, delay, operationId);
    }

    function executeAddBank(address bank) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addBank",
            bank
        ));

        executeOperation(operationId);

        require(bank != address(0), "CoreBank: Invalid bank address");
        require(!isBankEnabled[bank], "CoreBank: Bank already added");

        require(IBank(bank).asset() == asset(), "CoreBank: Bank asset mismatch");
        require(
            IBank(address(bank)).getBankType() == IBank.BankType.Public,
            "CoreBank: Not a Public Bank"
        );

        if (bankAllocations.length == 0) {
            bankAllocations.push(BankAllocation(IBank(bank), BASIS_POINTS));
        } else {
            bankAllocations.push(BankAllocation(IBank(bank), 0));
        }
        isBankEnabled[bank] = true;

        emit BankAdded(bank);
    }

    function cancelAddBank(address bank) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addBank",
            bank
        ));

        cancelOperation(operationId);

        emit BankAdditionCancelled(bank, operationId);
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
        require(isBankEnabled[bank], "Bank not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "removeBank",
            bank
        ));

        executeOperation(operationId);

        uint256 withdrawnAssets = 0;
        uint256 removedAllocation;
        for (uint256 i = 0; i < bankAllocations.length; i++) {
            if (address(bankAllocations[i].bank) == bank) {
                removedAllocation = bankAllocations[i].allocation;
                uint256 balance = IBank(bank).balanceOf(address(this));
                if (balance > 0) {
                    uint256 assets = IBank(bank).convertToAssets(balance);
                    IBank(bank).withdraw(assets, address(this), address(this));
                    withdrawnAssets += assets;
                }

                bankAllocations[i] = bankAllocations[bankAllocations.length - 1];
                bankAllocations.pop();
                break;
            }
        }

        isBankEnabled[bank] = false;     

        if (withdrawnAssets > 0) {
            uint256 totalRemainingAllocation = BASIS_POINTS - removedAllocation;
            require(bankAllocations.length > 0, "CoreBank: Cannot remove last bank if there are still assets in the bank");
            require(totalRemainingAllocation > 0, "CoreBank: Total remaining allocation is 0");

            if (totalRemainingAllocation < BASIS_POINTS) {
                for (uint256 i = 0; i < bankAllocations.length; i++) {
                    bankAllocations[i].allocation = bankAllocations[i].allocation * BASIS_POINTS / totalRemainingAllocation;
                }
            }

            uint256 remaining = withdrawnAssets;
            for (uint256 i = 0; i < bankAllocations.length && remaining > 0; i++) {
                BankAllocation memory allocation = bankAllocations[i];
                uint256 toDeposit = withdrawnAssets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
                toDeposit = Math.min(toDeposit, remaining);

                if (toDeposit > 0) {
                    IERC20(asset()).approve(address(allocation.bank), toDeposit);
                    allocation.bank.deposit(toDeposit, address(this));
                    remaining -= toDeposit;
                }
            }
            require(remaining == 0, "Not all assets deposited");
        }

        emit BankRemoved(bank);
    }

    function cancelRemoveBank(address bank) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeBank",
            bank
        ));

        cancelOperation(operationId);

        emit BankRemovalCancelled(bank, operationId);
    }

    function scheduleUpdateAllocations(BankAllocation[] calldata newBankAllocations, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(newBankAllocations.length == bankAllocations.length, "CoreBank: Mismatched arrays");

        // Check if all markets are enabled and allocations are valid
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < newBankAllocations.length; i++) {
            require(isBankEnabled[address(newBankAllocations[i].bank)], "CoreBank: Bank not enabled");
            require(
                newBankAllocations[i].allocation > 0 && 
                newBankAllocations[i].allocation <= BASIS_POINTS, 
                "CoreBank: Invalid allocation"
            );
            totalAllocation += newBankAllocations[i].allocation;
        }
        require(totalAllocation == BASIS_POINTS, "CoreBank: Total allocation must be 100%");

        bytes32 operationId = keccak256(abi.encode(
            "updateAllocations",
            newBankAllocations
        ));

        scheduleOperation(operationId, delay);

        emit AllocationsUpdateScheduled(newBankAllocations, delay, operationId);
    }

    function executeUpdateAllocations(BankAllocation[] calldata newBankAllocations) external onlyRole(EXECUTOR_ROLE) {
        require(newBankAllocations.length == bankAllocations.length, "CoreBank: Mismatched arrays");

        bytes32 operationId = keccak256(abi.encode(
            "updateAllocations",
            newBankAllocations
        ));

        executeOperation(operationId);

        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < newBankAllocations.length; i++) {
            require(isBankEnabled[address(newBankAllocations[i].bank)], "CoreBank: Bank not enabled");
            require(
                newBankAllocations[i].allocation > 0 && 
                newBankAllocations[i].allocation <= BASIS_POINTS, 
                "CoreBank: Invalid allocation"
            );
            totalAllocation += newBankAllocations[i].allocation;
        }
        require(totalAllocation == BASIS_POINTS, "CoreBank: Total allocation must be 100%");

        delete bankAllocations;
        for (uint256 i = 0; i < newBankAllocations.length; i++) {
            bankAllocations.push(newBankAllocations[i]);
        }

        emit AllocationsUpdated(newBankAllocations);
    }

    function cancelUpdateAllocations(BankAllocation[] calldata newBankAllocations) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateAllocations",
            newBankAllocations
        ));

        cancelOperation(operationId);

        emit AllocationsUpdateCancelled(newBankAllocations, operationId);
    }

    function scheduleReallocate(
        address[] calldata withdrawBanks,
        uint256[] calldata withdrawAmounts,
        address[] calldata depositBanks,
        uint256[] calldata depositAmounts,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(withdrawBanks.length == withdrawAmounts.length, "CoreBank: Mismatched withdraw arrays");
        require(depositBanks.length == depositAmounts.length, "CoreBank: Mismatched deposit arrays");

        // Check total amounts match
        uint256 totalWithdraw = 0;
        uint256 totalDeposit = 0;
        for (uint256 i = 0; i < withdrawAmounts.length; i++) {
            require(isBankEnabled[address(withdrawBanks[i])], "CoreBank: Withdraw bank not enabled");
            totalWithdraw += withdrawAmounts[i];
        }
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            require(isBankEnabled[address(depositBanks[i])], "CoreBank: Deposit bank not enabled");
            totalDeposit += depositAmounts[i];
        }
        require(totalWithdraw == totalDeposit, "CoreBank: Mismatched total amounts");

        bytes32 operationId = keccak256(abi.encode(
            "reallocate",
            withdrawBanks,
            withdrawAmounts,
            depositBanks,
            depositAmounts
        ));

        scheduleOperation(operationId, delay);

        emit ReallocateScheduled(withdrawBanks, withdrawAmounts, depositBanks, depositAmounts, delay, operationId);
    }

    function executeReallocate(
        address[] calldata withdrawBanks,
        uint256[] calldata withdrawAmounts,
        address[] calldata depositBanks,
        uint256[] calldata depositAmounts
    ) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "reallocate",
            withdrawBanks,
            withdrawAmounts,
            depositBanks,
            depositAmounts
        ));

        executeOperation(operationId);

        // Check total amounts match
        uint256 totalWithdraw = 0;
        uint256 totalDeposit = 0;
        for (uint256 i = 0; i < withdrawAmounts.length; i++) {
            require(isBankEnabled[address(withdrawBanks[i])], "CoreBank: Withdraw bank not enabled");
            totalWithdraw += withdrawAmounts[i];
        }
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            require(isBankEnabled[address(depositBanks[i])], "CoreBank: Deposit bank not enabled");
            totalDeposit += depositAmounts[i];
        }
        require(totalWithdraw == totalDeposit, "CoreBank: Mismatched total amounts");

        // Perform withdrawals
        for (uint256 i = 0; i < withdrawBanks.length; i++) {
            if (withdrawAmounts[i] > 0) {
                IBank(withdrawBanks[i]).withdraw(
                    withdrawAmounts[i],
                    address(this),
                    address(this)
                );
            }
        }

        // Perform deposits
        for (uint256 i = 0; i < depositBanks.length; i++) {
            if (depositAmounts[i] > 0) {
                IERC20(asset()).approve(address(depositBanks[i]), depositAmounts[i]);
                IBank(depositBanks[i]).deposit(depositAmounts[i], address(this));
            }
        }

        emit ReallocateExecuted(withdrawBanks, withdrawAmounts, depositBanks, depositAmounts);
    }

    function cancelReallocate(
        address[] calldata withdrawBanks,
        uint256[] calldata withdrawAmounts,
        address[] calldata depositBanks,
        uint256[] calldata depositAmounts
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "reallocate",
            withdrawBanks,
            withdrawAmounts,
            depositBanks,
            depositAmounts
        ));
        
        cancelOperation(operationId);
        
        emit ReallocateCancelled(withdrawBanks, withdrawAmounts, depositBanks, depositAmounts, operationId);
    }

    function getBankAllocations()
        external
        view
        returns (BankAllocation[] memory)
    {
        return bankAllocations;
    }
}
