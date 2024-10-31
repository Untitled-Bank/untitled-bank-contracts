// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/Bank.sol";
import "../src/interfaces/IBank.sol";
import "../src/core/UntitledHub.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/libraries/math/WadMath.sol";

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
        uint256 util = 0.05 * 1e18; // 5% APR for simplicity
        return util / 365 days; 
    }
}

contract BankTest is Test {
    using WadMath for uint256;
    using WadMath for uint128;
    using SharesMath for uint256;

    Bank public bank;
    UntitledHub public untitledHub;
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    MockPriceProvider public priceProvider;
    MockInterestRateModel public interestRateModel;

    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public feeRecipient;
    
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant FEE = 500; // 5%

    event MarketAdded(uint256 indexed id, uint256 allocation);
    event FeeUpdated(uint256 newFee);
    event FeeAccrued(uint256 feeAmount, uint256 feeShares);
    event MarketRemoved(uint256 indexed id);
    event WhitelistUpdated(address indexed account, bool status);
    event MarketsReallocated(uint256[] ids, uint256[] newAllocations);
    event MarketAdditionCancelled(uint256 indexed id, uint256 allocation, bytes32 indexed operationId);
    event MarketRemovalCancelled(uint256 indexed id, bytes32 indexed operationId);
    event FeeUpdateCancelled(uint256 newFee, bytes32 indexed operationId);
    event FeeRecipientUpdateCancelled(address newFeeRecipient, bytes32 indexed operationId);
    event WhitelistUpdateCancelled(address account, bool status, bytes32 indexed operationId);
    event ReallocateCancelled(uint256[] withdrawIds, uint256[] withdrawAmounts, uint256[] depositIds, uint256[] depositAmounts, bytes32 indexed operationId);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);
        feeRecipient = address(0x4);

        // Deploy mock tokens and services
        loanToken = new MockERC20("Loan Token", "LOAN");
        collateralToken = new MockERC20("Collateral Token", "COLL");
        priceProvider = new MockPriceProvider();
        interestRateModel = new MockInterestRateModel();

        // Deploy UntitledHub and register IRM
        untitledHub = new UntitledHub(owner);
        untitledHub.registerIrm(address(interestRateModel), true);

        // Deploy Bank
        bank = new Bank(
            IERC20(address(loanToken)),
            "Untitled Bank",
            "uBANK",
            untitledHub,
            FEE,
            feeRecipient,
            MIN_DELAY,
            owner,
            IBank.BankType.Public
        );

        // Mint tokens to users
        loanToken.mint(user1, INITIAL_BALANCE);
        loanToken.mint(user2, INITIAL_BALANCE);
        
        // Approve bank to spend tokens
        vm.prank(user1);
        loanToken.approve(address(bank), type(uint256).max);
        vm.prank(user2);
        loanToken.approve(address(bank), type(uint256).max);

        // Grant roles
        bank.grantRole(bank.PROPOSER_ROLE(), owner);
        bank.grantRole(bank.EXECUTOR_ROLE(), owner);
    }

    function testInitialState() view public {
        assertEq(address(bank.untitledHub()), address(untitledHub));
        assertEq(bank.getFee(), FEE);
        assertEq(bank.getFeeRecipient(), feeRecipient);
        assertEq(uint8(bank.getBankType()), 0); // BankType.Public
    }

    function testAddMarket() public {
        // Create market in UntitledHub
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        // Schedule market addition
        uint256 allocation = 5000; // 50%
        bank.scheduleAddMarket(marketId, allocation, MIN_DELAY);
        
        // Warp time and execute
        vm.warp(block.timestamp + MIN_DELAY);
        vm.expectEmit(true, true, true, true);
        emit MarketAdded(marketId, allocation);
        bank.executeAddMarket(marketId, allocation);

        // Verify market was added
        IBank.MarketAllocation[] memory allocations = bank.getMarketAllocations();
        assertEq(allocations.length, 1);
        assertEq(allocations[0].id, marketId);
        assertEq(allocations[0].allocation, allocation);
        assertTrue(bank.isMarketEnabled(marketId));
    }

    function testDeposit() public {
        // Setup market first
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
        
        bank.scheduleAddMarket(marketId, 10000, MIN_DELAY); // 100% allocation
        vm.warp(block.timestamp + MIN_DELAY);
        bank.executeAddMarket(marketId, 10000);

        // Test deposit
        uint256 depositAmount = 100e18;
        vm.prank(user1);
        bank.deposit(depositAmount, user1);

        // Verify deposit
        assertEq(bank.balanceOf(user1), depositAmount);
        assertEq(bank.totalAssets(), depositAmount);
        
        // Verify funds were supplied to UntitledHub
        (uint256 supplyShares,,) = untitledHub.position(marketId, address(bank));
        assertTrue(supplyShares > 0);
    }

    function testWithdraw() public {
        // Setup market and deposit first
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
        
        bank.scheduleAddMarket(marketId, 10000, MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);
        bank.executeAddMarket(marketId, 10000);

        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        bank.deposit(depositAmount, user1);
        
        // Test withdraw
        uint256 withdrawAmount = 50e18;
        bank.withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();

        // Verify withdraw
        assertEq(bank.balanceOf(user1), depositAmount - withdrawAmount);
        assertEq(bank.totalAssets(), depositAmount - withdrawAmount);
    }

    function testFeeAccrual() public {
        // Setup market and deposit
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
        
        bank.scheduleAddMarket(marketId, 10000, MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);
        bank.executeAddMarket(marketId, 10000);

        // Setup borrower
        deal(address(collateralToken), user2, 1000e18);
        vm.startPrank(user2);
        collateralToken.approve(address(untitledHub), type(uint256).max);
        untitledHub.supplyCollateral(marketId, 100e18, "");
        vm.stopPrank();

        // User1 deposits into bank
        uint256 depositAmount = 100e18;
        vm.prank(user1);
        bank.deposit(depositAmount, user1);

        // User2 borrows from the market (borrow 50% of deposit)
        vm.startPrank(user2);
        untitledHub.borrow(marketId, 50e18, user2);
        vm.stopPrank();

        // Record initial states
        uint256 initialTotalAssets = bank.totalAssets();
        uint256 initialFeeRecipientBalance = bank.balanceOf(feeRecipient);

        // Warp time to accrue interest (1 year)
        vm.warp(block.timestamp + 365 days);

        // Accrue interest in UntitledHub
        untitledHub.accrueInterest(marketId);

        uint256 newTotalAssets = bank.totalAssets();
        assertGt(newTotalAssets, initialTotalAssets, "Total assets should increase");

        // Call harvest to accrue fees
        bank.harvest();

        // Verify fee recipient received shares
        uint256 newFeeRecipientBalance = bank.balanceOf(feeRecipient);
        assertGt(newFeeRecipientBalance, initialFeeRecipientBalance, "Fee recipient should receive shares");

        // Log values for debugging
        console.log("Initial total assets:", initialTotalAssets);
        console.log("New totalAssets:", newTotalAssets);
        console.log("Interest earned:", newTotalAssets - initialTotalAssets);
        console.log("Initial fee recipient balance:", initialFeeRecipientBalance);
        console.log("New fee recipient balance:", newFeeRecipientBalance);
        
        // Calculate actual fee in assets
        uint256 actualFeeInAssets = bank.convertToAssets(newFeeRecipientBalance - initialFeeRecipientBalance);
        uint256 interestEarned = newTotalAssets - initialTotalAssets;
        uint256 expectedFeeAmount = interestEarned.mulWadDown(FEE * 1e18).divWadDown(10000 * 1e18);

        console.log("Expected fee amount:", expectedFeeAmount);
        console.log("Actual fee in assets:", actualFeeInAssets);

        // Use a larger tolerance (5%) due to rounding in various calculations
        assertApproxEqRel(
            actualFeeInAssets, 
            expectedFeeAmount, 
            0.02e18, // 5% tolerance
            "Fee amount outside acceptable range"
        );
        
        // Additional sanity checks
        assertLe(actualFeeInAssets, interestEarned, "Fee should not exceed interest earned");
        assertGe(actualFeeInAssets, (interestEarned * FEE * 95) / (10000 * 100), "Fee should not be too small");
    }
    
    function testUpdateFee() public {
        uint256 newFee = 300; // 3%
        
        // Schedule fee update
        bank.scheduleSetFee(newFee, MIN_DELAY);
        
        // Warp time and execute
        vm.warp(block.timestamp + MIN_DELAY);
        vm.expectEmit(true, true, true, true);
        emit FeeUpdated(newFee);
        bank.executeSetFee(newFee);

        assertEq(bank.getFee(), newFee);
    }

    function testPrivateBank() public {
        // Deploy private bank
        Bank privateBank = new Bank(
            IERC20(address(loanToken)),
            "Private Bank",
            "pBANK",
            untitledHub,
            FEE,
            feeRecipient,
            MIN_DELAY,
            owner,
            IBank.BankType.Private
        );
        
        // add market
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        privateBank.scheduleAddMarket(marketId, 10000, MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);
        privateBank.executeAddMarket(marketId, 10000);

        // Grant roles
        privateBank.grantRole(privateBank.PROPOSER_ROLE(), owner);
        privateBank.grantRole(privateBank.EXECUTOR_ROLE(), owner);

        // Schedule whitelist update
        privateBank.scheduleUpdateWhitelist(user1, true, MIN_DELAY);
        
        // Warp time and execute
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.expectEmit(true, true, true, true);
        emit WhitelistUpdated(user1, true);
        privateBank.executeUpdateWhitelist(user1, true);

        // Verify only whitelisted users can deposit
        vm.prank(user1);
        loanToken.approve(address(privateBank), type(uint256).max);
        
        vm.prank(user1);
        privateBank.deposit(100e18, user1); // Should succeed
        
        vm.prank(user2);
        loanToken.approve(address(privateBank), type(uint256).max);
        
        vm.prank(user2);
        vm.expectRevert("Not whitelisted");
        privateBank.deposit(100e18, user2); // Should fail
    }

    function testRemoveMarket() public {
        // Setup market first
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
        
        bank.scheduleAddMarket(marketId, 10000, MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);
        bank.executeAddMarket(marketId, 10000);

        // Schedule market removal
        bank.scheduleRemoveMarket(marketId, MIN_DELAY);
        
        // Warp time and execute
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.expectEmit(true, true, true, true);
        emit MarketRemoved(marketId);
        bank.executeRemoveMarket(marketId);

        // Verify market was removed
        IBank.MarketAllocation[] memory allocations = bank.getMarketAllocations();
        assertEq(allocations.length, 0);
        assertFalse(bank.isMarketEnabled(marketId));
    }

    function testCancelOperations() public {
        // Setup market configs
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
        
        // Test cancel market addition
        uint256 allocation = 5000;
        bank.scheduleAddMarket(marketId, allocation, MIN_DELAY);
        bytes32 addMarketOpId = keccak256(abi.encode(
            "addMarket",
            marketId,
            allocation
        ));
        vm.expectEmit(true, true, true, true);
        emit MarketAdditionCancelled(marketId, allocation, addMarketOpId);
        bank.cancelAddMarket(marketId, allocation);
        
        // Test cancel market removal
        bank.scheduleAddMarket(marketId, allocation, MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);
        bank.executeAddMarket(marketId, allocation);
        
        bank.scheduleRemoveMarket(marketId, MIN_DELAY);
        bytes32 removeMarketOpId = keccak256(abi.encode(
            "removeMarket",
            marketId
        ));
        
        vm.expectEmit(true, true, true, true);
        emit MarketRemovalCancelled(marketId, removeMarketOpId);
        bank.cancelRemoveMarket(marketId);
        
        // Test cancel fee update
        uint256 newFee = 300;
        bank.scheduleSetFee(newFee, MIN_DELAY);
        bytes32 feeUpdateOpId = keccak256(abi.encode(
            "setFee",
            newFee
        ));
        
        vm.expectEmit(true, true, true, true);
        emit FeeUpdateCancelled(newFee, feeUpdateOpId);
        bank.cancelSetFee(newFee);
        
        // Test cancel fee recipient update
        address newFeeRecipient = address(0x123);
        bank.scheduleSetFeeRecipient(newFeeRecipient, MIN_DELAY);
        bytes32 feeRecipientUpdateOpId = keccak256(abi.encode(
            "setFeeRecipient",
            newFeeRecipient
        ));
        
        vm.expectEmit(true, true, true, true);
        emit FeeRecipientUpdateCancelled(newFeeRecipient, feeRecipientUpdateOpId);
        bank.cancelSetFeeRecipient(newFeeRecipient);
        
        // Test cancel whitelist update
        // Deploy private bank
        Bank privateBank = new Bank(
            IERC20(address(loanToken)),
            "Private Bank",
            "pBANK", 
            untitledHub,
            FEE,
            feeRecipient,
            MIN_DELAY,
            owner,
            IBank.BankType.Private
        );

        // Grant roles
        privateBank.grantRole(privateBank.PROPOSER_ROLE(), owner);
        privateBank.grantRole(privateBank.EXECUTOR_ROLE(), owner);
        privateBank.scheduleUpdateWhitelist(owner, true, MIN_DELAY);
        bytes32 whitelistUpdateOpId = keccak256(abi.encode(
            "updateWhitelist",
            owner,
            true
        ));
        
        vm.expectEmit(true, true, true, true);
        emit WhitelistUpdateCancelled(owner, true, whitelistUpdateOpId);
        privateBank.cancelUpdateWhitelist(owner, true);
        
        // Test cancel markets reallocation
        uint256[] memory ids = new uint256[](1);
        uint256[] memory newAllocations = new uint256[](1);
        ids[0] = marketId;
        newAllocations[0] = 10e18;
        
        bank.scheduleReallocate(ids, newAllocations, ids, newAllocations, MIN_DELAY);
        bytes32 reallocateOpId = keccak256(abi.encode(
            "reallocate",
            ids,
            newAllocations,
            ids,
            newAllocations
        ));
        
        vm.expectEmit(true, true, true, true);
        emit ReallocateCancelled(ids, newAllocations, ids, newAllocations, reallocateOpId);
        bank.cancelReallocate(ids, newAllocations, ids, newAllocations);
    }

    function testRemoveMarketWithActiveLoans() public {
        uint256 timestamp = block.timestamp;

        // Setup initial market
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);

        // add more deposit to untitledHub directly (supply)
        deal(address(loanToken), user3, 30000e18);
        vm.startPrank(user3);
        loanToken.approve(address(untitledHub), type(uint256).max);
        untitledHub.supply(marketId, 10000e18, "");
        vm.stopPrank();

        bank.scheduleAddMarket(marketId, 10000, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeAddMarket(marketId, 10000);

        // User1 deposits into bank
        uint256 depositAmount = 1000e18;
        vm.startPrank(user1);
        bank.deposit(depositAmount, user1);
        vm.stopPrank();

        // add another market
        uint256 marketId2 = untitledHub.createMarket{value: 0.01 ether}(configs);
        bank.scheduleAddMarket(marketId2, 10000, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeAddMarket(marketId2, 10000);

        // Setup borrower
        deal(address(collateralToken), user2, 1000e18);
        vm.startPrank(user2);
        collateralToken.approve(address(untitledHub), type(uint256).max);
        untitledHub.supplyCollateral(marketId, 100e18, "");
        untitledHub.borrow(marketId, 50e18, user2); // Borrow 50% of deposit
        vm.stopPrank();

        // Try to remove market
        bank.scheduleRemoveMarket(marketId, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeRemoveMarket(marketId);

        // Verify market was removed
        assertFalse(bank.isMarketEnabled(marketId));
        
        // Verify funds were properly withdrawn
        (uint256 supplyShares,,) = untitledHub.position(marketId, address(bank));
        assertEq(supplyShares, 0, "Supply shares should be 0 after market removal");
        
        // Verify bank's total assets remain intact
        assertApproxEqRel(
            bank.totalAssets(),
            depositAmount,
            0.01e18, // 1% tolerance for potential rounding
            "Total assets should remain approximately the same"
        );
    }

    function testRemoveMarketWithPendingInterest() public {
        uint256 timestamp = block.timestamp;

        // Setup market
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
        
        bank.scheduleAddMarket(marketId, 10000, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeAddMarket(marketId, 10000);

        // add more deposit to untitledHub directly (supply)
        deal(address(loanToken), user3, 30000e18);
        vm.startPrank(user3);
        loanToken.approve(address(untitledHub), type(uint256).max);
        untitledHub.supply(marketId, 10000e18, "");
        vm.stopPrank();

        // User1 deposits
        uint256 depositAmount = 1000e18;
        vm.startPrank(user1);
        bank.deposit(depositAmount, user1);
        vm.stopPrank();

        // Setup borrower
        deal(address(collateralToken), user2, 1000e18);
        vm.startPrank(user2);
        collateralToken.approve(address(untitledHub), type(uint256).max);
        untitledHub.supplyCollateral(marketId, 100e18, "");
        untitledHub.borrow(marketId, 50e18, user2);
        vm.stopPrank();

        // Warp time to accrue interest
        vm.warp(block.timestamp + 180 days);
        
        // Record state before removal
        uint256 initialTotalAssets = bank.totalAssets();

        // add another market
        uint256 marketId2 = untitledHub.createMarket{value: 0.01 ether}(configs);
        bank.scheduleAddMarket(marketId2, 10000, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeAddMarket(marketId2, 10000);
        
        // Remove market
        bank.scheduleRemoveMarket(marketId, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeRemoveMarket(marketId);

        // Verify market was removed
        assertFalse(bank.isMarketEnabled(marketId));
        
        // Verify accrued interest was captured
        uint256 finalTotalAssets = bank.totalAssets();
        console.log("initialTotalAssets", initialTotalAssets);
        console.log("finalTotalAssets", finalTotalAssets);
        assertTrue(
            finalTotalAssets > initialTotalAssets,
            "Total assets should increase due to accrued interest"
        );
        
        // Verify user can withdraw with interest
        vm.startPrank(user1);
        uint256 user1BalanceBefore = loanToken.balanceOf(user1);
        uint256 withdrawAmountShares = bank.balanceOf(user1);
        uint256 withdrawAmount = bank.convertToAssets(withdrawAmountShares);
        bank.withdraw(withdrawAmount, user1, user1);
        uint256 user1BalanceAfter = loanToken.balanceOf(user1);
        vm.stopPrank();
        
        console.log("withdrawAmountShares", withdrawAmountShares);
        console.log("withdrawAmount", withdrawAmount);
        console.log("user1BalanceBefore", user1BalanceBefore);
        console.log("user1BalanceAfter", user1BalanceAfter);
        console.log("depositAmount", depositAmount);

        assertTrue(
            user1BalanceAfter - user1BalanceBefore > depositAmount,
            "User should receive original deposit plus interest"
        );
    }

    function testRemoveNonExistentMarket() public {
        uint256 nonExistentMarketId = 999;
        
        vm.expectRevert("Bank: Market not enabled");
        bank.scheduleRemoveMarket(nonExistentMarketId, MIN_DELAY);
    }

    function testRemoveAndReaddMarket() public {
        uint256 timestamp = block.timestamp;

        // Setup initial market
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
        
        // Add market first time
        bank.scheduleAddMarket(marketId, 10000, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeAddMarket(marketId, 10000);

        // Remove market
        bank.scheduleRemoveMarket(marketId, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeRemoveMarket(marketId);

        // Re-add same market
        bank.scheduleAddMarket(marketId, 5000, MIN_DELAY); // Different allocation
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeAddMarket(marketId, 5000);

        // Verify market was re-added successfully
        assertTrue(bank.isMarketEnabled(marketId));
        
        IBank.MarketAllocation[] memory allocations = bank.getMarketAllocations();
        assertEq(allocations.length, 1);
        assertEq(allocations[0].id, marketId);
        assertEq(allocations[0].allocation, 5000);
    }

    function testReallocateAndUpdateAllocations() public {
        uint256 timestamp = block.timestamp;

        // Setup initial markets
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId1 = untitledHub.createMarket{value: 0.01 ether}(configs);
        uint256 marketId2 = untitledHub.createMarket{value: 0.01 ether}(configs);
        
        // Add markets with initial allocations
        bank.scheduleAddMarket(marketId1, 6000, MIN_DELAY); // 60%
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeAddMarket(marketId1, 6000);

        bank.scheduleAddMarket(marketId2, 4000, MIN_DELAY); // 40%
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeAddMarket(marketId2, 4000);

        // User deposits
        uint256 depositAmount = 1000e18;
        vm.startPrank(user1);
        bank.deposit(depositAmount, user1);
        vm.stopPrank();

        // Record initial positions
        (uint256 initialSupplyShares1,,) = untitledHub.position(marketId1, address(bank));
        (uint256 initialSupplyShares2,,) = untitledHub.position(marketId2, address(bank));

        // Prepare reallocation arrays
        uint256[] memory withdrawIds = new uint256[](1);
        uint256[] memory withdrawAmounts = new uint256[](1);
        uint256[] memory depositIds = new uint256[](1);
        uint256[] memory depositAmounts = new uint256[](1);

        // Move 20% from market1 to market2
        withdrawIds[0] = marketId1;
        withdrawAmounts[0] = 200e18; // 20% of 1000e18
        depositIds[0] = marketId2;
        depositAmounts[0] = 200e18;

        // Schedule and execute reallocation
        bank.scheduleReallocate(withdrawIds, withdrawAmounts, depositIds, depositAmounts, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeReallocate(withdrawIds, withdrawAmounts, depositIds, depositAmounts);

        // Verify new positions
        (uint256 newSupplyShares1,,) = untitledHub.position(marketId1, address(bank));
        (uint256 newSupplyShares2,,) = untitledHub.position(marketId2, address(bank));
        
        // Check that shares decreased in market1 and increased in market2
        assertTrue(newSupplyShares1 < initialSupplyShares1, "Market1 shares should decrease");
        assertTrue(newSupplyShares2 > initialSupplyShares2, "Market2 shares should increase");

        // Test updating allocations
        IBank.MarketAllocation[] memory newAllocations = new IBank.MarketAllocation[](2);
        newAllocations[0] = IBank.MarketAllocation({
            id: marketId1,
            allocation: 4000  // 40%
        });
        newAllocations[1] = IBank.MarketAllocation({
            id: marketId2,
            allocation: 6000  // 60%
        });

        // Schedule and execute allocation update
        bank.scheduleUpdateAllocations(newAllocations, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank.executeUpdateAllocations(newAllocations);

        // Verify new allocations
        IBank.MarketAllocation[] memory updatedAllocations = bank.getMarketAllocations();
        assertEq(updatedAllocations.length, 2, "Should have 2 markets");
        assertEq(updatedAllocations[0].allocation, 4000, "Market1 should have 40% allocation");
        assertEq(updatedAllocations[1].allocation, 6000, "Market2 should have 60% allocation");

        // Test invalid reallocation (mismatched amounts)
        withdrawAmounts[0] = 300e18;
        depositAmounts[0] = 200e18;
        
        vm.expectRevert("Bank: Mismatched total amounts");
        bank.scheduleReallocate(withdrawIds, withdrawAmounts, depositIds, depositAmounts, MIN_DELAY);

        // Test invalid allocation update (total != 100%)
        newAllocations[0].allocation = 5000;
        newAllocations[1].allocation = 6000; // Total > 100%
        
        vm.expectRevert("Bank: Total allocation must be 100%");
        bank.scheduleUpdateAllocations(newAllocations, MIN_DELAY);
    }
}