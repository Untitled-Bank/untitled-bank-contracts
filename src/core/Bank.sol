// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/IBank.sol";
import "./BankInternal.sol";
import "../libraries/Timelock.sol";
import "../libraries/math/WadMath.sol";

contract Bank is IBank, BankInternal, Timelock {
    using WadMath for uint256;

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        UntitledHub _untitledHub,
        uint256 _fee,
        address _feeRecipient,
        uint256 _minDelay,
        address _initialAdmin,
        IBank.BankType _bankType
    )
        ERC4626(_asset)
        ERC20(_name, _symbol)
        BankStorage(_untitledHub, _bankType)        
        Timelock(_minDelay, _initialAdmin)
    {
        require(_fee <= 1000, "Fee too high"); // Max 10%
        fee = _fee;
        emit FeeUpdated(_fee);

        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);

        emit BankTypeSet(_bankType);

        lastTotalAssets = totalAssets();
    }

    function scheduleAddMarket(
        uint256 id,
        uint256 allocation,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(marketAllocations.length < MAX_MARKETS, "Bank: Max markets reached");
        require(!isMarketEnabled[id], "Bank: Market already added");
        require(
            allocation > 0 && allocation <= BASIS_POINTS,
            "Bank: Invalid allocation"
        );

        (address loanToken, , , , ) = untitledHub.idToMarketConfigs(id);
        require(loanToken == asset(), "Bank: Asset mismatch");

        bytes32 operationId = keccak256(abi.encode(
            "addMarket",
            id,
            allocation
        ));

        scheduleOperation(operationId, delay);

        emit MarketAdditionScheduled(id, allocation, delay, operationId);
    }

    function executeAddMarket(uint256 id, uint256 allocation) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addMarket",
            id,
            allocation
        ));

        executeOperation(operationId);

        require(marketAllocations.length < MAX_MARKETS, "Bank: Max markets reached");
        require(!isMarketEnabled[id], "Bank: Market already added");
        require(
            allocation > 0 && allocation <= BASIS_POINTS,
            "Bank: Invalid allocation"
        );

        (address loanToken, , , , ) = untitledHub.idToMarketConfigs(id);
        require(loanToken == asset(), "Bank: Asset mismatch");

        marketAllocations.push(MarketAllocation(id, allocation));
        isMarketEnabled[id] = true;

        emit MarketAdded(id, allocation);
    }

    function cancelAddMarket(uint256 id, uint256 allocation) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addMarket",
            id,
            allocation
        ));
        
        cancelOperation(operationId);
        
        emit MarketAdditionCancelled(id, allocation, operationId);
    }


    function scheduleAddMarkets(
        uint256[] calldata ids,
        uint256[] calldata allocations,
        uint256 delay
    ) external onlyRole(PROPOSER_ROLE) {
        require(ids.length == allocations.length, "Bank: Mismatched arrays");
        require(
            marketAllocations.length + ids.length <= MAX_MARKETS,
            "Bank: Max markets reached"
        );
        for (uint256 i = 0; i < ids.length; i++) {
            require(!isMarketEnabled[ids[i]], "Bank: Market already added");
            (address loanToken, , , , ) = untitledHub.idToMarketConfigs(ids[i]);
            require(loanToken == asset(), "Bank: Asset mismatch");
        }
        // allocation check
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            require(allocations[i] > 0 && allocations[i] <= BASIS_POINTS, "Bank: Invalid allocation");
            totalAllocation += allocations[i];
        }

        for (uint256 i = 0; i < marketAllocations.length; i++) {
            totalAllocation += marketAllocations[i].allocation;
        }
        require(totalAllocation <= BASIS_POINTS, "Bank: Total allocation exceeds 100%");


        bytes32 operationId = keccak256(abi.encode(
            "addMarkets",
            ids,
            allocations
        ));

        scheduleOperation(operationId, delay);

        emit MarketsAdditionScheduled(ids, allocations, delay, operationId);
    }

    function executeAddMarkets(uint256[] calldata ids, uint256[] calldata allocations) external onlyRole(EXECUTOR_ROLE) {
        require(
            marketAllocations.length + ids.length <= MAX_MARKETS,
            "Bank: Max markets reached"
        );

        bytes32 operationId = keccak256(abi.encode(
            "addMarkets",
            ids,
            allocations
        ));

        executeOperation(operationId);

        for (uint256 i = 0; i < ids.length; i++) {
            require(!isMarketEnabled[ids[i]], "Bank: Market already added");
            (address loanToken, , , , ) = untitledHub.idToMarketConfigs(ids[i]);
            require(loanToken == asset(), "Bank: Asset mismatch");
        }
        // allocation check
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            require(allocations[i] > 0 && allocations[i] <= BASIS_POINTS, "Bank: Invalid allocation");
            totalAllocation += allocations[i];
        }

        for (uint256 i = 0; i < marketAllocations.length; i++) {
            totalAllocation += marketAllocations[i].allocation;
        }
        require(totalAllocation <= BASIS_POINTS, "Bank: Total allocation exceeds 100%");

        for (uint256 i = 0; i < ids.length; i++) {
            require(!isMarketEnabled[ids[i]], "Bank: Market already added");
            marketAllocations.push(MarketAllocation(ids[i], allocations[i]));
            isMarketEnabled[ids[i]] = true;
        }

        emit MarketsAdded(ids, allocations);
    }

    function cancelAddMarkets(uint256[] calldata ids, uint256[] calldata allocations) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "addMarkets",
            ids,
            allocations
        ));
        
        cancelOperation(operationId);
        
        emit MarketsAdditionCancelled(ids, allocations, operationId);
    }

    function scheduleRemoveMarket(uint256 id, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(isMarketEnabled[id], "Bank: Market not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "removeMarket",
            id
        ));

        scheduleOperation(operationId, delay);

        emit MarketRemovalScheduled(id, delay, operationId);
    }

    function executeRemoveMarket(uint256 id) external onlyRole(EXECUTOR_ROLE) {
        require(isMarketEnabled[id], "Bank: Market not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "removeMarket",
            id
        ));

        executeOperation(operationId);
        
        // Find and withdraw assets from the market being removed
        uint256 withdrawnAssets = 0;
        for (uint256 i = 0; i < marketAllocations.length; i++) {
            if (marketAllocations[i].id == id) {
                (uint256 supplyShares, , ) = untitledHub.position(id, address(this));                
                if (supplyShares > 0) {
                    (uint256 assets, ) = untitledHub.withdraw(id, type(uint256).max, address(this));
                    withdrawnAssets += assets;
                }
                
                // Remove market from allocations
                marketAllocations[i] = marketAllocations[marketAllocations.length - 1];
                marketAllocations.pop();
                break;
            }
        }
        
        isMarketEnabled[id] = false;
        
        if (withdrawnAssets > 0) {            
            if(marketAllocations.length == 0) {
                revert("Bank: Cannot remove last market if there are still assets in the bank");
            }
            uint256 remaining = withdrawnAssets;
            for (uint256 i = 0; i < marketAllocations.length && remaining > 0; i++) {
                IBank.MarketAllocation memory allocation = marketAllocations[i];
                uint256 toDeposit = withdrawnAssets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
                toDeposit = Math.min(toDeposit, remaining);

                if (toDeposit > 0) {
                    IERC20(asset()).approve(address(untitledHub), toDeposit);
                    untitledHub.supply(allocation.id, toDeposit, "");
                    remaining -= toDeposit;
                }
            }
            require(remaining == 0, "Not all assets deposited");
        }

        emit MarketRemoved(id);
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
        require(newMarketAllocations.length == marketAllocations.length, "Bank: Mismatched arrays");

        // Check if all markets are enabled and allocations are valid
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < newMarketAllocations.length; i++) {
            require(isMarketEnabled[newMarketAllocations[i].id], "Bank: Market not enabled");
            require(
                newMarketAllocations[i].allocation > 0 && 
                newMarketAllocations[i].allocation <= BASIS_POINTS, 
                "Bank: Invalid allocation"
            );
            totalAllocation += newMarketAllocations[i].allocation;
        }
        require(totalAllocation == BASIS_POINTS, "Bank: Total allocation must be 100%");

        bytes32 operationId = keccak256(abi.encode(
            "updateAllocations",
            newMarketAllocations
        ));

        scheduleOperation(operationId, delay);

        emit AllocationsUpdateScheduled(newMarketAllocations, delay, operationId);
    }

    function executeUpdateAllocations(
        MarketAllocation[] calldata newMarketAllocations
    ) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "updateAllocations",
            newMarketAllocations
        ));

        executeOperation(operationId);

        require(newMarketAllocations.length == marketAllocations.length, "Bank: Mismatched arrays");
        // Check if all markets are enabled and allocations are valid
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < newMarketAllocations.length; i++) {
            require(isMarketEnabled[newMarketAllocations[i].id], "Bank: Market not enabled");
            require(
                newMarketAllocations[i].allocation > 0 && 
                newMarketAllocations[i].allocation <= BASIS_POINTS, 
                "Bank: Invalid allocation"
            );
            totalAllocation += newMarketAllocations[i].allocation;
        }
        require(totalAllocation == BASIS_POINTS, "Bank: Total allocation must be 100%");

        // Update allocations
        delete marketAllocations;
        for (uint256 i = 0; i < newMarketAllocations.length; i++) {
            marketAllocations.push(newMarketAllocations[i]);
        }

        emit AllocationsUpdated(newMarketAllocations);
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
        require(withdrawIds.length == withdrawAmounts.length, "Bank: Mismatched withdraw arrays");
        require(depositIds.length == depositAmounts.length, "Bank: Mismatched deposit arrays");

        // Check if all markets are enabled
        for (uint256 i = 0; i < withdrawIds.length; i++) {
            require(isMarketEnabled[withdrawIds[i]], "Bank: Withdraw market not enabled");
        }
        for (uint256 i = 0; i < depositIds.length; i++) {
            require(isMarketEnabled[depositIds[i]], "Bank: Deposit market not enabled");
        }

        // Check total amounts match
        uint256 totalWithdraw = 0;
        uint256 totalDeposit = 0;
        for (uint256 i = 0; i < withdrawAmounts.length; i++) {
            totalWithdraw += withdrawAmounts[i];
        }
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            totalDeposit += depositAmounts[i];
        }
        require(totalWithdraw == totalDeposit, "Bank: Mismatched total amounts");

        bytes32 operationId = keccak256(abi.encode(
            "reallocate",
            withdrawIds,
            withdrawAmounts,
            depositIds,
            depositAmounts
        ));

        scheduleOperation(operationId, delay);

        emit ReallocateScheduled(withdrawIds, withdrawAmounts, depositIds, depositAmounts, delay, operationId);
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

        require(withdrawIds.length == withdrawAmounts.length, "Bank: Mismatched withdraw arrays");
        require(depositIds.length == depositAmounts.length, "Bank: Mismatched deposit arrays");

        // Check if all markets are enabled
        for (uint256 i = 0; i < withdrawIds.length; i++) {
            require(isMarketEnabled[withdrawIds[i]], "Bank: Withdraw market not enabled");
        }
        for (uint256 i = 0; i < depositIds.length; i++) {
            require(isMarketEnabled[depositIds[i]], "Bank: Deposit market not enabled");
        }

        // Check and track total amounts
        uint256 totalWithdraw = 0;
        uint256 totalDeposit = 0;
        for (uint256 i = 0; i < withdrawAmounts.length; i++) {
            totalWithdraw += withdrawAmounts[i];
        }
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            totalDeposit += depositAmounts[i];
        }
        require(totalWithdraw == totalDeposit, "Bank: Mismatched total amounts");

        // Perform withdrawals
        for (uint256 i = 0; i < withdrawIds.length; i++) {
            if (withdrawAmounts[i] > 0) {
                untitledHub.withdraw(withdrawIds[i], withdrawAmounts[i], address(this));
            }
        }

        // Perform deposits
        for (uint256 i = 0; i < depositIds.length; i++) {
            if (depositAmounts[i] > 0) {
                IERC20(asset()).approve(address(untitledHub), depositAmounts[i]);
                untitledHub.supply(depositIds[i], depositAmounts[i], "");
            }
        }

        emit Reallocated(withdrawIds, withdrawAmounts, depositIds, depositAmounts);
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
        require(newFee <= 1000, "Bank: Fee too high"); // Max 10%

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

        require(newFee <= 1000, "Bank: Fee too high"); // Max 10%
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
        require(bankType == BankType.Private, "Bank: Not a Private Bank");
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

    function isWhitelisted(address account) external view returns (bool) {
        return whitelist[account];
    }
}