// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title IDappStakingManagerL2
 * @author neemo
 */
interface IDappStakingManagerL2 {
    /// @notice Returns the current LST exchange rate.
    /// @dev nsASTR -> ASTR
    function getRate() external view returns (uint256);

    /// @notice Returns the Astar to LST exchange rate.
    /// @dev ASTR -> nsASTR
    function underlyingToLstRate() external view returns (uint256);
}
