// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./CoreBankStorage.sol";
import "../libraries/math/WadMath.sol";
import "../libraries/math/SharesMath.sol";
import "../interfaces/IUntitledHub.sol";

abstract contract CoreBankInternal is ERC4626Upgradeable, CoreBankStorage {
    using Math for uint256;
    using WadMath for uint256;
    using SharesMath for uint256;

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        super._deposit(caller, receiver, assets, shares);

        uint256 remaining = assets;
        // Handle all banks except the last one
        for (uint256 i = 0; i < bankAllocations.length - 1 && remaining > 0; i++) {
            ICoreBank.BankAllocation memory allocation = bankAllocations[i];
            if (!isBankEnabled[address(allocation.bank)] || allocation.allocation == 0) {
                continue;
            }
            uint256 toDeposit = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            toDeposit = Math.min(toDeposit, remaining);

            if (toDeposit > 0) {
                IERC20(asset()).approve(address(allocation.bank), toDeposit);
                allocation.bank.deposit(toDeposit, address(this));
                remaining -= toDeposit;
            }
        }

        // Handle the last bank - deposit all remaining assets
        if (remaining > 0 && bankAllocations.length > 0) {
            ICoreBank.BankAllocation memory lastAllocation = bankAllocations[bankAllocations.length - 1];
            if (isBankEnabled[address(lastAllocation.bank)] && lastAllocation.allocation > 0) {
                IERC20(asset()).approve(address(lastAllocation.bank), remaining);
                lastAllocation.bank.deposit(remaining, address(this));
                remaining = 0;
            }
        }

        require(remaining == 0, "CoreBank: Not all assets deposited");
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        uint256 remaining = assets;
        uint256[] memory bankWithdrawals = new uint256[](bankAllocations.length);
        uint256[] memory bankLiquidities = new uint256[](bankAllocations.length);
        
        // First pass: Try to withdraw according to allocations for all except last bank
        for (uint256 i = 0; i < bankAllocations.length - 1 && remaining > 0; i++) {
            ICoreBank.BankAllocation memory allocation = bankAllocations[i];
            if (!isBankEnabled[address(allocation.bank)] || allocation.allocation == 0) {
                continue;
            }
            uint256 targetWithdraw = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            uint256 bankAvailableLiquidity = _getBankWithdrawableLiquidity(address(allocation.bank));            
            bankLiquidities[i] = bankAvailableLiquidity;

            uint256 bankShares = allocation.bank.balanceOf(address(this));
            uint256 availableAssets = Math.min(bankAvailableLiquidity, allocation.bank.convertToAssets(bankShares));
            
            uint256 actualWithdraw = Math.min(targetWithdraw, availableAssets);
            if (actualWithdraw > 0) {
                try allocation.bank.withdraw(
                    actualWithdraw,
                    address(this),
                    address(this)
                ) {
                    bankWithdrawals[i] = actualWithdraw;
                    remaining -= actualWithdraw;
                } catch {
                    // If the withdraw fails, we skip this bank
                }               
            }
        }

        // Handle the last bank - try to withdraw all remaining assets if needed
        if (remaining > 0 && bankAllocations.length > 0) {
            uint256 lastIndex = bankAllocations.length - 1;
            ICoreBank.BankAllocation memory lastAllocation = bankAllocations[lastIndex];
            if (isBankEnabled[address(lastAllocation.bank)] && lastAllocation.allocation > 0) {
                uint256 bankAvailableLiquidity = _getBankWithdrawableLiquidity(address(lastAllocation.bank));
                uint256 bankShares = lastAllocation.bank.balanceOf(address(this));
                uint256 availableAssets = Math.min(bankAvailableLiquidity, lastAllocation.bank.convertToAssets(bankShares));

                if (availableAssets > 0) {
                    uint256 finalWithdraw = Math.min(remaining, availableAssets);
                    try lastAllocation.bank.withdraw(
                        finalWithdraw,
                        address(this),
                        address(this)
                    ) {
                        bankWithdrawals[lastIndex] = finalWithdraw;
                        remaining -= finalWithdraw;
                    } catch {
                        // If the withdraw fails, continue to second pass
                    }
                }
            }
        }
        
        // Second pass: Try to withdraw remaining assets from any bank with available liquidity
        if (remaining > 0) {
            for (uint256 i = 0; i < bankAllocations.length && remaining > 0; i++) {
                ICoreBank.BankAllocation memory allocation = bankAllocations[i];
                if (!isBankEnabled[address(allocation.bank)] || allocation.allocation == 0) {
                    continue;
                }
                
                uint256 bankShares = allocation.bank.balanceOf(address(this));
                uint256 availableAssets = Math.min(bankLiquidities[i], allocation.bank.convertToAssets(bankShares));
                
                // Subtract what we've already withdrawn
                availableAssets = availableAssets > bankWithdrawals[i] ? availableAssets - bankWithdrawals[i] : 0;
                
                if (availableAssets > 0) {
                    uint256 additionalWithdraw = Math.min(remaining, availableAssets);
                    try allocation.bank.withdraw(
                        additionalWithdraw,
                        address(this),
                        address(this)
                    ) {
                        bankWithdrawals[i] += additionalWithdraw;
                        remaining -= additionalWithdraw;
                    } catch {
                        // If the withdraw fails, we skip this bank
                    }
                }
            }
        }

        require(remaining == 0, "Insufficient liquidity across all banks");
        
        super._withdraw(caller, receiver, owner, assets, shares);
    }
    
    function totalAssets() public view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < bankAllocations.length; i++) {
            IERC4626 bank = bankAllocations[i].bank;
            uint256 bankShares = bank.balanceOf(address(this));
            total += bank.convertToAssets(bankShares);
        }
        return total;
    }

    function _getBankWithdrawableLiquidity(address bank) internal returns (uint256) {
        // Harvest fees first to get accurate total assets
        IBank(bank).harvest();
        
        // Get total assets in the bank after fee accrual
        uint256 bankTotalAssets = IBank(bank).totalAssets();
        if (bankTotalAssets == 0) return 0;

        // Get all market allocations from the bank
        IBank.MarketAllocation[] memory marketAllocations = IBank(bank).getMarketAllocations();
        
        uint256 totalWithdrawable = 0;
        
        // Check each market's available liquidity
        for (uint256 i = 0; i < marketAllocations.length; i++) {
            IBank.MarketAllocation memory allocation = marketAllocations[i];
            if (!IBank(bank).getIsMarketEnabled(allocation.id)) continue;

            // Accrue interest for this market first
            IUntitledHub(IBank(bank).getUntitledHub()).accrueInterest(allocation.id);

            // Get market position
            (uint256 supplyShares, , ) = IUntitledHub(IBank(bank).getUntitledHub()).position(allocation.id, bank);
            if (supplyShares == 0) continue;

            // Get market state after interest accrual
            (uint128 totalSupplyAssets, uint128 totalSupplyShares, uint128 totalBorrowAssets, , , ) = IUntitledHub(IBank(bank).getUntitledHub()).market(allocation.id);
            
            // Calculate available liquidity in this market
            uint256 marketLiquidity = totalSupplyAssets - totalBorrowAssets;
            
            // Calculate bank's withdrawable amount from this market
            uint256 bankAssetsInMarket = supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
            uint256 marketWithdrawable = Math.min(marketLiquidity, bankAssetsInMarket);
            
            totalWithdrawable += marketWithdrawable;
        }

        return totalWithdrawable;
    }
}
