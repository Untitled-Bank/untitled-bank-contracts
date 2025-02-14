// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @dev Oracle price scale.
uint256 constant ORACLE_PRICE_SCALE = 1e36;

/// @dev Liquidation incentive slope. 'm' from y = b - mx
uint256 constant LIQUIDATION_SLOPE = 0.4e18;

/// @dev Liquidation incentive intercept. 'b' from y = b - mx
uint256 constant LIQUIDATION_INTERCEPT = 1.4e18;

/// @dev Max liquidation incentive factor.
uint256 constant MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18;

/// @dev Max number of markets.
uint256 constant MAX_MARKETS = 10;

/// @dev Basis points.
uint256 constant BASIS_POINTS = 10000;

/// @dev Basis points in WAD.
uint256 constant BASIS_POINTS_WAD = BASIS_POINTS * 1e18;
