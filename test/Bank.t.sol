// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/Bank.sol";
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
        return 0.05e18; // 5% APR for simplicity
    }
}

contract BankTest is Test {
    Bank public bank;
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    MockPriceProvider public priceProvider;
    MockInterestRateModel public interestRateModel;

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

        bank = new Bank(owner);
        bank.registerIrm(address(interestRateModel), true);

        // Mint tokens to users
        loanToken.mint(user1, INITIAL_BALANCE);
        loanToken.mint(user2, INITIAL_BALANCE);
        collateralToken.mint(user1, INITIAL_BALANCE);
        collateralToken.mint(user2, INITIAL_BALANCE);

        // Approve bank to spend tokens
        vm.prank(user1);
        loanToken.approve(address(bank), type(uint256).max);
        vm.prank(user1);
        collateralToken.approve(address(bank), type(uint256).max);
        vm.prank(user2);
        loanToken.approve(address(bank), type(uint256).max);
        vm.prank(user2);
        collateralToken.approve(address(bank), type(uint256).max);
    }

    function testCreateMarket() public {
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18 // 80% LLTV
        });

        uint256 marketId = bank.createMarket{value: 0.01 ether}(configs);
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
        uint256 marketId = bank.createMarket{value: 0.01 ether}(configs);

        // User1 supplies 100 tokens
        vm.prank(user1);
        (uint256 suppliedAssets, uint256 suppliedShares) = bank.supply(
            marketId,
            100e18,
            ""
        );
        assertEq(suppliedAssets, 100e18, "Supplied assets should be 100");
        assertGt(suppliedShares, 0, "Supplied shares should be greater than 0");

        // User2 supplies 50 collateral tokens
        vm.prank(user2);
        bank.supplyCollateral(marketId, 50e18, "");

        // User2 borrows 30 tokens
        vm.prank(user2);
        (uint256 borrowedAssets, uint256 borrowedShares) = bank.borrow(
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
        uint256 marketId = bank.createMarket{value: 0.01 ether}(configs);

        vm.prank(user1);
        bank.supply(marketId, 100e18, "");

        vm.prank(user2);
        bank.supplyCollateral(marketId, 50e18, "");

        vm.prank(user2);
        bank.borrow(marketId, 30e18, user2);

        // User2 repays 20 tokens
        vm.prank(user2);
        (uint256 repaidAssets, uint256 repaidShares) = bank.repay(
            marketId,
            20e18,
            ""
        );
        assertEq(repaidAssets, 20e18, "Repaid assets should be 20");
        assertGt(repaidShares, 0, "Repaid shares should be greater than 0");

        // User1 withdraws 50 tokens
        vm.prank(user1);
        (uint256 withdrawnAssets, uint256 withdrawnShares) = bank.withdraw(
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
        uint256 marketId = bank.createMarket{value: 0.01 ether}(configs);

        vm.startPrank(user1);
        loanToken.approve(address(bank), type(uint256).max);
        bank.supply(marketId, 100e18, "");
        vm.stopPrank();

        vm.startPrank(user2);
        collateralToken.approve(address(bank), type(uint256).max);
        bank.supplyCollateral(marketId, 50e18, "");
        bank.borrow(marketId, 39e18, user2); // Borrow close to the limit
        vm.stopPrank();

        // Simulate price drop to make the position liquidatable
        priceProvider.setCollateralTokenPrice(0.5e36); // 50% price drop

        // Advance time to accrue some interest
        vm.warp(block.timestamp + 365 days);

        // User1 liquidates User2's position
        vm.startPrank(user1);
        loanToken.approve(address(bank), type(uint256).max);
        (uint256 seizedAssets, uint256 repaidShares) = bank
            .liquidateBySeizedAssets(marketId, user2, 20e18, "");
        vm.stopPrank();

        console.log("Seized Assets:", seizedAssets);
        console.log("Repaid Shares:", repaidShares);

        assertGt(seizedAssets, 0, "Seized assets should be greater than 0");
        assertGt(repaidShares, 0, "Repaid shares should be greater than 0");
    }
}
