// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./UntitledHub.sol";

contract UntitledHubOperation is ReentrancyGuard {
    using SafeERC20 for IERC20;

    UntitledHub public immutable untitledHub;

    constructor(address _untitledHub) {
        untitledHub = UntitledHub(_untitledHub);
    }

    function supplyCollateralAndBorrow(
        uint256 id,
        uint256 collateralAmount,
        uint256 borrowAmount,
        address collateralToken,
        address receiver
    ) external nonReentrant {
        require(collateralAmount > 0 || borrowAmount > 0, "Invalid amounts");
        require(receiver != address(0), "Invalid receiver");
        require(
            untitledHub.isGranted(msg.sender, address(this)),
            "Permission not granted"
        );

        if (collateralAmount > 0) {
            IERC20(collateralToken).safeTransferFrom(
                msg.sender,
                address(this),
                collateralAmount
            );
            IERC20(collateralToken).approve(address(untitledHub), collateralAmount);
            untitledHub.supplyCollateralFor(id, collateralAmount, receiver, "");
        }

        if (borrowAmount > 0) {
            untitledHub.borrowFor(id, borrowAmount, receiver, receiver);
        }
    }

    function repayAndWithdrawCollateral(
        uint256 id,
        uint256 repayAmount,
        uint256 withdrawAmount,
        address loanToken,
        address receiver
    ) external nonReentrant {
        require(repayAmount > 0 || withdrawAmount > 0, "Invalid amounts");
        require(receiver != address(0), "Invalid receiver");
        require(
            untitledHub.isGranted(msg.sender, address(this)),
            "Permission not granted"
        );

        if (repayAmount > 0) {
            IERC20(loanToken).safeTransferFrom(
                msg.sender,
                address(this),
                repayAmount
            );
            IERC20(loanToken).approve(address(untitledHub), repayAmount);
            untitledHub.repayFor(id, repayAmount, receiver, "");
        }

        if (withdrawAmount > 0) {
            untitledHub.withdrawCollateralFor(id, withdrawAmount, receiver, receiver);
        }
    }
}
