// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library UtilsLib {
    /// @dev Returns the min of `x` and `y`.
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }

    /// @dev Returns `x` safely cast to uint128.
    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, "Bank: Overflow");
        return uint128(x);
    }

    /// @dev Returns max(0, x - y).
    function zeroFloorSub(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 z) {
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }
}
