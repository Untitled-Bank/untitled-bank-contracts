// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

/// @title Price Provider Interface
/// @notice This interface defines the structure for a price oracle contract
/// @dev Implement this interface for contracts that provide price information for collateral tokens
interface IPriceProvider {
    /// @notice Checks if the contract is a valid price provider
    /// @dev This function should return true for all valid price provider implementations
    /// @return bool Returns true if the contract is a price provider, false otherwise
    function isPriceProvider() external view returns (bool);

    /// @notice Gets the current price of the collateral token
    /// @dev The price should be denominated in the loan token
    /// @return price The current price of the collateral token
    function getCollateralTokenPrice() external view returns (uint256 price);
}
