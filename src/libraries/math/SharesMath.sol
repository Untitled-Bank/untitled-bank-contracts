// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {WadMath} from "./WadMath.sol";

/**
 * @title SharesMath Library
 * @dev A library for converting between assets and shares in a vault-like system.
 * It uses virtual shares and assets to prevent division by zero and inflation attacks.
 */
library SharesMath {
    using WadMath for uint256;

    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;

    /**
     * @dev Converts assets to shares, rounding down.
     * @param assets The amount of assets to convert.
     * @param totalAssets The total amount of assets in the system.
     * @param totalShares The total amount of shares in the system.
     * @return The calculated amount of shares, rounded down.
     */
    function toSharesDown(
        uint256 assets,
        uint256 totalAssets,
        uint256 totalShares
    ) internal pure returns (uint256) {
        return
            assets.mulDivDown(
                totalShares + VIRTUAL_SHARES,
                totalAssets + VIRTUAL_ASSETS
            );
    }

    /**
     * @dev Converts shares to assets, rounding down.
     * @param shares The amount of shares to convert.
     * @param totalAssets The total amount of assets in the system.
     * @param totalShares The total amount of shares in the system.
     * @return The calculated amount of assets, rounded down.
     */
    function toAssetsDown(
        uint256 shares,
        uint256 totalAssets,
        uint256 totalShares
    ) internal pure returns (uint256) {
        return
            shares.mulDivDown(
                totalAssets + VIRTUAL_ASSETS,
                totalShares + VIRTUAL_SHARES
            );
    }

    /**
     * @dev Converts assets to shares, rounding up.
     * @param assets The amount of assets to convert.
     * @param totalAssets The total amount of assets in the system.
     * @param totalShares The total amount of shares in the system.
     * @return The calculated amount of shares, rounded up.
     */
    function toSharesUp(
        uint256 assets,
        uint256 totalAssets,
        uint256 totalShares
    ) internal pure returns (uint256) {
        return
            assets.mulDivUp(
                totalShares + VIRTUAL_SHARES,
                totalAssets + VIRTUAL_ASSETS
            );
    }

    /**
     * @dev Converts shares to assets, rounding up.
     * @param shares The amount of shares to convert.
     * @param totalAssets The total amount of assets in the system.
     * @param totalShares The total amount of shares in the system.
     * @return The calculated amount of assets, rounded up.
     */
    function toAssetsUp(
        uint256 shares,
        uint256 totalAssets,
        uint256 totalShares
    ) internal pure returns (uint256) {
        return
            shares.mulDivUp(
                totalAssets + VIRTUAL_ASSETS,
                totalShares + VIRTUAL_SHARES
            );
    }
}
