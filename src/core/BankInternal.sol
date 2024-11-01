// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./BankStorage.sol";
import "../libraries/math/WadMath.sol";
import "../libraries/math/SharesMath.sol";

abstract contract BankInternal is ERC4626, BankStorage {
    using Math for uint256;
    using WadMath for uint256;
    using SharesMath for uint256;

    uint256 public lastTotalAssets;
    event FeeAccrued(uint256 feeAmount, uint256 feeShares);

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (bankType == IBank.BankType.Private) {
            require(whitelist[caller], "Not whitelisted");
        }
        _accrueFee();
        super._deposit(caller, receiver, assets, shares);

        uint256 remaining = assets;
        for (uint256 i = 0; i < marketAllocations.length && remaining > 0; i++) {
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

        require(remaining == 0, "Not all assets deposited");
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
            require(whitelist[owner], "Not whitelisted");
        }
        _accrueFee();

        uint256 remaining = assets;
        uint256[] memory marketWithdrawals = new uint256[](marketAllocations.length);
        
        // First pass: Try to withdraw according to allocations
        for (uint256 i = 0; i < marketAllocations.length && remaining > 0; i++) {
            IBank.MarketAllocation memory allocation = marketAllocations[i];
            if (!isMarketEnabled[allocation.id] || allocation.allocation == 0) {
                continue;
            }
            uint256 targetWithdraw = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);            
            uint256 availableLiquidity = _marketLiquidityAfterAccruedInterest(allocation.id);

            // Check how much we can actually withdraw from this market
            (uint256 supplyShares, , ) = untitledHub.position(allocation.id, address(this));
            (uint128 totalSupplyAssets, uint128 totalSupplyShares, , , , ) = untitledHub.market(allocation.id);
            uint256 availableAssets = Math.min(availableLiquidity, supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares));
            
            uint256 actualWithdraw = Math.min(targetWithdraw, availableAssets);
            if (actualWithdraw > 0) {
                try untitledHub.withdraw(allocation.id, actualWithdraw, address(this)) {
                    marketWithdrawals[i] = actualWithdraw;
                    remaining -= actualWithdraw;
                } catch {
                    // If the withdraw fails, we skip this market
                }
            }
        }
        
        // Second pass: Try to withdraw remaining assets from markets with available liquidity
        if (remaining > 0) {
            for (uint256 i = 0; i < marketAllocations.length && remaining > 0; i++) {
                IBank.MarketAllocation memory allocation = marketAllocations[i];
                if (!isMarketEnabled[allocation.id] || allocation.allocation == 0) {
                    continue;
                }
                
                // Check remaining available assets in this market
                (uint256 supplyShares, , ) = untitledHub.position(allocation.id, address(this));
                (uint128 totalSupplyAssets, uint128 totalSupplyShares, , , , ) = untitledHub.market(allocation.id);
                uint256 availableAssets = supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
                
                // Subtract what we've already withdrawn
                availableAssets = availableAssets > marketWithdrawals[i] ? availableAssets - marketWithdrawals[i] : 0;
                
                if (availableAssets > 0) {
                    try untitledHub.withdraw(allocation.id, Math.min(remaining, availableAssets), address(this)) {
                        marketWithdrawals[i] += Math.min(remaining, availableAssets);
                        remaining -= Math.min(remaining, availableAssets);
                    } catch {
                        // If the withdraw fails, we skip this market
                    }
                }
            }
        }

        require(remaining == 0, "Insufficient liquidity across all markets");
        
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

    // Override these functions to account for fee accrual
    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }
}