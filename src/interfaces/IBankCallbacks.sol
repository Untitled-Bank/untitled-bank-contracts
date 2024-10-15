// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Bank Liquidate Callback Interface
/// @notice Interface for callback function to handle bank liquidation
interface IBankLiquidateCallback {
    /// @notice Called when a liquidation occurs in the bank
    /// @param repaidAssets The amount of assets repaid during liquidation
    /// @param data Additional data passed to the callback
    function onBankLiquidate(
        uint256 repaidAssets,
        bytes calldata data
    ) external;
}

/// @title Bank Repay Callback Interface
/// @notice Interface for callback function to handle bank repayments
interface IBankRepayCallback {
    /// @notice Called when a repayment is made to the bank
    /// @param assets The amount of assets repaid
    /// @param data Additional data passed to the callback
    function onBankRepay(uint256 assets, bytes calldata data) external;
}

/// @title Bank Supply Callback Interface
/// @notice Interface for callback function to handle asset supply to the bank
interface IBankSupplyCallback {
    /// @notice Called when assets are supplied to the bank
    /// @param assets The amount of assets supplied
    /// @param data Additional data passed to the callback
    function onBankSupply(uint256 assets, bytes calldata data) external;
}

/// @title Bank Supply Collateral Callback Interface
/// @notice Interface for callback function to handle collateral supply to the bank
interface IBankSupplyCollateralCallback {
    /// @notice Called when collateral is supplied to the bank
    /// @param assets The amount of collateral assets supplied
    /// @param data Additional data passed to the callback
    function onBankSupplyCollateral(
        uint256 assets,
        bytes calldata data
    ) external;
}

/// @title Bank Flash Loan Callback Interface
/// @notice Interface for callback function to handle flash loans from the bank
interface IBankFlashLoanCallback {
    /// @notice Called when a flash loan is taken from the bank
    /// @param assets The amount of assets borrowed in the flash loan
    /// @param data Additional data passed to the callback
    function onBankFlashLoan(uint256 assets, bytes calldata data) external;
}
