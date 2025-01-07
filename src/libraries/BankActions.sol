// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interfaces/IBank.sol";
import "../core/UntitledHub.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../libraries/math/WadMath.sol";

library BankActions {
    using WadMath for uint256;

    event MarketAdded(uint256 indexed id);
    event MarketRemoved(uint256 indexed id);
    event AllocationsUpdated(IBank.MarketAllocation[] newMarketAllocations);
    event Reallocated(uint256[] withdrawIds, uint256[] withdrawAmounts, uint256[] depositIds, uint256[] depositAmounts);

    function executeAddMarket(
        uint256 id,
        IBank.MarketAllocation[] storage marketAllocations,
        mapping(uint256 => uint256) storage marketIdToIndex,
        mapping(uint256 => bool) storage isMarketEnabled,
        UntitledHub untitledHub,
        address asset
    ) internal {
        require(marketAllocations.length < MAX_MARKETS, "Bank: Max markets reached");
        require(!isMarketEnabled[id], "Bank: Market already added");

        (address loanToken, , , , ) = untitledHub.idToMarketConfigs(id);
        require(loanToken == asset, "Bank: Asset mismatch");

        if (marketAllocations.length == 0) {
            marketAllocations.push(IBank.MarketAllocation(id, BASIS_POINTS));
            marketIdToIndex[id] = 0;
        } else {
            marketIdToIndex[id] = marketAllocations.length;
            marketAllocations.push(IBank.MarketAllocation(id, 0));
        }
        isMarketEnabled[id] = true;

        emit MarketAdded(id);
    }

    function executeRemoveMarket(
        uint256 id,
        IBank.MarketAllocation[] storage marketAllocations,
        mapping(uint256 => uint256) storage marketIdToIndex,
        mapping(uint256 => bool) storage isMarketEnabled,
        UntitledHub untitledHub,
        address asset
    ) internal {
        require(isMarketEnabled[id], "Bank: Market not enabled");
        
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
            require(marketAllocations.length > 0, "Bank: Cannot remove last market with assets");
            require(totalRemainingAllocation > 0, "Bank: Total remaining allocation is 0");

            if (totalRemainingAllocation < BASIS_POINTS) {
                for (uint256 i = 0; i < marketAllocations.length; i++) {
                    marketAllocations[i].allocation = marketAllocations[i].allocation * BASIS_POINTS / totalRemainingAllocation;
                }   
            }
            
            _redistributeAssets(
                withdrawnAssets,
                marketAllocations,
                untitledHub,
                asset
            );
        }

        emit MarketRemoved(id);
    }

    function executeUpdateAllocations(
        IBank.MarketAllocation[] calldata newMarketAllocations,
        IBank.MarketAllocation[] storage marketAllocations,
        mapping(uint256 => bool) storage isMarketEnabled
    ) internal {
        require(newMarketAllocations.length == marketAllocations.length, "Bank: Mismatched arrays");
        
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

        uint256 length = marketAllocations.length;
        for (uint256 i = 0; i < length; i++) {
            marketAllocations[i].id = newMarketAllocations[i].id;
            marketAllocations[i].allocation = newMarketAllocations[i].allocation;
        }

        emit AllocationsUpdated(newMarketAllocations);
    }

    function executeReallocate(
        uint256[] calldata withdrawIds,
        uint256[] calldata withdrawAmounts,
        uint256[] calldata depositIds,
        uint256[] calldata depositAmounts,
        mapping(uint256 => bool) storage isMarketEnabled,
        UntitledHub untitledHub,
        address asset
    ) internal {
        require(withdrawIds.length == withdrawAmounts.length, "Bank: Mismatched withdraw arrays");
        require(depositIds.length == depositAmounts.length, "Bank: Mismatched deposit arrays");

        uint256 totalWithdraw = 0;
        uint256 totalDeposit = 0;

        for (uint256 i = 0; i < withdrawIds.length; i++) {
            require(isMarketEnabled[withdrawIds[i]], "Bank: Withdraw market not enabled");

            if (withdrawAmounts[i] > 0) {
                untitledHub.withdraw(withdrawIds[i], withdrawAmounts[i], address(this));
                totalWithdraw += withdrawAmounts[i];
            }
        }

        for (uint256 i = 0; i < depositIds.length; i++) {
            require(isMarketEnabled[depositIds[i]], "Bank: Deposit market not enabled");

            if (depositAmounts[i] > 0) {
                IERC20(asset).approve(address(untitledHub), depositAmounts[i]);
                untitledHub.supply(depositIds[i], depositAmounts[i], "");
                totalDeposit += depositAmounts[i];
            }
        }

        require(totalWithdraw == totalDeposit, "Bank: Mismatched total amounts");

        emit Reallocated(withdrawIds, withdrawAmounts, depositIds, depositAmounts);
    }

    function _redistributeAssets(
        uint256 totalAssets,
        IBank.MarketAllocation[] storage marketAllocations,
        UntitledHub untitledHub,
        address asset
    ) private {
        uint256 remaining = totalAssets;
        // Handle all markets except the last one
        for (uint256 i = 0; i < marketAllocations.length - 1 && remaining > 0; i++) {
            IBank.MarketAllocation memory allocation = marketAllocations[i];
            uint256 toDeposit = totalAssets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            toDeposit = Math.min(toDeposit, remaining);

            if (toDeposit > 0) {
                IERC20(asset).approve(address(untitledHub), toDeposit);
                untitledHub.supply(allocation.id, toDeposit, "");
                remaining -= toDeposit;
            }
        }
        // Handle the last market - deposit all remaining assets
        if (remaining > 0 && marketAllocations.length > 0) {
            IBank.MarketAllocation memory lastAllocation = marketAllocations[marketAllocations.length - 1];
            IERC20(asset).approve(address(untitledHub), remaining);
            untitledHub.supply(lastAllocation.id, remaining, "");
        }
    }
}