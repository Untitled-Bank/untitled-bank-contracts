// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/UntitledHub.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockPriceProvider {
    uint256 public price = 1e36;

    function isPriceProvider() external pure returns (bool) {
        return true;
    }

    function getCollateralTokenPrice() external view returns (uint256) {
        return price;
    }

    function setCollateralTokenPrice(uint256 _price) external {
        price = _price;
    }
}

contract MockInterestRateModel {
    function isIrm() external pure returns (bool) {
        return true;
    }

    function borrowRate(
        MarketConfigs memory,
        Market memory
    ) external pure returns (uint256) {
        uint256 util = 0.05 * 1e18;
        return util / 365 days;
    }
}

contract MockInvalidInterestRateModel {
    function borrowRate(
        MarketConfigs memory,
        Market memory
    ) external pure returns (uint256) {
        uint256 util = 0.05 * 1e18;
        return util / 365 days;
    }
}

contract UntitledHubTest is Test {
    receive() external payable {}

    UntitledHub public untitledHub;
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    MockPriceProvider public priceProvider;
    MockInterestRateModel public interestRateModel;
    MockInvalidInterestRateModel public invalidInterestRateModel;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_BALANCE = 1000e18;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        loanToken = new MockERC20("Loan Token", "LOAN");
        collateralToken = new MockERC20("Collateral Token", "COLL");
        priceProvider = new MockPriceProvider();
        interestRateModel = new MockInterestRateModel();
        untitledHub = new UntitledHub(owner);
        untitledHub.registerIrm(address(interestRateModel), true);

        // Mint tokens to users
        loanToken.mint(user1, INITIAL_BALANCE);
        loanToken.mint(user2, INITIAL_BALANCE);
        collateralToken.mint(user1, INITIAL_BALANCE);
        collateralToken.mint(user2, INITIAL_BALANCE);

        // Approve untitledHub to spend tokens
        vm.prank(user1);
        loanToken.approve(address(untitledHub), type(uint256).max);
        vm.prank(user1);
        collateralToken.approve(address(untitledHub), type(uint256).max);
        vm.prank(user2);
        loanToken.approve(address(untitledHub), type(uint256).max);
        vm.prank(user2);
        collateralToken.approve(address(untitledHub), type(uint256).max);
    }

    function testCreateMarket() public {
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18 // 80% LLTV
        });

        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
        assertEq(marketId, 1, "Market ID should be 1");
    }

    function testSupplyAndBorrow() public {
        // Create market
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18 // 80% LLTV
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        // User1 supplies 100 tokens
        vm.prank(user1);
        (uint256 suppliedAssets, uint256 suppliedShares) = untitledHub.supply(
            marketId,
            100e18,
            ""
        );
        assertEq(suppliedAssets, 100e18, "Supplied assets should be 100");
        assertGt(suppliedShares, 0, "Supplied shares should be greater than 0");

        // User2 supplies 50 collateral tokens
        vm.prank(user2);
        untitledHub.supplyCollateral(marketId, 50e18, "");

        // User2 borrows 30 tokens
        vm.prank(user2);
        (uint256 borrowedAssets, uint256 borrowedShares) = untitledHub.borrow(
            marketId,
            30e18,
            user2
        );
        assertEq(borrowedAssets, 30e18, "Borrowed assets should be 30");
        assertGt(borrowedShares, 0, "Borrowed shares should be greater than 0");
    }

    function testRepayAndWithdraw() public {
        // Create market and supply/borrow as in previous test
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18 // 80% LLTV
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        vm.prank(user1);
        untitledHub.supply(marketId, 100e18, "");

        vm.prank(user2);
        untitledHub.supplyCollateral(marketId, 50e18, "");

        vm.prank(user2);
        untitledHub.borrow(marketId, 30e18, user2);

        // User2 repays 20 tokens
        vm.prank(user2);
        (uint256 repaidAssets, uint256 repaidShares) = untitledHub.repay(
            marketId,
            20e18,
            ""
        );
        assertEq(repaidAssets, 20e18, "Repaid assets should be 20");
        assertGt(repaidShares, 0, "Repaid shares should be greater than 0");

        // User1 withdraws 50 tokens
        vm.prank(user1);
        (uint256 withdrawnAssets, uint256 withdrawnShares) = untitledHub.withdraw(
            marketId,
            50e18,
            user1
        );
        assertEq(withdrawnAssets, 50e18, "Withdrawn assets should be 50");
        assertGt(
            withdrawnShares,
            0,
            "Withdrawn shares should be greater than 0"
        );
    }

    
    function testLiquidation() public {
        // Create market and supply/borrow as in previous tests
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18 // 80% LLTV
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        vm.startPrank(user1);
        loanToken.approve(address(untitledHub), type(uint256).max);
        untitledHub.supply(marketId, 100e18, "");
        vm.stopPrank();

        vm.startPrank(user2);
        collateralToken.approve(address(untitledHub), type(uint256).max);
        untitledHub.supplyCollateral(marketId, 50e18, "");
        untitledHub.borrow(marketId, 39e18, user2); // Borrow close to the limit
        vm.stopPrank();

        // Simulate price drop to make the position liquidatable
        priceProvider.setCollateralTokenPrice(0.5e36); // 50% price drop

        // Advance time to accrue some interest
        vm.warp(block.timestamp + 365 days);

        // User1 liquidates User2's position
        vm.startPrank(user1);
        loanToken.approve(address(untitledHub), type(uint256).max);
        (uint256 seizedAssets, uint256 repaidShares) = untitledHub
            .liquidateBySeizedAssets(marketId, user2, 20e18, "");
        vm.stopPrank();

        console.log("Seized Assets:", seizedAssets);
        console.log("Repaid Shares:", repaidShares);

        assertGt(seizedAssets, 0, "Seized assets should be greater than 0");
        assertGt(repaidShares, 0, "Repaid shares should be greater than 0");
    }

    function testLiquidationByRepaidShares() public {
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18 // 80% LLTV
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        vm.startPrank(user1);
        loanToken.approve(address(untitledHub), type(uint256).max);
        untitledHub.supply(marketId, 100e18, "");
        vm.stopPrank();

        vm.startPrank(user2);
        collateralToken.approve(address(untitledHub), type(uint256).max);
        untitledHub.supplyCollateral(marketId, 50e18, "");
        untitledHub.borrow(marketId, 39e18, user2); // Borrow close to the limit
        vm.stopPrank();

        // Simulate price drop to make the position liquidatable
        priceProvider.setCollateralTokenPrice(0.5e36); // 50% price drop

        vm.warp(block.timestamp + 365 days);

        (, uint128 borrowShares, uint128 collateral) = untitledHub.position(marketId, user2);
        uint256 repaidShares = borrowShares / 2; // Try to repay half of the debt

        // User1 liquidates User2's position using repaidShares
        vm.startPrank(user1);
        loanToken.approve(address(untitledHub), type(uint256).max);
        (uint256 seizedAssets, uint256 actualRepaidShares) = untitledHub
            .liquidateByRepaidShares(marketId, user2, repaidShares, "");
        vm.stopPrank();

        console.log("Seized Assets:", seizedAssets);
        console.log("Repaid Shares:", actualRepaidShares);

        assertGt(seizedAssets, 0, "Seized assets should be greater than 0");
        assertEq(actualRepaidShares, repaidShares, "Actual repaid shares should match requested amount");

        // Verify the liquidation results
        (, uint128 borrowSharesAfter, uint128 collateralAfter) = untitledHub.position(marketId, user2);
        assertEq(
            borrowSharesAfter,
            borrowShares - actualRepaidShares,
            "Borrow shares should be reduced by repaid amount"
        );
        assertEq(
            collateralAfter,
            collateral - uint128(seizedAssets),
            "Collateral should be reduced by seized amount"
        );
    }

    function testAccrueInterest() public {
        // Create market
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18 // 80% LLTV
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        // User1 supplies 100 tokens
        vm.prank(user1);
        untitledHub.supply(marketId, 100e18, "");

        // User2 supplies collateral and borrows
        vm.startPrank(user2);
        untitledHub.supplyCollateral(marketId, 50e18, "");
        untitledHub.borrow(marketId, 30e18, user2);
        vm.stopPrank();

        // Advance time by 1 year
        vm.warp(block.timestamp + 365 days);

        // Get market state before accrual
        (
            uint128 totalSupplyAssetsBefore,
            ,
            uint128 totalBorrowAssetsBefore,
            ,
            ,
        ) = untitledHub.market(marketId);        
        // Accrue interest
        untitledHub.accrueInterest(marketId);

        // Get market state after accrual
        (
            uint128 totalSupplyAssetsAfter,
            ,
            uint128 totalBorrowAssetsAfter,
            ,
            ,
        ) = untitledHub.market(marketId);

        // With 5% APR and 30 tokens borrowed, expect roughly 1.5 tokens of interest after a year
        // 5% APR to APY => about 5.127%
        uint256 expectedInterest = 30 * 0.05127 * 1e18;
        uint256 actualInterest = totalBorrowAssetsAfter - totalBorrowAssetsBefore;
        
        // Allow for small rounding differences
        assertApproxEqRel(
            actualInterest,
            expectedInterest,
            0.01e18, // 1% tolerance
            "Interest accrual amount incorrect"
        );

        // Verify that supply assets increased by the same amount as borrow assets
        assertEq(
            totalSupplyAssetsAfter - totalSupplyAssetsBefore,
            totalBorrowAssetsAfter - totalBorrowAssetsBefore,
            "Supply and borrow asset changes should match"
        );
    }

    function testSupplyFor() public {
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        // Grant permission for user1 to supply on behalf of user2
        vm.prank(user2);
        untitledHub.setGrantPermission(user1, true);

        // User1 supplies for user2
        vm.prank(user1);
        (uint256 suppliedAssets, uint256 suppliedShares) = untitledHub.supplyFor(
            marketId,
            100e18,
            user2,
            ""
        );

        assertEq(suppliedAssets, 100e18, "Supplied assets should be 100");
        assertGt(suppliedShares, 0, "Supplied shares should be greater than 0");
    }

    function testWithdrawFor() public {
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        // User1 supplies
        vm.prank(user1);
        untitledHub.supply(marketId, 100e18, "");

        // Grant permission for user2 to withdraw on behalf of user1
        vm.prank(user1);
        untitledHub.setGrantPermission(user2, true);

        // User2 withdraws for user1
        vm.prank(user2);
        (uint256 withdrawnAssets, uint256 withdrawnShares) = untitledHub.withdrawFor(
            marketId,
            50e18,
            user1,
            user1
        );

        assertEq(withdrawnAssets, 50e18, "Withdrawn assets should be 50");
        assertGt(withdrawnShares, 0, "Withdrawn shares should be greater than 0");
    }

    function testBorrowFor() public {
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        // Setup initial state
        vm.prank(user1);
        untitledHub.supply(marketId, 100e18, "");

        vm.prank(user2);
        untitledHub.supplyCollateral(marketId, 50e18, "");

        // Grant permission for user1 to borrow on behalf of user2
        vm.prank(user2);
        untitledHub.setGrantPermission(user1, true);

        // User1 borrows for user2
        vm.prank(user1);
        (uint256 borrowedAssets, uint256 borrowedShares) = untitledHub.borrowFor(
            marketId,
            30e18,
            user2,
            user2
        );

        assertEq(borrowedAssets, 30e18, "Borrowed assets should be 30");
        assertGt(borrowedShares, 0, "Borrowed shares should be greater than 0");
    }

    function testRepayFor() public {
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        // Setup initial state
        vm.prank(user1);
        untitledHub.supply(marketId, 100e18, "");

        vm.startPrank(user2);
        untitledHub.supplyCollateral(marketId, 50e18, "");
        untitledHub.borrow(marketId, 30e18, user2);
        vm.stopPrank();

        // Grant permission for user1 to repay on behalf of user2
        vm.prank(user2);
        untitledHub.setGrantPermission(user1, true);

        // User1 repays for user2
        vm.prank(user1);
        (uint256 repaidAssets, uint256 repaidShares) = untitledHub.repayFor(
            marketId,
            20e18,
            user2,
            ""
        );

        assertEq(repaidAssets, 20e18, "Repaid assets should be 20");
        assertGt(repaidShares, 0, "Repaid shares should be greater than 0");
    }

    function testSetFee() public {
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        uint256 newFee = 0.1e18; // 10% fee
        untitledHub.setFee(marketId, newFee);

        (,,,,,uint128 fee) = untitledHub.market(marketId);
        assertEq(fee, newFee, "Fee not set correctly");
    }

    function testSetFeeRecipient() public {
        address newFeeRecipient = address(0x123);
        untitledHub.setFeeRecipient(newFeeRecipient);
        assertEq(untitledHub.feeRecipient(), newFeeRecipient, "Fee recipient not set correctly");
    }

    function testWithdrawFees() public {
        // Create market to generate fees
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        untitledHub.createMarket{value: 0.01 ether}(configs);

        uint256 initialBalance = address(owner).balance;
        console.log("Collected fees:", untitledHub.collectedFees());
        console.log("initialBalance:", initialBalance);
        
        vm.prank(owner);
        untitledHub.withdrawFees(0.01 ether);
        
        assertEq(
            address(owner).balance,
            initialBalance + 0.01 ether,
            "Fees not withdrawn correctly"
        );
    }

    function testGetHealthFactor() public {
        // Create market
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18 // 80% LLTV
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        // Initial health factor should be max for user with no borrows
        assertEq(
            untitledHub.getHealthFactor(marketId, user1),
            type(uint256).max,
            "Initial health factor should be max"
        );

        // Setup borrowing position
        vm.startPrank(user1);
        untitledHub.supply(marketId, 100e18, "");
        vm.stopPrank();

        vm.startPrank(user2);
        untitledHub.supplyCollateral(marketId, 50e18, "");
        untitledHub.borrow(marketId, 30e18, user2);
        vm.stopPrank();

        // Calculate expected health factor
        // With 50 collateral, price of 1e36, and 80% LLTV, max borrow is 40
        // Current borrow is 30, so health factor should be 40/30 = 1.33...
        uint256 healthFactor = untitledHub.getHealthFactor(marketId, user2);
        assertApproxEqRel(
            healthFactor,
            1.333333333333333333e18,
            0.005e18, // 0.5% tolerance
            "Health factor should be ~1.33"
        );

        // Reduce collateral price by half and check health factor
        priceProvider.setCollateralTokenPrice(0.5e36);
        healthFactor = untitledHub.getHealthFactor(marketId, user2);
        assertApproxEqRel(
            healthFactor,
            0.666666666666666666e18,
            0.005e18,
            "Health factor should be ~0.67 after price drop"
        );
    }

    function testSetMarketCreationFee() public {
        uint256 oldFee = untitledHub.marketCreationFee();
        uint256 newFee = 0.02 ether;

        // Only owner can set fee
        vm.prank(user1);
        vm.expectRevert("UntitledHub: not owner");
        untitledHub.setMarketCreationFee(newFee);

        // Owner can set fee
        untitledHub.setMarketCreationFee(newFee);
        assertEq(
            untitledHub.marketCreationFee(),
            newFee,
            "Market creation fee not updated"
        );

        // Test market creation with new fee
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });

        // Should fail with insufficient fee
        vm.expectRevert("UntitledHub: insufficient creation fee");
        untitledHub.createMarket{value: oldFee}(configs);

        // Should succeed with new fee
        uint256 marketId = untitledHub.createMarket{value: newFee}(configs);
        assertEq(marketId, 1, "Market should be created with new fee");
    }

    function testRegisterIrm() public {
        address newIrm = address(new MockInterestRateModel());
        
        // Only owner can register IRM
        vm.prank(user1);
        vm.expectRevert("UntitledHub: not owner");
        untitledHub.registerIrm(newIrm, true);

        // EOA address
        vm.expectRevert();
        untitledHub.registerIrm(address(0x123), true);

        // Invalid IRM interface
        invalidInterestRateModel = new MockInvalidInterestRateModel();
        vm.expectRevert("UntitledHub: invalid IRM interface");
        untitledHub.registerIrm(address(invalidInterestRateModel), true);

        // Owner can register valid IRM
        untitledHub.registerIrm(newIrm, true);
        assertTrue(
            untitledHub.isIrmRegistered(newIrm),
            "IRM should be registered"
        );

        // Owner can unregister IRM
        untitledHub.registerIrm(newIrm, false);
        assertFalse(
            untitledHub.isIrmRegistered(newIrm),
            "IRM should be unregistered"
        );

        // Test market creation with unregistered IRM
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: newIrm,
            lltv: 0.8e18
        });
        
        vm.expectRevert("UntitledHub: IRM not registered");
        untitledHub.createMarket{value: 0.01 ether}(configs);
    }
}
