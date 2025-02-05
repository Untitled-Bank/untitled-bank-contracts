// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {IDappStakingManagerL2} from "../interfaces/IDappStakingManagerL2.sol";

contract NeemoOracle is IPriceProvider {
    using Math for uint256;

    /* IMMUTABLES */

    IDappStakingManagerL2 public immutable dappStakingManager;
    bool public immutable isNsAstrCollateral;
    uint256 public constant ORACLE_PRICE_SCALE = 10 ** 36;

    error ZeroPrice();

    constructor(
        IDappStakingManagerL2 _dappStakingManager,
        bool _isNsAstrCollateral
    ) {
        dappStakingManager = _dappStakingManager;
        isNsAstrCollateral = _isNsAstrCollateral;
    }

    function isPriceProvider() external pure returns (bool) {
        return true;
    }

    function getCollateralTokenPrice() external view returns (uint256) {
        // Get rate based on collateral type
        uint256 rate = isNsAstrCollateral
            ? dappStakingManager.getRate()
            : dappStakingManager.underlyingToLstRate();

        // Revert if rate is zero
        if (rate == 0) revert ZeroPrice();

        // Scale up the rate and return
        return rate * 1e18;
    }
}
