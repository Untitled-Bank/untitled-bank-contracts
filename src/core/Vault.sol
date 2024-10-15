// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/IVault.sol";
import "./VaultInternal.sol";
import "../libraries/Timelock.sol";

contract Vault is IVault, VaultInternal, Timelock {
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        Bank _bank,
        uint256 _fee,
        address _feeRecipient,
        uint256 _minDelay,
        address _initialAdmin,
        VaultType _vaultType
    )
        ERC4626(_asset)
        ERC20(_name, _symbol)
        VaultStorage(_bank, _vaultType)        
        Timelock(_minDelay, _initialAdmin)
    {
        require(_fee <= 1000, "Fee too high"); // Max 10%
        fee = _fee;
        emit FeeUpdated(_fee);

        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);

        emit VaultTypeSet(_vaultType);

        lastTotalAssets = totalAssets();
    }

    function scheduleAddBank(
        uint256 id,
        uint256 allocation,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(bankAllocations.length < MAX_BANKS, "Vault: Max banks reached");
        require(!isBankEnabled[id], "Vault: Bank already added");
        require(
            allocation > 0 && allocation <= BASIS_POINTS,
            "Vault: Invalid allocation"
        );

        (address loanToken, , , , ) = bank.idToMarketConfigs(id);
        require(loanToken == asset(), "Vault: Vault asset mismatch");

        bytes32 operationId = keccak256(abi.encode(
            "addBank",
            id,
            allocation
        ));

        scheduleOperation(operationId, delay);

        emit BankAdditionScheduled(id, allocation, delay, operationId);
    }

    function executeAddBank(uint256 id, uint256 allocation) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addBank",
            id,
            allocation
        ));

        executeOperation(operationId);

        require(bankAllocations.length < MAX_BANKS, "Vault: Max banks reached");
        require(!isBankEnabled[id], "Vault: Bank already added");
        require(
            allocation > 0 && allocation <= BASIS_POINTS,
            "Vault: Invalid allocation"
        );

        (address loanToken, , , , ) = bank.idToMarketConfigs(id);
        require(loanToken == asset(), "Vault: Vault asset mismatch");

        bankAllocations.push(BankAllocation(id, allocation));
        isBankEnabled[id] = true;

        emit BankAdded(id, allocation);
    }

    function scheduleAddBanks(
        uint256[] calldata ids,
        uint256[] calldata allocations,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(ids.length == allocations.length, "Mismatched arrays");
        require(
            bankAllocations.length + ids.length <= MAX_BANKS,
            "Max banks would be exceeded"
        );
        for (uint256 i = 0; i < ids.length; i++) {
            require(!isBankEnabled[ids[i]], "Vault: Bank already added");
            (address loanToken, , , , ) = bank.idToMarketConfigs(ids[i]);
            require(loanToken == asset(), "Vault: Vault asset mismatch");
        }
        // allocation check
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            require(allocations[i] > 0 && allocations[i] <= BASIS_POINTS, "Vault: Invalid allocation");
            totalAllocation += allocations[i];
        }

        for (uint256 i = 0; i < bankAllocations.length; i++) {
            totalAllocation += bankAllocations[i].allocation;
        }
        require(totalAllocation <= BASIS_POINTS, "Vault: Total allocation exceeds 100%");


        bytes32 operationId = keccak256(abi.encode(
            "addBanks",
            ids,
            allocations
        ));

        scheduleOperation(operationId, delay);

        emit BanksAdditionScheduled(ids, allocations, delay, operationId);
    }

    function executeAddBanks(uint256[] calldata ids, uint256[] calldata allocations) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addBanks",
            ids,
            allocations
        ));

        executeOperation(operationId);

        for (uint256 i = 0; i < ids.length; i++) {
            require(!isBankEnabled[ids[i]], "Vault: Bank already added");
            (address loanToken, , , , ) = bank.idToMarketConfigs(ids[i]);
            require(loanToken == asset(), "Vault: Vault asset mismatch");
        }
        // allocation check
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            require(allocations[i] > 0 && allocations[i] <= BASIS_POINTS, "Vault: Invalid allocation");
            totalAllocation += allocations[i];
        }

        for (uint256 i = 0; i < bankAllocations.length; i++) {
            totalAllocation += bankAllocations[i].allocation;
        }
        require(totalAllocation <= BASIS_POINTS, "Vault: Total allocation exceeds 100%");

        for (uint256 i = 0; i < ids.length; i++) {
            require(!isBankEnabled[ids[i]], "Bank already added");
            bankAllocations.push(BankAllocation(ids[i], allocations[i]));
            isBankEnabled[ids[i]] = true;
        }

        emit BanksAdded(ids, allocations);
    }


    function scheduleRemoveBank(uint256 id, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(isBankEnabled[id], "Bank not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "removeBank",
            id
        ));

        scheduleOperation(operationId, delay);

        emit BankRemovalScheduled(id, delay, operationId);
    }

    function executeRemoveBank(uint256 id) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeBank",
            id
        ));

        executeOperation(operationId);

        require(isBankEnabled[id], "Bank not enabled");

        for (uint256 i = 0; i < bankAllocations.length; i++) {
            if (bankAllocations[i].id == id) {
                bankAllocations[i] = bankAllocations[bankAllocations.length - 1];
                bankAllocations.pop();
                break;
            }
        }
        isBankEnabled[id] = false;

        emit BankRemoved(id);
    }

   function scheduleRemoveBanks(uint256[] calldata ids, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeBanks",
            ids
        ));

        scheduleOperation(operationId, delay);

        emit BanksRemovalScheduled(ids, delay, operationId);
    }

    function executeRemoveBanks(uint256[] calldata ids) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeBanks",
            ids
        ));

        executeOperation(operationId);

        for (uint256 j = 0; j < ids.length; j++) {
            uint256 id = ids[j];
            require(isBankEnabled[id], "Bank not enabled");

            for (uint256 i = 0; i < bankAllocations.length; i++) {
                if (bankAllocations[i].id == id) {
                    bankAllocations[i] = bankAllocations[bankAllocations.length - 1];
                    bankAllocations.pop();
                    break;
                }
            }
            isBankEnabled[id] = false;
        }

        emit BanksRemoved(ids);
    }

    function scheduleUpdateAllocation(uint256 id, uint256 newAllocation, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(isBankEnabled[id], "Bank not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "updateAllocation",
            id,
            newAllocation
        ));

        uint256 totalAllocation = newAllocation;
        for (uint256 i = 0; i < bankAllocations.length; i++) {
            if (bankAllocations[i].id != id) {
                totalAllocation += bankAllocations[i].allocation;
            }
        }
        require(totalAllocation <= BASIS_POINTS, "Vault: Total allocation exceeds 100%");

        scheduleOperation(operationId, delay);

        emit AllocationUpdateScheduled(id, newAllocation, delay, operationId);
    }

    function executeUpdateAllocation(uint256 id, uint256 newAllocation) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateAllocation",
            id,
            newAllocation
        ));

        executeOperation(operationId);

        require(isBankEnabled[id], "Bank not enabled");
        uint256 totalAllocation = newAllocation;
        for (uint256 i = 0; i < bankAllocations.length; i++) {
            if (bankAllocations[i].id != id) {
                totalAllocation += bankAllocations[i].allocation;
            }
        }
        require(totalAllocation <= BASIS_POINTS, "Vault: Total allocation exceeds 100%");

        for (uint256 i = 0; i < bankAllocations.length; i++) {
            if (bankAllocations[i].id == id) {
                bankAllocations[i].allocation = newAllocation;
                break;
            }
        }

        emit AllocationUpdated(id, newAllocation);
    }
    function scheduleSetFee(uint256 newFee, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(newFee <= 1000, "Fee too high"); // Max 10%

        bytes32 operationId = keccak256(abi.encode(
            "setFee",
            newFee
        ));

        scheduleOperation(operationId, delay);

        emit FeeUpdateScheduled(newFee, delay, operationId);
    }

    function executeSetFee(uint256 newFee) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "setFee",
            newFee
        ));

        executeOperation(operationId);

        require(newFee <= 1000, "Fee too high"); // Max 10%
        _accrueFee();
        fee = newFee;
        emit FeeUpdated(newFee);
    }

    function scheduleSetFeeRecipient(address newFeeRecipient, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "setFeeRecipient",
            newFeeRecipient
        ));

        scheduleOperation(operationId, delay);

        emit FeeRecipientUpdateScheduled(newFeeRecipient, delay, operationId);
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
    function scheduleUpdateWhitelist(
        address account,
        bool status,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(vaultType == VaultType.Private, "Not a Private Vault");
        bytes32 operationId = keccak256(abi.encode(
            "updateWhitelist",
            account,
            status
        ));
        scheduleOperation(operationId, delay);
        emit WhitelistUpdateScheduled(account, status, delay, operationId);
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

    function harvest() external {
        _accrueFee();
    }

    function getVaultType() external view returns (VaultType) {
        return vaultType;
    }

    function getFee() external view returns (uint256) {
        return fee;
    }

    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }

    function getBankAllocations()
        external
        view
        returns (BankAllocation[] memory)
    {
        return bankAllocations;
    }

    function isWhitelisted(address account) external view returns (bool) {
        return whitelist[account];
    }

}
