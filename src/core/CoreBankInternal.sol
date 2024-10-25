// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./CoreBankStorage.sol";
import "../libraries/math/WadMath.sol";
import "../libraries/math/SharesMath.sol";

abstract contract CoreBankInternal is ERC4626, CoreBankStorage {
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
        for (uint256 i = 0; i < bankAllocations.length && remaining > 0; i++) {
            ICoreBank.BankAllocation memory allocation = bankAllocations[i];
            uint256 toDeposit = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            toDeposit = Math.min(toDeposit, remaining);

            if (toDeposit > 0) {
                IERC20(asset()).approve(address(allocation.bank), toDeposit);
                allocation.bank.deposit(toDeposit, address(this));
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
        for (uint256 i = 0; i < bankAllocations.length && remaining > 0; i++) {
            ICoreBank.BankAllocation memory allocation = bankAllocations[i];
            uint256 bankShares = allocation.bank.balanceOf(address(this));
            uint256 bankAssets = allocation.bank.convertToAssets(bankShares);
            uint256 toWithdraw = assets.mulWadDown(allocation.allocation * 1e18).divWadDown(BASIS_POINTS_WAD);
            toWithdraw = Math.min(toWithdraw, bankAssets);
            toWithdraw = Math.min(toWithdraw, remaining);

            if (toWithdraw > 0) {
                allocation.bank.withdraw(
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
        for (uint256 i = 0; i < bankAllocations.length; i++) {
            IERC4626 bank = bankAllocations[i].bank;
            uint256 bankShares = bank.balanceOf(address(this));
            total += bank.convertToAssets(bankShares);
        }
        return total;
    }
}
