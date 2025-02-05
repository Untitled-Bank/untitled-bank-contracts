// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUntitledHub, MarketConfigs} from "../interfaces/IUntitledHub.sol";
import {SharesMath} from "../libraries/math/SharesMath.sol";

contract UntitledHubOperation is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SharesMath for uint256;

    IUntitledHub public immutable untitledHub;

    constructor(address _untitledHub) {
        untitledHub = IUntitledHub(_untitledHub);
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

        (, address hubCollateralToken, , , ) = untitledHub.idToMarketConfigs(
            id
        );
        require(
            hubCollateralToken == collateralToken,
            "Invalid collateral token"
        );

        if (collateralAmount > 0) {
            IERC20(collateralToken).safeTransferFrom(
                msg.sender,
                address(this),
                collateralAmount
            );
            IERC20(collateralToken).approve(
                address(untitledHub),
                collateralAmount
            );
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

        (address hubLoanToken, , , , ) = untitledHub.idToMarketConfigs(id);
        require(hubLoanToken == loanToken, "Invalid loan token");

        untitledHub.accrueInterest(id);

        if (repayAmount > 0) {
            uint256 transferAmount;
            if (repayAmount == type(uint256).max) {
                (
                    ,
                    ,
                    uint256 totalBorrowAssets,
                    uint256 totalBorrowShares,
                    ,

                ) = untitledHub.market(id);
                (, uint256 userBorrowShares, ) = untitledHub.position(
                    id,
                    receiver
                );

                transferAmount = userBorrowShares.toAssetsUp(
                    totalBorrowAssets,
                    totalBorrowShares
                );

                // If no debt, exit early
                if (transferAmount == 0) return;
            } else {
                transferAmount = repayAmount;
            }

            // Transfer the calculated amount from the sender
            IERC20(loanToken).safeTransferFrom(
                msg.sender,
                address(this),
                transferAmount
            );
            IERC20(loanToken).approve(address(untitledHub), transferAmount);

            // Perform the repayment
            (uint256 actualRepayAmount, ) = untitledHub.repayFor(
                id,
                transferAmount,
                receiver,
                ""
            );

            // Refund any excess
            if (actualRepayAmount < transferAmount) {
                IERC20(loanToken).safeTransfer(
                    msg.sender,
                    transferAmount - actualRepayAmount
                );
            }
        }

        if (withdrawAmount > 0) {
            untitledHub.withdrawCollateralFor(
                id,
                withdrawAmount,
                receiver,
                receiver
            );
        }
    }
}
