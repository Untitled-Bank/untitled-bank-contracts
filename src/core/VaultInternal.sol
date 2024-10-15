// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./VaultStorage.sol";
import "../libraries/math/WadMath.sol";
import "../libraries/math/SharesMath.sol";

abstract contract VaultInternal is ERC4626, VaultStorage {
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
        if (vaultType == IVault.VaultType.Private) {
            require(whitelist[caller], "Not whitelisted");
        }
        _accrueFee();
        super._deposit(caller, receiver, assets, shares);

        uint256 remaining = assets;
        for (uint256 i = 0; i < bankAllocations.length && remaining > 0; i++) {
            IVault.BankAllocation memory allocation = bankAllocations[i];
            uint256 toDeposit = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            toDeposit = Math.min(toDeposit, remaining);

            if (toDeposit > 0) {
                IERC20(asset()).approve(address(bank), toDeposit);
                bank.supply(allocation.id, toDeposit, "");
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
        if (vaultType == IVault.VaultType.Private) {
            require(whitelist[owner], "Not whitelisted");
        }
         _accrueFee();

        uint256 remaining = assets;
        for (uint256 i = 0; i < bankAllocations.length && remaining > 0; i++) {
            IVault.BankAllocation memory allocation = bankAllocations[i];

            (
                uint128 totalSupplyAssets,
                uint128 totalSupplyShares,
                ,
                ,
                ,

            ) = bank.market(allocation.id);

            (uint256 supplyShares, , ) = bank.position(
                allocation.id,
                address(this)
            );
            uint256 currentAssets = supplyShares.toAssetsDown(
                totalSupplyAssets,
                totalSupplyShares
            );

            uint256 toWithdraw = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            toWithdraw = Math.min(toWithdraw, currentAssets);
            toWithdraw = Math.min(toWithdraw, remaining);

            if (toWithdraw > 0) {
                bank.withdraw(allocation.id, toWithdraw, address(this));
                remaining -= toWithdraw;
            }
        }

        require(remaining == 0, "Not enough liquidity");

        super._withdraw(caller, receiver, owner, assets, shares);
        lastTotalAssets = totalAssets();
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < bankAllocations.length; i++) {
            IVault.BankAllocation memory allocation = bankAllocations[i];
            (uint256 supplyShares, , ) = bank.position(allocation.id, address(this));
            (uint128 totalSupplyAssets, uint128 totalSupplyShares, , , , ) = bank.market(allocation.id);
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