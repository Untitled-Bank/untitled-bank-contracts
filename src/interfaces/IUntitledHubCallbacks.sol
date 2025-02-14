// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title UntitledHub Liquidate Callback Interface
/// @notice Interface for callback function to handle untitled hub liquidation
interface IUntitledHubLiquidateCallback {
    /// @notice Called when a liquidation occurs in the untitled hub
    /// @param repaidAssets The amount of assets repaid during liquidation
    /// @param data Additional data passed to the callback
    function onUntitledHubLiquidate(
        uint256 repaidAssets,
        bytes calldata data
    ) external;
}

/// @title UntitledHub Repay Callback Interface
/// @notice Interface for callback function to handle untitled hub repayments
interface IUntitledHubRepayCallback {
    /// @notice Called when a repayment is made to the untitled hub
    /// @param assets The amount of assets repaid
    /// @param data Additional data passed to the callback
    function onUntitledHubRepay(uint256 assets, bytes calldata data) external;
}

/// @title UntitledHub Supply Callback Interface
/// @notice Interface for callback function to handle asset supply to the untitled hub
interface IUntitledHubSupplyCallback {
    /// @notice Called when assets are supplied to the untitled hub
    /// @param assets The amount of assets supplied
    /// @param data Additional data passed to the callback
    function onUntitledHubSupply(uint256 assets, bytes calldata data) external;
}

/// @title UntitledHub Supply Collateral Callback Interface
/// @notice Interface for callback function to handle collateral supply to the untitled hub
interface IUntitledHubSupplyCollateralCallback {
    /// @notice Called when collateral is supplied to the untitled hub
    /// @param assets The amount of collateral assets supplied
    /// @param data Additional data passed to the callback
    function onUntitledHubSupplyCollateral(
        uint256 assets,
        bytes calldata data
    ) external;
}

/// @title UntitledHub Flash Loan Callback Interface
/// @notice Interface for callback function to handle flash loans from the untitled hub
interface IUntitledHubFlashLoanCallback {
    /// @notice Called when a flash loan is taken from the untitled hub
    /// @param assets The amount of assets borrowed in the flash loan
    /// @param data Additional data passed to the callback
    function onUntitledHubFlashLoan(uint256 assets, bytes calldata data) external;
}
