// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./BankStorage.sol";
import "../libraries/math/WadMath.sol";
import "../libraries/math/SharesMath.sol";
import "../interfaces/IBank.sol";

abstract contract BankInternal is ERC4626Upgradeable, BankStorage {
    using Math for uint256;
    using WadMath for uint256;
    using SharesMath for uint256;

    uint256 public lastTotalAssets;
    event FeeAccrued(uint256 feeAmount, uint256 feeShares);
    error WithdrawFailed();

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (bankType == IBank.BankType.Private) {
            if (!whitelist[caller]) revert IBank.NotWhitelisted();
        }
        _accrueFee();
        super._deposit(caller, receiver, assets, shares);

        uint256 remaining = assets;
        // Handle all markets except the last one
        for (uint256 i = 0; i < marketAllocations.length - 1 && remaining > 0; i++) {
            IBank.MarketAllocation memory allocation = marketAllocations[i];
            if (!isMarketEnabled[allocation.id] || allocation.allocation == 0) {
                continue;
            }
            uint256 toDeposit = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
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
            if (isMarketEnabled[lastAllocation.id] && lastAllocation.allocation > 0) {
                IERC20(asset()).approve(address(untitledHub), remaining);
                untitledHub.supply(lastAllocation.id, remaining, "");
                remaining = 0;
            }
        }

        if (remaining != 0) revert IBank.AssetsNotFullyDeposited();
        lastTotalAssets = totalAssets();
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (bankType == IBank.BankType.Private) {
            if (!whitelist[owner]) revert IBank.NotWhitelisted();
        }
        _accrueFee();

        if (!_executeWithdraw(assets)) {
            revert WithdrawFailed();
        }
        
        // Execute transfer to receiver
        super._withdraw(caller, receiver, owner, assets, shares);
        lastTotalAssets = totalAssets();
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < marketAllocations.length; i++) {
            IBank.MarketAllocation memory allocation = marketAllocations[i];
            (uint256 supplyShares, , ) = untitledHub.position(allocation.id, address(this));
            (uint128 totalSupplyAssets, uint128 totalSupplyShares, , , , ) = untitledHub.market(allocation.id);
            total += supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
        }
        return total;
    }

    function _accrueFee() internal {
        uint256 currentTotalAssets = totalAssets();
        uint256 totalInterest = currentTotalAssets > lastTotalAssets ? currentTotalAssets - lastTotalAssets : 0;
        
        if (totalInterest > 0 && fee > 0 && feeRecipient != address(0)) {
            uint256 feeAmount = totalInterest.mulWadDown(fee * 1e18).divWadDown(BASIS_POINTS_WAD);
            uint256 feeShares = convertToShares(feeAmount);
            
            if (feeShares > 0) {
                _mint(feeRecipient, feeShares);
                emit FeeAccrued(feeAmount, feeShares);
            }
        }
        
        lastTotalAssets = currentTotalAssets;
    }

    function _marketLiquidityAfterAccruedInterest(uint256 marketId) internal returns (uint256) {
        untitledHub.accrueInterest(marketId);

        (uint128 totalSupplyAssets, , uint128 totalBorrowAssets, , , ) = untitledHub.market(marketId);
        return totalSupplyAssets - totalBorrowAssets;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function _executeWithdraw(uint256 assets) private returns (bool) {
        uint256[] memory marketWithdrawals = new uint256[](marketAllocations.length);
        uint256[] memory marketLiquidities = new uint256[](marketAllocations.length);
        uint256 remaining = assets;
        
        // First pass: withdraw by allocation except last market
        remaining = _withdrawByAllocationExceptLast(remaining, marketWithdrawals, marketLiquidities);
        
        // Second pass: try last market
        if (remaining > 0) {
            remaining = _withdrawFromLastMarket(remaining, marketWithdrawals, marketLiquidities);
        }
        
        // Final pass: try remaining liquidity from all markets
        if (remaining > 0) {
            remaining = _withdrawFromRemainingLiquidity(remaining, marketWithdrawals, marketLiquidities);
        }
        
        return remaining == 0;
    }

    function _withdrawByAllocationExceptLast(
        uint256 remaining,
        uint256[] memory marketWithdrawals,
        uint256[] memory marketLiquidities
    ) private returns (uint256) {
        for (uint256 i = 0; i < marketAllocations.length - 1 && remaining > 0; i++) {
            IBank.MarketAllocation memory allocation = marketAllocations[i];
            if (!_isValidMarket(allocation)) continue;

            uint256 targetWithdraw = remaining.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            marketLiquidities[i] = _marketLiquidityAfterAccruedInterest(allocation.id);
            
            uint256 availableAssets = _calculateAvailableAssets(allocation.id, marketLiquidities[i]);
            uint256 withdrawAmount = Math.min(targetWithdraw, availableAssets);
            
            if (withdrawAmount > 0) {
                uint256 withdrawn = _tryWithdraw(allocation.id, withdrawAmount);
                if (withdrawn > 0) {
                    marketWithdrawals[i] = withdrawn;
                    remaining -= withdrawn;
                }
            }
        }
        return remaining;
    }

    function _withdrawFromLastMarket(
        uint256 remaining,
        uint256[] memory marketWithdrawals,
        uint256[] memory marketLiquidities
    ) private returns (uint256) {
        if (marketAllocations.length == 0) return remaining;

        uint256 lastIndex = marketAllocations.length - 1;
        IBank.MarketAllocation memory lastAllocation = marketAllocations[lastIndex];
        if (!_isValidMarket(lastAllocation)) return remaining;

        marketLiquidities[lastIndex] = _marketLiquidityAfterAccruedInterest(lastAllocation.id);
        uint256 availableAssets = _calculateAvailableAssets(lastAllocation.id, marketLiquidities[lastIndex]);
        
        if (availableAssets > 0) {
            uint256 finalWithdraw = Math.min(remaining, availableAssets);
            uint256 withdrawn = _tryWithdraw(lastAllocation.id, finalWithdraw);
            if (withdrawn > 0) {
                marketWithdrawals[lastIndex] = withdrawn;
                remaining -= withdrawn;
            }
        }
        
        return remaining;
    }

    function _withdrawFromRemainingLiquidity(
        uint256 remaining,
        uint256[] memory marketWithdrawals,
        uint256[] memory marketLiquidities
    ) private returns (uint256) {
        for (uint256 i = 0; i < marketAllocations.length && remaining > 0; i++) {
            IBank.MarketAllocation memory allocation = marketAllocations[i];
            if (!_isValidMarket(allocation)) continue;
            
            uint256 availableAssets = _calculateAvailableAssets(allocation.id, marketLiquidities[i]);
            availableAssets = availableAssets > marketWithdrawals[i] ? 
                availableAssets - marketWithdrawals[i] : 0;
            
            if (availableAssets > 0) {
                uint256 withdrawAmount = Math.min(remaining, availableAssets);
                uint256 withdrawn = _tryWithdraw(allocation.id, withdrawAmount);
                if (withdrawn > 0) {
                    remaining -= withdrawn;
                }
            }
        }
        return remaining;
    }

    function _isValidMarket(IBank.MarketAllocation memory allocation) private view returns (bool) {
        return isMarketEnabled[allocation.id] && allocation.allocation > 0;
    }

    function _calculateAvailableAssets(
        uint256 marketId,
        uint256 availableLiquidity
    ) private view returns (uint256) {
        (uint256 supplyShares, , ) = untitledHub.position(marketId, address(this));
        (uint128 totalSupplyAssets, uint128 totalSupplyShares, , , , ) = untitledHub.market(marketId);
        
        return Math.min(
            availableLiquidity,
            supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares)
        );
    }

    function _tryWithdraw(
        uint256 marketId,
        uint256 amount
    ) private returns (uint256) {
        try untitledHub.withdraw(marketId, amount, address(this)) {
            return amount;
        } catch {
            return 0;
        }
    }
}