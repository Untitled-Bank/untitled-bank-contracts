// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/IBank.sol";
import "./BankInternal.sol";
import "../libraries/Timelock.sol";

contract Bank is IBank, BankInternal, Timelock {
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


    function scheduleRemoveMarket(uint256 id, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(isMarketEnabled[id], "Market not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "removeMarket",
            id
        ));

        scheduleOperation(operationId, delay);

        emit MarketRemovalScheduled(id, delay, operationId);
    }

    function executeRemoveMarket(uint256 id) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeMarket",
            id
        ));

        executeOperation(operationId);

        require(isMarketEnabled[id], "Bank: Market not enabled");

        for (uint256 i = 0; i < marketAllocations.length; i++) {
            if (marketAllocations[i].id == id) {
                marketAllocations[i] = marketAllocations[marketAllocations.length - 1];
                marketAllocations.pop();
                break;
            }
        }
        isMarketEnabled[id] = false;

        emit MarketRemoved(id);
    }

   function scheduleRemoveMarkets(uint256[] calldata ids, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeMarkets",
            ids
        ));

        scheduleOperation(operationId, delay);

        emit MarketsRemovalScheduled(ids, delay, operationId);
    }

    function executeRemoveMarkets(uint256[] calldata ids) external onlyRole(EXECUTOR_ROLE) {
        bytes32 operationId = keccak256(abi.encode(
            "removeMarkets",
            ids
        ));

        executeOperation(operationId);

        for (uint256 j = 0; j < ids.length; j++) {
            uint256 id = ids[j];
            require(isMarketEnabled[id], "Bank: Market not enabled");

            for (uint256 i = 0; i < marketAllocations.length; i++) {
                if (marketAllocations[i].id == id) {
                    marketAllocations[i] = marketAllocations[marketAllocations.length - 1];
                    marketAllocations.pop();
                    break;
                }
            }
            isMarketEnabled[id] = false;
        }

        emit MarketsRemoved(ids);
    }

    function scheduleUpdateAllocation(uint256 id, uint256 newAllocation, uint256 delay) external onlyRole(PROPOSER_ROLE) {
        require(isMarketEnabled[id], "Bank: Market not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "updateAllocation",
            id,
            newAllocation
        ));

        uint256 totalAllocation = newAllocation;
        for (uint256 i = 0; i < marketAllocations.length; i++) {
            if (marketAllocations[i].id != id) {
                totalAllocation += marketAllocations[i].allocation;
            }
        }
        require(totalAllocation <= BASIS_POINTS, "Bank: Total allocation exceeds 100%");

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

        require(isMarketEnabled[id], "Bank: Market not enabled");
        uint256 totalAllocation = newAllocation;
        for (uint256 i = 0; i < marketAllocations.length; i++) {
            if (marketAllocations[i].id != id) {
                totalAllocation += marketAllocations[i].allocation;
            }
        }
        require(totalAllocation <= BASIS_POINTS, "Bank: Total allocation exceeds 100%");

        for (uint256 i = 0; i < marketAllocations.length; i++) {
            if (marketAllocations[i].id == id) {
                marketAllocations[i].allocation = newAllocation;
                break;
            }
        }

        emit AllocationUpdated(id, newAllocation);
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
