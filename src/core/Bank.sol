// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IBank.sol";
import "./BankInternal.sol";
import "../libraries/Timelock.sol";
import "../libraries/math/WadMath.sol";

contract Bank is 
    Initializable, 
    UUPSUpgradeable,     
    IBank, 
    BankInternal, 
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
        
        require(_fee <= 1000, "Fee too high"); // Max 10%
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

        require(marketAllocations.length < MAX_MARKETS, "Bank: Max markets reached");
        require(!isMarketEnabled[id], "Bank: Market already added");

        (address loanToken, , , , ) = untitledHub.idToMarketConfigs(id);
        require(loanToken == asset(), "Bank: Asset mismatch");

        if (marketAllocations.length == 0) {
            marketAllocations.push(MarketAllocation(id, BASIS_POINTS));
            marketIdToIndex[id] = 0;
        } else {
            marketIdToIndex[id] = marketAllocations.length;
            marketAllocations.push(MarketAllocation(id, 0));
        }
        isMarketEnabled[id] = true;

        emit MarketAdded(id);
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
        require(isMarketEnabled[id], "Bank: Market not enabled");

        bytes32 operationId = keccak256(abi.encode(
            "removeMarket",
            id
        ));

        executeOperation(operationId);
        
        uint256 index = marketIdToIndex[id];
        require(index < marketAllocations.length && marketAllocations[index].id == id, "Bank: Market index mismatch");
        
        uint256 removedAllocation = marketAllocations[index].allocation;
        (uint256 supplyShares, , ) = untitledHub.position(id, address(this));                
        uint256 withdrawnAssets = 0;
        if (supplyShares > 0) {
            (uint256 assets, ) = untitledHub.withdraw(id, type(uint256).max, address(this));
            withdrawnAssets = assets;
        }
        
        // Remove market and update indices
        uint256 lastIndex = marketAllocations.length - 1;
        if (index != lastIndex) {
            marketAllocations[index] = marketAllocations[lastIndex];
            marketIdToIndex[marketAllocations[lastIndex].id] = index;
        }
        marketAllocations.pop();
        delete marketIdToIndex[id];
        isMarketEnabled[id] = false;

        if (withdrawnAssets > 0) {            
            uint256 totalRemainingAllocation = BASIS_POINTS - removedAllocation;
            require(marketAllocations.length > 0, "Bank: Cannot remove last market if there are still assets in the bank");
            require(totalRemainingAllocation > 0, "Bank: Total remaining allocation is 0");

            if (totalRemainingAllocation < BASIS_POINTS) {
                for (uint256 i = 0; i < marketAllocations.length; i++) {
                    marketAllocations[i].allocation = marketAllocations[i].allocation * BASIS_POINTS / totalRemainingAllocation;
                }   
            }
            uint256 remaining = withdrawnAssets;
            // Handle all markets except the last one
            for (uint256 i = 0; i < marketAllocations.length - 1 && remaining > 0; i++) {
                IBank.MarketAllocation memory allocation = marketAllocations[i];
                uint256 toDeposit = withdrawnAssets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
                toDeposit = Math.min(toDeposit, remaining);

                if (toDeposit > 0) {
                    IERC20(asset()).approve(address(untitledHub), toDeposit);
                    untitledHub.supply(allocation.id, toDeposit, "");
                    remaining -= toDeposit;
                }
            }
            // Handle the last market - deposit all remaining assets
            if (remaining > 0 && marketAllocations.length > 0) {
                IBank.MarketAllocation memory lastAllocation = marketAllocations[marketAllocations.length - 1];
                IERC20(asset()).approve(address(untitledHub), remaining);
                untitledHub.supply(lastAllocation.id, remaining, "");
            }
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

        require(withdrawIds.length == withdrawAmounts.length, "Bank: Mismatched withdraw arrays");
        require(depositIds.length == depositAmounts.length, "Bank: Mismatched deposit arrays");

        // Check and track total amounts
        uint256 totalWithdraw = 0;
        uint256 totalDeposit = 0;
        uint256 len = withdrawIds.length;

        // Perform withdrawals
        for (uint256 i = 0; i < len; i++) {
            require(isMarketEnabled[withdrawIds[i]], "Bank: Withdraw market not enabled");

            if (withdrawAmounts[i] > 0) {
                untitledHub.withdraw(withdrawIds[i], withdrawAmounts[i], address(this));
                totalWithdraw += withdrawAmounts[i];
            }
        }

        // Perform deposits
        for (uint256 i = 0; i < len; i++) {
            require(isMarketEnabled[depositIds[i]], "Bank: Deposit market not enabled");

            if (depositAmounts[i] > 0) {
                IERC20(asset()).approve(address(untitledHub), depositAmounts[i]);
                untitledHub.supply(depositIds[i], depositAmounts[i], "");
                totalDeposit += depositAmounts[i];
            }
        }

        require(totalWithdraw == totalDeposit, "Bank: Mismatched total amounts");

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