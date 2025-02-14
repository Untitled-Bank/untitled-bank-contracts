// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {MarketConfigs, Market} from "./IUntitledHub.sol";

/// @title IInterestRateModel - Interest Rate Model Interface
/// @notice This interface defines the structure for interest rate calculation in DeFi lending protocols
/// @dev Implement this interface to create custom interest rate models
interface IInterestRateModel {
    /// @notice Checks if the IRM is valid
    /// @dev This function does not modify contract state
    /// @return True if the IRM is valid, false otherwise
    function isIrm() external view returns (bool);

    /// @notice Calculates the current borrow rate
    /// @dev This function may modify contract state
    /// @param marketConfigs Parameters defining the market configuration
    /// @param market Current state of the market
    /// @return The calculated borrow rate as a uint256
    function borrowRate(
        MarketConfigs memory marketConfigs,
        Market memory market
    ) external returns (uint256);

    /// @notice Views the current borrow rate without modifying state
    /// @dev This function does not modify contract state
    /// @param marketConfigs Parameters defining the market configuration
    /// @param market Current state of the market
    /// @return The calculated borrow rate as a uint256
    function borrowRateView(
        MarketConfigs memory marketConfigs,
        Market memory market
    ) external view returns (uint256);
}
