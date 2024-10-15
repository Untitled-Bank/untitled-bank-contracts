// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

uint256 constant WAD = 1e18;
uint256 constant HALF_WAD = 0.5e18;
uint256 constant MAX_UINT256 = 2 ** 256 - 1;

/// @title WadMath Library
/// @notice A library for fixed-point arithmetic operations using WAD precision
library WadMath {
    /// @notice Multiplies two WAD numbers and rounds down
    /// @param x The first WAD number
    /// @param y The second WAD number
    /// @return The product of x and y, rounded down
    function mulWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD); // Equivalent to (x * y) / WAD rounded down.
    }

    /// @notice Multiplies two WAD numbers and rounds up
    /// @param x The first WAD number
    /// @param y The second WAD number
    /// @return The product of x and y, rounded up
    function mulWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD); // Equivalent to (x * y) / WAD rounded up.
    }

    /// @notice Divides two WAD numbers and rounds down
    /// @param x The numerator WAD number
    /// @param y The denominator WAD number
    /// @return The quotient of x divided by y, rounded down
    function divWadDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y); // Equivalent to (x * WAD) / y rounded down.
    }

    /// @notice Divides two WAD numbers and rounds up
    /// @param x The numerator WAD number
    /// @param y The denominator WAD number
    /// @return The quotient of x divided by y, rounded up
    function divWadUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y); // Equivalent to (x * WAD) / y rounded up.
    }

    /*//////////////////////////////////////////////////////////////
                    LOW LEVEL FIXED POINT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Multiplies two numbers and divides the product by a third number, rounding down
    /// @param x The first factor
    /// @param y The second factor
    /// @param denominator The number to divide the product by
    /// @return z The result of (x * y) / denominator, rounded down
    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(
                mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))
            ) {
                revert(0, 0)
            }

            // Divide x * y by the denominator.
            z := div(mul(x, y), denominator)
        }
    }

    /// @notice Multiplies two numbers and divides the product by a third number, rounding up
    /// @param x The first factor
    /// @param y The second factor
    /// @param denominator The number to divide the product by
    /// @return z The result of (x * y) / denominator, rounded up
    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // Equivalent to require(denominator != 0 && (y == 0 || x <= type(uint256).max / y))
            if iszero(
                mul(denominator, iszero(mul(y, gt(x, div(MAX_UINT256, y)))))
            ) {
                revert(0, 0)
            }

            // If x * y modulo the denominator is strictly greater than 0,
            // 1 is added to round up the division of x * y by the denominator.
            z := add(
                gt(mod(mul(x, y), denominator), 0),
                div(mul(x, y), denominator)
            )
        }
    }

    /// @notice Calculates a WAD approximation of e^(x*n) using a Taylor series expansion
    /// @param x The base WAD number
    /// @param n The exponent
    /// @return The result of the WAD approximation of e^(x*n)
    function wadCompounded(
        uint256 x,
        uint256 n
    ) internal pure returns (uint256) {
        uint256 firstTerm = x * n;
        uint256 secondTerm = mulDivDown(firstTerm, firstTerm, 2 * WAD);
        uint256 thirdTerm = mulDivDown(secondTerm, firstTerm, 3 * WAD);

        return firstTerm + secondTerm + thirdTerm;
    }
}
