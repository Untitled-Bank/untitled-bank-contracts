// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./CoreVaultStorage.sol";
import "../libraries/math/WadMath.sol";
import "../libraries/math/SharesMath.sol";

abstract contract CoreVaultInternal is ERC4626, CoreVaultStorage {
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
        for (uint256 i = 0; i < vaultAllocations.length && remaining > 0; i++) {
            ICoreVault.VaultAllocation memory allocation = vaultAllocations[i];
            uint256 toDeposit = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            toDeposit = Math.min(toDeposit, remaining);

            if (toDeposit > 0) {
                IERC20(asset()).approve(address(allocation.vault), toDeposit);
                allocation.vault.deposit(toDeposit, address(this));
                remaining -= toDeposit;
            }
        }

        require(remaining == 0, "Not all assets deposited");
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        uint256 remaining = assets;
        for (uint256 i = 0; i < vaultAllocations.length && remaining > 0; i++) {
            ICoreVault.VaultAllocation memory allocation = vaultAllocations[i];
            uint256 vaultShares = allocation.vault.balanceOf(address(this));
            uint256 vaultAssets = allocation.vault.convertToAssets(vaultShares);
            uint256 toWithdraw = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            toWithdraw = Math.min(toWithdraw, vaultAssets);
            toWithdraw = Math.min(toWithdraw, remaining);

            if (toWithdraw > 0) {
                allocation.vault.withdraw(
                    toWithdraw,
                    address(this),
                    address(this)
                );
                remaining -= toWithdraw;
            }
        }

        require(remaining == 0, "Not enough liquidity");

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function totalAssets() public view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < vaultAllocations.length; i++) {
            IERC4626 vault = vaultAllocations[i].vault;
            uint256 vaultShares = vault.balanceOf(address(this));
            total += vault.convertToAssets(vaultShares);
        }
        return total;
    }
}
