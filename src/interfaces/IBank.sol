// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

struct MarketConfigs {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

struct Position {
    uint256 supplyShares;
    uint128 borrowShares;
    uint128 collateral;
}

struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

struct LiquidationParams {
    uint256 seizedAssets;
    uint256 repaidShares;
    uint256 repaidAssets;
    uint256 liquidationIncentiveFactor;
}

interface IBankBase {
    function owner() external view returns (address);
    function feeRecipient() external view returns (address);
    function position(
        uint256 id,
        address account
    )
        external
        view
        returns (
            uint256 supplyShares,
            uint128 borrowShares,
            uint128 collateral
        );
    function market(
        uint256 id
    )
        external
        view
        returns (
            uint128 totalSupplyAssets,
            uint128 totalSupplyShares,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            uint128 lastUpdate,
            uint128 fee
        );
    function isIrmRegistered(address irm) external view returns (bool);
    function registerIrm(address irm, bool isIrm) external;
    function isGranted(
        address owner,
        address grantee
    ) external view returns (bool);
    function idToMarketConfigs(
        uint256 id
    )
        external
        view
        returns (
            address loanToken,
            address collateralToken,
            address oracle,
            address irm,
            uint256 lltv
        );
    function marketCreationFee() external view returns (uint256);
    function collectedFees() external view returns (uint256);

    function createMarket(
        MarketConfigs memory marketConfigs
    ) external payable returns (uint256);
    function setMarketCreationFee(uint256 newFee) external;
    function withdrawFees(uint256 amount) external;

    function supply(
        uint256 id,
        uint256 assets,
        bytes calldata data
    ) external returns (uint256, uint256);

    function supplyFor(
        uint256 id,
        uint256 assets,
        address supplier,
        bytes calldata data
    ) external returns (uint256, uint256);

    function withdraw(
        uint256 id,
        uint256 assets,
        address receiver
    ) external returns (uint256, uint256);

    function withdrawFor(
        uint256 id,
        uint256 assets,
        address withdrawer,
        address receiver
    ) external returns (uint256, uint256);

    function borrow(
        uint256 id,
        uint256 assets,
        address receiver
    ) external returns (uint256, uint256);

    function borrowFor(
        uint256 id,
        uint256 assets,
        address borrower,
        address receiver
    ) external returns (uint256, uint256);

    function repay(
        uint256 id,
        uint256 assets,
        bytes calldata data
    ) external returns (uint256, uint256);

    function repayFor(
        uint256 id,
        uint256 assets,
        address repayer,
        bytes calldata data
    ) external returns (uint256, uint256);

    function supplyCollateral(
        uint256 id,
        uint256 assets,
        bytes calldata data
    ) external;

    function supplyCollateralFor(
        uint256 id,
        uint256 assets,
        address supplier,
        bytes calldata data
    ) external;

    function withdrawCollateral(
        uint256 id,
        uint256 assets,
        address receiver
    ) external;

    function withdrawCollateralFor(
        uint256 id,
        uint256 assets,
        address withdrawer,
        address receiver
    ) external;

    function liquidateBySeizedAssets(
        uint256 id,
        address borrower,
        uint256 maxSeizedAssets,
        bytes calldata data
    ) external returns (uint256 seizedAssets, uint256 repaidShares);

    function liquidateByRepaidShares(
        uint256 id,
        address borrower,
        uint256 maxRepaidShares,
        bytes calldata data
    ) external returns (uint256 seizedAssets, uint256 repaidShares);

    function flashLoan(
        address token,
        uint256 assets,
        bytes calldata data
    ) external;

    function setGrantPermission(address grantee, bool newIsGranted) external;

    function getHealthFactor(
        uint256 id,
        address borrower
    ) external view returns (uint256);

    function setFee(uint256 id, uint256 newFee) external;
    function setFeeRecipient(address newFeeRecipient) external;
    function accrueInterest(uint256 id) external;
}

interface IBank is IBankBase {
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event MarketCreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(uint256 amount);
    event CreateMarket(uint256 indexed id, MarketConfigs params);
    event Supply(
        uint256 indexed id,
        address indexed sender,
        address indexed supplier,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        uint256 indexed id,
        address indexed sender,
        address indexed withdrawer,
        address receiver,
        uint256 assets,
        uint256 shares
    );
    event Borrow(
        uint256 indexed id,
        address indexed sender,
        address indexed borrower,
        address receiver,
        uint256 assets,
        uint256 shares
    );
    event Repay(
        uint256 indexed id,
        address indexed sender,
        address indexed repayer,
        uint256 assets,
        uint256 shares
    );
    event SupplyCollateral(
        uint256 indexed id,
        address indexed sender,
        address indexed supplier,
        uint256 assets
    );
    event WithdrawCollateral(
        uint256 indexed id,
        address indexed sender,
        address indexed withdrawer,
        address receiver,
        uint256 assets
    );
    event Liquidate(
        uint256 indexed id,
        address indexed liquidator,
        address indexed borrower,
        uint256 seizedAssets,
        uint256 repaidShares
    );
    event FlashLoan(
        address indexed receiver,
        address indexed token,
        uint256 assets
    );
    event SetGrantPermission(
        address indexed setter,
        address indexed owner,
        address indexed grantee,
        bool isGranted
    );
    event AccrueInterest(
        uint256 indexed id,
        uint256 borrowRate,
        uint256 interest,
        uint256 feeShares
    );
    event SetFee(uint256 indexed id, uint256 newFee);
    event SetFeeRecipient(address indexed newFeeRecipient);
}
