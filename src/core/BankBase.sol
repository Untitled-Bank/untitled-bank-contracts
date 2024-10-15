// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import {IBankBase, MarketConfigs, LiquidationParams, Position, Market} from "../interfaces/IBank.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {WadMath, WAD} from "../libraries/math/WadMath.sol";
import {UtilsLib} from "../libraries/UtilsLib.sol";
import {SharesMath} from "../libraries/math/SharesMath.sol";
import "../libraries/ConstantsLib.sol";
import "./BankStorage.sol";

import {IPriceProvider} from "../interfaces/IPriceProvider.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {IBankLiquidateCallback, IBankRepayCallback, IBankSupplyCallback, IBankSupplyCollateralCallback, IBankFlashLoanCallback} from "../interfaces/IBankCallbacks.sol";

abstract contract BankBase is BankStorage {
    using WadMath for uint128;
    using WadMath for uint256;
    using UtilsLib for uint256;
    using SharesMath for uint256;
    using SafeERC20 for ERC20;

    /* MODIFIERS */

    modifier onlyOwner() {
        require(msg.sender == owner, "Bank: not owner");
        _;
    }

    modifier nonZeroAddress(address addr) {
        require(addr != address(0), "Bank: zero address");
        _;
    }

    /* CONSTRUCTOR */

    constructor(address newOwner) nonZeroAddress(newOwner) {
        owner = newOwner;
        marketCreationFee = 0.01 ether; // Initial creation fee set to 0.01 ETH
    }

    /* MARKET CREATION */

    function createMarket(
        MarketConfigs memory marketConfigs
    ) external payable returns (uint256) {
        require(
            IPriceProvider(marketConfigs.oracle).isPriceProvider(),
            "Bank: invalid oracle"
        );
        require(
            IInterestRateModel(marketConfigs.irm).isIrm(),
            "Bank: invalid IRM"
        );
        require(isIrmRegistered[marketConfigs.irm], "Bank: IRM not registered");
        require(marketConfigs.lltv < 1e18, "Bank: wrong LLTV");
        require(
            msg.value >= marketCreationFee,
            "Bank: insufficient creation fee"
        );

        uint256 newId = ++lastUsedId;
        require(market[newId].lastUpdate == 0, "Bank: market already created");

        // Safe "unchecked" cast.
        market[newId].lastUpdate = uint128(block.timestamp);
        idToMarketConfigs[newId] = marketConfigs;

        emit CreateMarket(newId, marketConfigs);

        // Call to initialize the IRM in case it is stateful.
        if (marketConfigs.irm != address(0))
            IInterestRateModel(marketConfigs.irm).borrowRate(
                marketConfigs,
                market[newId]
            );

        // Add the creation fee to the collected fees
        collectedFees += msg.value;

        return newId;
    }

    function registerIrm(address irm, bool isIrm) external onlyOwner {
        require(IInterestRateModel(irm).isIrm(), "Bank: invalid IRM");
        isIrmRegistered[irm] = isIrm;
    }

    /* FEE MANAGEMENT */

    function setFee(uint256 id, uint256 newFee) external onlyOwner {
        require(market[id].lastUpdate != 0, "Bank: market not created");
        require(newFee != market[id].fee, "Bank: already set");
        require(newFee <= 0.3e18, "Bank: max fee exceeded");

        _accrueInterest(id);

        market[id].fee = uint128(newFee);

        emit SetFee(id, newFee);
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != feeRecipient, "Bank: already set");

        feeRecipient = newFeeRecipient;

        emit SetFeeRecipient(newFeeRecipient);
    }

    function setMarketCreationFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = marketCreationFee;
        marketCreationFee = newFee;
        emit MarketCreationFeeUpdated(oldFee, newFee);
    }

    function withdrawFees(uint256 amount) external onlyOwner {
        require(amount <= collectedFees, "Bank: insufficient collected fees");
        collectedFees -= amount;
        payable(owner).transfer(amount);
        emit FeesWithdrawn(amount);
    }

    /* SUPPLY MANAGEMENT */

    function _supply(
        uint256 id,
        uint256 assets,
        address supplier,
        bytes calldata data
    ) internal nonZeroAddress(supplier) returns (uint256, uint256) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        require(market[id].lastUpdate != 0, "Bank: market not created");
        require(_isSenderGranted(supplier), "Bank: not granted");
        require(assets != 0, "Bank: zero assets");

        _accrueInterest(id);

        uint256 shares = assets.toSharesDown(
            market[id].totalSupplyAssets,
            market[id].totalSupplyShares
        );

        position[id][supplier].supplyShares += shares;
        market[id].totalSupplyShares += shares.toUint128();
        market[id].totalSupplyAssets += assets.toUint128();

        emit Supply(id, msg.sender, supplier, assets, shares);

        if (data.length > 0) {
            IBankSupplyCallback(msg.sender).onBankSupply(assets, data);
        }

        ERC20(marketConfigs.loanToken).safeTransferFrom(
            msg.sender,
            address(this),
            assets
        );

        return (assets, shares);
    }

    function _withdraw(
        uint256 id,
        uint256 assets,
        address withdrawer,
        address receiver
    ) internal nonZeroAddress(receiver) returns (uint256, uint256) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        require(market[id].lastUpdate != 0, "Bank: market not created");
        require(_isSenderGranted(withdrawer), "Bank: not granted");
        require(assets != 0, "Bank: zero assets");

        _accrueInterest(id);

        uint256 shares;
        uint256 userShares = position[id][withdrawer].supplyShares;
        if (assets == type(uint256).max) {
            assets = userShares.toAssetsDown(
                market[id].totalSupplyAssets,
                market[id].totalSupplyShares
            );
            require(assets != 0, "Bank: zero assets");
            shares = userShares;
        } else {
            shares = assets.toSharesUp(
                market[id].totalSupplyAssets,
                market[id].totalSupplyShares
            );
            require(shares <= userShares, "Bank: insufficient balance");
        }

        position[id][withdrawer].supplyShares -= shares;
        market[id].totalSupplyShares -= shares.toUint128();
        market[id].totalSupplyAssets -= assets.toUint128();

        require(
            market[id].totalBorrowAssets <= market[id].totalSupplyAssets,
            "Bank: insufficient liquidity"
        );

        emit Withdraw(id, msg.sender, withdrawer, receiver, assets, shares);

        ERC20(marketConfigs.loanToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    function _borrow(
        uint256 id,
        uint256 assets,
        address borrower,
        address receiver
    ) internal nonZeroAddress(receiver) returns (uint256, uint256) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        require(market[id].lastUpdate != 0, "Bank: market not created");
        require(_isSenderGranted(borrower), "Bank: not granted");
        require(assets != 0, "Bank: zero assets");

        _accrueInterest(id);

        uint256 shares = assets.toSharesUp(
            market[id].totalBorrowAssets,
            market[id].totalBorrowShares
        );

        position[id][borrower].borrowShares += shares.toUint128();
        market[id].totalBorrowShares += shares.toUint128();
        market[id].totalBorrowAssets += assets.toUint128();

        require(
            getHealthFactor(id, borrower) >= WAD,
            "Bank: insufficient collateral"
        );
        require(
            market[id].totalBorrowAssets <= market[id].totalSupplyAssets,
            "Bank: insufficient liquidity"
        );

        emit Borrow(id, msg.sender, borrower, receiver, assets, shares);

        ERC20(marketConfigs.loanToken).safeTransfer(receiver, assets);

        return (assets, shares);
    }

    function _repay(
        uint256 id,
        uint256 assets,
        address repayer,
        bytes calldata data
    ) internal nonZeroAddress(repayer) returns (uint256, uint256) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        require(market[id].lastUpdate != 0, "Bank: market not created");
        require(_isSenderGranted(repayer), "Bank: not granted");
        require(assets != 0, "Bank: zero assets");

        _accrueInterest(id);

        // Calculate the maximum repayable amount
        uint256 maxRepayable = UtilsLib.min(
            assets,
            market[id].totalBorrowAssets
        );

        uint256 shares = maxRepayable.toSharesDown(
            market[id].totalBorrowAssets,
            market[id].totalBorrowShares
        );

        // Ensure the user has enough borrow shares
        uint256 userBorrowShares = position[id][repayer].borrowShares;
        shares = UtilsLib.min(shares, userBorrowShares);

        // Recalculate the actual assets to be repaid based on the adjusted shares
        uint256 actualRepayAmount = shares.toAssetsUp(
            market[id].totalBorrowAssets,
            market[id].totalBorrowShares
        );

        position[id][repayer].borrowShares -= shares.toUint128();
        market[id].totalBorrowShares -= shares.toUint128();
        market[id].totalBorrowAssets -= actualRepayAmount.toUint128();

        emit Repay(id, msg.sender, repayer, actualRepayAmount, shares);

        if (data.length > 0)
            IBankRepayCallback(msg.sender).onBankRepay(actualRepayAmount, data);

        ERC20(marketConfigs.loanToken).safeTransferFrom(
            msg.sender,
            address(this),
            actualRepayAmount
        );

        return (actualRepayAmount, shares);
    }

    /* COLLATERAL MANAGEMENT */

    function _supplyCollateral(
        uint256 id,
        uint256 assets,
        address supplier,
        bytes calldata data
    ) internal nonZeroAddress(supplier) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        require(market[id].lastUpdate != 0, "Bank: market not created");
        require(_isSenderGranted(supplier), "Bank: not granted");
        require(assets != 0, "Bank: zero assets");

        position[id][supplier].collateral += assets.toUint128();

        emit SupplyCollateral(id, msg.sender, supplier, assets);

        if (data.length > 0)
            IBankSupplyCollateralCallback(msg.sender).onBankSupplyCollateral(
                assets,
                data
            );

        ERC20(marketConfigs.collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            assets
        );
    }

    function _withdrawCollateral(
        uint256 id,
        uint256 assets,
        address withdrawer,
        address receiver
    ) internal nonZeroAddress(receiver) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        require(market[id].lastUpdate != 0, "Bank: market not created");
        require(assets != 0, "Bank: zero assets");
        require(_isSenderGranted(withdrawer), "Bank: not granted");

        _accrueInterest(id);

        position[id][withdrawer].collateral -= assets.toUint128();

        require(
            getHealthFactor(id, withdrawer) >= WAD,
            "Bank: insufficient collateral"
        );

        emit WithdrawCollateral(id, msg.sender, withdrawer, receiver, assets);

        ERC20(marketConfigs.collateralToken).safeTransfer(receiver, assets);
    }

    /* LIQUIDATION */

    function _liquidateBySeizedAssets(
        uint256 id,
        address borrower,
        uint256 seizedAssets,
        bytes calldata data
    ) internal returns (uint256, uint256) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        require(market[id].lastUpdate != 0, "Bank: market not created");
        require(seizedAssets != 0, "Bank: zero seized assets");

        _accrueInterest(id);

        require(getHealthFactor(id, borrower) < WAD, "Bank: healthy position");

        LiquidationParams memory params;
        params.liquidationIncentiveFactor = UtilsLib.min(
            MAX_LIQUIDATION_INCENTIVE_FACTOR,
            LIQUIDATION_INTERCEPT.zeroFloorSub(
                LIQUIDATION_SLOPE.mulWadDown(marketConfigs.lltv)
            )
        );

        uint256 collateralPrice = IPriceProvider(marketConfigs.oracle)
            .getCollateralTokenPrice();

        params.seizedAssets = seizedAssets;
        uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(
            collateralPrice,
            ORACLE_PRICE_SCALE
        );
        params.repaidShares = seizedAssetsQuoted
            .divWadUp(params.liquidationIncentiveFactor)
            .toSharesUp(
                market[id].totalBorrowAssets,
                market[id].totalBorrowShares
            );

        // Calculate repaidAssets based on repaidShares
        params.repaidAssets = params.repaidShares.toAssetsDown(
            market[id].totalBorrowAssets,
            market[id].totalBorrowShares
        );

        return _executeLiquidation(id, borrower, params, data);
    }

    function _liquidateByRepaidShares(
        uint256 id,
        address borrower,
        uint256 repaidShares,
        bytes calldata data
    ) internal returns (uint256, uint256) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        require(market[id].lastUpdate != 0, "Bank: market not created");
        require(repaidShares != 0, "Bank: zero repaid shares");

        _accrueInterest(id);

        require(getHealthFactor(id, borrower) < WAD, "Bank: healthy position");

        LiquidationParams memory params;
        params.liquidationIncentiveFactor = UtilsLib.min(
            MAX_LIQUIDATION_INCENTIVE_FACTOR,
            LIQUIDATION_INTERCEPT.zeroFloorSub(
                LIQUIDATION_SLOPE.mulWadDown(marketConfigs.lltv)
            )
        );

        uint256 collateralPrice = IPriceProvider(marketConfigs.oracle)
            .getCollateralTokenPrice();

        params.repaidShares = repaidShares;
        params.seizedAssets = repaidShares
            .toAssetsDown(
                market[id].totalBorrowAssets,
                market[id].totalBorrowShares
            )
            .mulWadDown(params.liquidationIncentiveFactor)
            .mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);

        return _executeLiquidation(id, borrower, params, data);
    }

    function _executeLiquidation(
        uint256 id,
        address borrower,
        LiquidationParams memory params,
        bytes calldata data
    ) private returns (uint256, uint256) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];

        position[id][borrower].collateral -= params.seizedAssets.toUint128();
        position[id][borrower].borrowShares -= params.repaidShares.toUint128();
        market[id].totalBorrowShares -= params.repaidShares.toUint128();
        market[id].totalBorrowAssets -= params.repaidAssets.toUint128();

        emit Liquidate(
            id,
            msg.sender,
            borrower,
            params.seizedAssets,
            params.repaidShares
        );

        ERC20(marketConfigs.collateralToken).safeTransfer(
            msg.sender,
            params.seizedAssets
        );

        if (data.length > 0) {
            IBankLiquidateCallback(msg.sender).onBankLiquidate(
                params.repaidAssets,
                data
            );
        }

        ERC20(marketConfigs.loanToken).safeTransferFrom(
            msg.sender,
            address(this),
            params.repaidAssets
        );

        return (params.seizedAssets, params.repaidShares);
    }

    /* FLASH LOANS */

    function _flashLoan(
        address token,
        uint256 assets,
        bytes calldata data
    ) internal {
        require(assets != 0, "Bank: zero assets");

        emit FlashLoan(msg.sender, token, assets);

        ERC20(token).safeTransfer(msg.sender, assets);

        IBankFlashLoanCallback(msg.sender).onBankFlashLoan(assets, data);

        ERC20(token).safeTransferFrom(msg.sender, address(this), assets);
    }

    function setGrantPermission(address grantee, bool newIsGranted) external {
        require(
            newIsGranted != isGranted[msg.sender][grantee],
            "Bank: already set"
        );

        isGranted[msg.sender][grantee] = newIsGranted;

        emit SetGrantPermission(msg.sender, msg.sender, grantee, newIsGranted);
    }

    function _isSenderGranted(address grantee) internal view returns (bool) {
        return msg.sender == grantee || isGranted[grantee][msg.sender];
    }

    /* INTEREST MANAGEMENT */

    function accrueInterest(uint256 id) external {
        require(market[id].lastUpdate != 0, "Bank: market not created");

        _accrueInterest(id);
    }

    function _accrueInterest(uint256 id) internal {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        uint256 elapsed = block.timestamp - market[id].lastUpdate;
        if (elapsed == 0) return;

        if (marketConfigs.irm != address(0)) {
            uint256 borrowRate = IInterestRateModel(marketConfigs.irm)
                .borrowRate(marketConfigs, market[id]);
            uint256 interest = market[id].totalBorrowAssets.mulWadDown(
                borrowRate.wadCompounded(elapsed)
            );
            market[id].totalBorrowAssets += interest.toUint128();
            market[id].totalSupplyAssets += interest.toUint128();

            uint256 feeShares;
            if (market[id].fee != 0) {
                uint256 feeAmount = interest.mulWadDown(market[id].fee);
                feeShares = feeAmount.toSharesDown(
                    market[id].totalSupplyAssets - feeAmount,
                    market[id].totalSupplyShares
                );
                position[id][feeRecipient].supplyShares += feeShares;
                market[id].totalSupplyShares += feeShares.toUint128();
            }

            emit AccrueInterest(id, borrowRate, interest, feeShares);
        }

        // Safe "unchecked" cast.
        market[id].lastUpdate = uint128(block.timestamp);
    }

    function getHealthFactor(
        uint256 id,
        address borrower
    ) public view returns (uint256) {
        MarketConfigs memory marketConfigs = idToMarketConfigs[id];
        if (position[id][borrower].borrowShares == 0) return type(uint256).max;

        uint256 collateralPrice = IPriceProvider(marketConfigs.oracle)
            .getCollateralTokenPrice();

        uint256 borrowed = uint256(position[id][borrower].borrowShares)
            .toAssetsUp(
                market[id].totalBorrowAssets,
                market[id].totalBorrowShares
            );
        uint256 maxBorrow = uint256(position[id][borrower].collateral)
            .mulDivDown(collateralPrice, ORACLE_PRICE_SCALE)
            .mulWadDown(marketConfigs.lltv);

        return maxBorrow.divWadDown(borrowed);
    }
}
