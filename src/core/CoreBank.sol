// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../interfaces/ICoreBank.sol";
import "./CoreBankInternal.sol";
import "../libraries/Timelock.sol";
import "../libraries/math/WadMath.sol";

contract CoreBank is 
    Initializable,
    UUPSUpgradeable,
    ICoreBank, 
    CoreBankInternal, 
    Timelock 
{
    using WadMath for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint32 _minDelay,
        address _initialAdmin
    ) public initializer {
        __ERC4626_init(_asset);
        __ERC20_init(_name, _symbol);
        __AccessControl_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);

        _initializeTimelock(_minDelay, _initialAdmin);
        _initializeCoreBankStorage();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function scheduleAddBank(
        address bank,
        uint32 delay
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addBank",
            bank
        ));

        scheduleOperation(operationId, uint32(delay));

        emit BankAdditionScheduled(bank, uint32(delay), operationId);
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
            bankToIndex[bank] = 0;
        } else {
            bankToIndex[bank] = bankAllocations.length;
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

    function scheduleRemoveBank(address bank, uint32 delay) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeBank",
            bank
        ));

        scheduleOperation(operationId, uint32(delay));

        emit BankRemovalScheduled(bank, uint32(delay), operationId);
    }

    function executeRemoveBank(address bank) external onlyRole(EXECUTOR_ROLE) {
        require(isBankEnabled[bank], "Bank not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "removeBank",
            bank
        ));

        executeOperation(operationId);

        uint256 index = bankToIndex[bank];
        require(index < bankAllocations.length && address(bankAllocations[index].bank) == bank, "CoreBank: Bank index mismatch");

        uint256 removedAllocation = bankAllocations[index].allocation;
        uint256 balance = IBank(bank).balanceOf(address(this));
        uint256 withdrawnAssets = 0;
        if (balance > 0) {
            uint256 assets = IBank(bank).convertToAssets(balance);
            IBank(bank).withdraw(assets, address(this), address(this));
            withdrawnAssets += assets;
        }

        uint256 lastIndex = bankAllocations.length - 1;
        if (index != lastIndex) {
            bankAllocations[index] = bankAllocations[lastIndex];
            bankToIndex[address(bankAllocations[lastIndex].bank)] = index;
        }
        bankAllocations.pop();
        delete bankToIndex[bank];
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
            // Handle all banks except the last one
            for (uint256 i = 0; i < bankAllocations.length - 1 && remaining > 0; i++) {
                BankAllocation memory allocation = bankAllocations[i];
                uint256 toDeposit = withdrawnAssets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
                toDeposit = Math.min(toDeposit, remaining);

                if (toDeposit > 0) {
                    IERC20(asset()).approve(address(allocation.bank), toDeposit);
                    allocation.bank.deposit(toDeposit, address(this));
                    remaining -= toDeposit;
                }
            }

            // Handle the last bank - deposit all remaining assets
            if (remaining > 0 && bankAllocations.length > 0) {
                BankAllocation memory lastAllocation = bankAllocations[bankAllocations.length - 1];
                IERC20(asset()).approve(address(lastAllocation.bank), remaining);
                lastAllocation.bank.deposit(remaining, address(this));
            }
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

    function scheduleUpdateAllocations(BankAllocation[] calldata newBankAllocations, uint32 delay) external onlyRole(PROPOSER_ROLE) {
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

        scheduleOperation(operationId, uint32(delay));

        emit AllocationsUpdateScheduled(newBankAllocations, uint32(delay), operationId);
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
        uint32 delay
    ) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "reallocate",
            withdrawBanks,
            withdrawAmounts,
            depositBanks,
            depositAmounts
        ));

        scheduleOperation(operationId, uint32(delay));

        emit ReallocateScheduled(withdrawBanks, withdrawAmounts, depositBanks, depositAmounts, uint32(delay), operationId);
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
        uint256 len = withdrawAmounts.length;

        // Perform withdrawals
        for (uint256 i = 0; i < len; i++) {
            require(isBankEnabled[address(withdrawBanks[i])], "CoreBank: Withdraw bank not enabled");
            if (withdrawAmounts[i] > 0) {
                IBank(withdrawBanks[i]).withdraw(
                    withdrawAmounts[i],
                    address(this),
                    address(this)
                );
                totalWithdraw += withdrawAmounts[i];
            }
        }

        // Perform deposits
        for (uint256 i = 0; i < len; i++) {
            require(isBankEnabled[address(depositBanks[i])], "CoreBank: Deposit bank not enabled");
            if (depositAmounts[i] > 0) {
                IERC20(asset()).approve(address(depositBanks[i]), depositAmounts[i]);
                IBank(depositBanks[i]).deposit(depositAmounts[i], address(this));
                totalDeposit += depositAmounts[i];
            }
        }

        require(totalWithdraw == totalDeposit, "CoreBank: Mismatched total amounts");

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
