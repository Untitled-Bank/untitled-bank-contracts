// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IUntitledHubBase, IUntitledHub, MarketConfigs, Position, Market} from "../interfaces/IUntitledHub.sol";
import {IUntitledHubLiquidateCallback, IUntitledHubRepayCallback, IUntitledHubSupplyCallback, IUntitledHubSupplyCollateralCallback, IUntitledHubFlashLoanCallback} from "../interfaces/IUntitledHubCallbacks.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {UntitledHubBase} from "./UntitledHubBase.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/ConstantsLib.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {WadMath, WAD} from "../libraries/math/WadMath.sol";
import {SharesMath} from "../libraries/math/SharesMath.sol";
import "./UntitledHubStorage.sol";

contract UntitledHub is IUntitledHub, UntitledHubBase {
    using WadMath for uint128;
    using WadMath for uint256;
    using UtilsLib for uint256;
    using SharesMath for uint256;
    using SafeERC20 for ERC20;

    /* CONSTRUCTOR */

    constructor(address _newOwner) UntitledHubBase(_newOwner) {}

    /* LENDING MANAGEMENT */

    function supply(
        uint256 id,
        uint256 assets,
        bytes calldata data
    ) external returns (uint256, uint256) {
        return _supply(id, assets, msg.sender, data);
    }

    function supplyFor(
        uint256 id,
        uint256 assets,
        address supplier,
        bytes calldata data
    ) external returns (uint256, uint256) {
        return _supply(id, assets, supplier, data);
    }

    function withdraw(
        uint256 id,
        uint256 assets,
        address receiver
    ) external returns (uint256, uint256) {
        return _withdraw(id, assets, msg.sender, receiver);
    }

    function withdrawFor(
        uint256 id,
        uint256 assets,
        address withdrawer,
        address receiver
    ) external returns (uint256, uint256) {
        return _withdraw(id, assets, withdrawer, receiver);
    }

    function borrow(
        uint256 id,
        uint256 assets,
        address receiver
    ) external returns (uint256, uint256) {
        return _borrow(id, assets, msg.sender, receiver);
    }

    function borrowFor(
        uint256 id,
        uint256 assets,
        address borrower,
        address receiver
    ) external returns (uint256, uint256) {
        return _borrow(id, assets, borrower, receiver);
    }

    function repay(
        uint256 id,
        uint256 assets,
        bytes calldata data
    ) external returns (uint256, uint256) {
        return _repay(id, assets, msg.sender, data);
    }

    function repayFor(
        uint256 id,
        uint256 assets,
        address repayer,
        bytes calldata data
    ) external returns (uint256, uint256) {
        return _repay(id, assets, repayer, data);
    }

    function supplyCollateral(
        uint256 id,
        uint256 assets,
        bytes calldata data
    ) external {
        return _supplyCollateral(id, assets, msg.sender, data);
    }

    function supplyCollateralFor(
        uint256 id,
        uint256 assets,
        address supplier,
        bytes calldata data
    ) external {
        return _supplyCollateral(id, assets, supplier, data);
    }

    function withdrawCollateral(
        uint256 id,
        uint256 assets,
        address receiver
    ) external {
        return _withdrawCollateral(id, assets, msg.sender, receiver);
    }

    function withdrawCollateralFor(
        uint256 id,
        uint256 assets,
        address withdrawer,
        address receiver
    ) external {
        return _withdrawCollateral(id, assets, withdrawer, receiver);
    }

    /* LIQUIDATION */

    function liquidateBySeizedAssets(
        uint256 id,
        address borrower,
        uint256 maxSeizedAssets,
        bytes calldata data
    ) external returns (uint256 seizedAssets, uint256 repaidShares) {
        return _liquidateBySeizedAssets(id, borrower, maxSeizedAssets, data);
    }

    function liquidateByRepaidShares(
        uint256 id,
        address borrower,
        uint256 maxRepaidShares,
        bytes calldata data
    ) external returns (uint256 seizedAssets, uint256 repaidShares) {
        return _liquidateByRepaidShares(id, borrower, maxRepaidShares, data);
    }

    /* FLASH LOANS */

    function flashLoan(
        address token,
        uint256 assets,
        bytes calldata data
    ) external {
        return _flashLoan(token, assets, data);
    }
}
