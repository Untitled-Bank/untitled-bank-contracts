// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/CoreBank.sol";
import "../src/core/Bank.sol";
import "../src/interfaces/ICoreBank.sol";
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

// Create a TestBank contract that inherits from Bank but doesn't disable initializers
contract TestBank is Bank {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Don't initialize anything in constructor
    }

    function _disableInitializers() internal override {
        // Override to prevent disabling initializers
    }
}

// Create a TestCoreBank contract that inherits from CoreBank but doesn't disable initializers
contract TestCoreBank is CoreBank {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Don't initialize anything in constructor
    }

    function _disableInitializers() internal override {
        // Override to prevent disabling initializers
    }
}

contract CoreBankTest is Test {
    using WadMath for uint256;

    TestCoreBank public coreBank;
    TestBank public bank1;  // Change to TestBank
    TestBank public bank2;  // Change to TestBank
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    UntitledHub public untitledHub;
    MockPriceProvider public priceProvider;
    MockInterestRateModel public interestRateModel;

    address public owner;
    address public user1;
    address public user2;
    address public feeRecipient;
    
    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint32 public constant MIN_DELAY = 1 days;

    event BankAdded(address indexed bank);
    event BankRemoved(address indexed bank);
    event AllocationsUpdated(ICoreBank.BankAllocation[] newAllocations);
    event BankAdditionCancelled(address indexed bank, bytes32 indexed operationId);
    event BankRemovalCancelled(address indexed bank, bytes32 indexed operationId);
    event AllocationsUpdateCancelled(ICoreBank.BankAllocation[] newAllocations, bytes32 indexed operationId);

    function setUp() public {
        uint256 timestamp = block.timestamp;

        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        feeRecipient = address(0x3);

        // Deploy mock tokens
        loanToken = new MockERC20("Loan Token", "LOAN");
        collateralToken = new MockERC20("Collateral Token", "COLL");

        // Deploy UntitledHub
        untitledHub = new UntitledHub(owner);

        priceProvider = new MockPriceProvider();
        interestRateModel = new MockInterestRateModel();

        // Register irm
        untitledHub.registerIrm(address(interestRateModel), true);

        // Deploy CoreBank
        coreBank = new TestCoreBank();
        
        console.log("CoreBank address:", address(coreBank));
        console.log("Starting CoreBank initialization...");
        
        coreBank.initialize(
            IERC20(address(loanToken)),
            "Core Bank",
            "cBANK",
            MIN_DELAY,
            owner
        );

        console.log("CoreBank initialized successfully");

        // Deploy Banks
        bank1 = new TestBank();  // Use TestBank
        console.log("Bank1 address:", address(bank1));
        console.log("Starting Bank1 initialization...");
        
        bank1.initialize(
            IERC20(address(loanToken)),
            "Bank 1",
            "BANK1",
            untitledHub,
            500, // 5% fee
            feeRecipient,
            MIN_DELAY,
            owner,
            IBank.BankType.Public
        );

        console.log("Bank1 initialized successfully");

        bank2 = new TestBank();  // Use TestBank
        console.log("Bank2 address:", address(bank2));
        console.log("Starting Bank2 initialization...");
        
        bank2.initialize(
            IERC20(address(loanToken)),
            "Bank 2",
            "BANK2",
            untitledHub,
            500, // 5% fee
            feeRecipient,
            MIN_DELAY,
            owner,
            IBank.BankType.Public
        );

        console.log("Bank2 initialized successfully");

        // Mint tokens to users
        loanToken.mint(user1, INITIAL_BALANCE);
        loanToken.mint(user2, INITIAL_BALANCE);
        
        // Approve CoreBank to spend tokens
        vm.prank(user1);
        loanToken.approve(address(coreBank), type(uint256).max);
        vm.prank(user2);
        loanToken.approve(address(coreBank), type(uint256).max);

        // Grant roles
        coreBank.grantRole(coreBank.PROPOSER_ROLE(), owner);
        coreBank.grantRole(coreBank.EXECUTOR_ROLE(), owner);

        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18
        });
        uint256 marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
        uint256 marketId2 = untitledHub.createMarket{value: 0.01 ether}(configs);

        // Schedule market addition
        bank1.scheduleAddMarket(marketId, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank1.executeAddMarket(marketId);

        bank1.scheduleAddMarket(marketId2, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank1.executeAddMarket(marketId2);

        bank2.scheduleAddMarket(marketId, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank2.executeAddMarket(marketId);

        // market allocation update
        IBank.MarketAllocation[] memory newAllocations = new IBank.MarketAllocation[](2);
        newAllocations[0] = IBank.MarketAllocation({
            id: marketId,
            allocation: 6000
        });
        newAllocations[1] = IBank.MarketAllocation({
            id: marketId2,
            allocation: 4000
        });
        bank1.scheduleUpdateAllocations(newAllocations, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bank1.executeUpdateAllocations(newAllocations);
    }

    function testInitialState() public {
        assertEq(address(coreBank.asset()), address(loanToken));
        assertEq(coreBank.name(), "Core Bank");
        assertEq(coreBank.symbol(), "cBANK");
    }

    function testAddBank() public {
        uint256 timestamp = block.timestamp;
        
        // Schedule bank addition
        coreBank.scheduleAddBank(address(bank1), MIN_DELAY);
        
        // Warp time and execute
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        vm.expectEmit(true, true, true, true);
        emit BankAdded(address(bank1));
        coreBank.executeAddBank(address(bank1));

        // Verify bank was added
        ICoreBank.BankAllocation[] memory allocations = coreBank.getBankAllocations();
        assertEq(allocations.length, 1);
        assertEq(address(allocations[0].bank), address(bank1));
        assertTrue(coreBank.isBankEnabled(address(bank1)));
    }

    function testDeposit() public {
        uint256 timestamp = block.timestamp;
        
        // Deploy new CoreBank with initialize
        TestCoreBank newCoreBank = new TestCoreBank();
        newCoreBank.initialize(
            IERC20(address(loanToken)),
            "Core Bank",
            "cBANK",
            MIN_DELAY,
            owner
        );

        // Add bank first
        newCoreBank.scheduleAddBank(address(bank1), MIN_DELAY); // 100% allocation
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        newCoreBank.executeAddBank(address(bank1));

        // Test deposit
        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        loanToken.approve(address(newCoreBank), depositAmount);
        newCoreBank.deposit(depositAmount, user1);
        vm.stopPrank();

        // Verify deposit
        assertEq(newCoreBank.balanceOf(user1), depositAmount);
        assertEq(newCoreBank.totalAssets(), depositAmount);
        
        // Verify funds were transferred to bank1
        assertEq(bank1.balanceOf(address(newCoreBank)), depositAmount);
    }

    function testWithdraw() public {
        uint256 timestamp = block.timestamp;
        
        // Add bank and deposit first
        coreBank.scheduleAddBank(address(bank1), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeAddBank(address(bank1));

        uint256 depositAmount = 100e18;
        vm.startPrank(user1);
        coreBank.deposit(depositAmount, user1);
        
        // Test withdraw
        uint256 withdrawAmount = 50e18;
        coreBank.withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();

        // Verify withdraw
        assertEq(coreBank.balanceOf(user1), depositAmount - withdrawAmount);
        assertEq(coreBank.totalAssets(), depositAmount - withdrawAmount);
        assertEq(bank1.balanceOf(address(coreBank)), depositAmount - withdrawAmount);
    }

    function testRemoveBank() public {
        uint256 timestamp = block.timestamp;
        
        // Add bank first
        coreBank.scheduleAddBank(address(bank1), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeAddBank(address(bank1));

        // Schedule bank removal
        coreBank.scheduleRemoveBank(address(bank1), MIN_DELAY);
        
        // Warp time and execute
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        vm.expectEmit(true, true, true, true);
        emit BankRemoved(address(bank1));
        coreBank.executeRemoveBank(address(bank1));

        // Verify bank was removed
        ICoreBank.BankAllocation[] memory allocations = coreBank.getBankAllocations();
        assertEq(allocations.length, 0);
        assertFalse(coreBank.isBankEnabled(address(bank1)));
    }

    function testCancelOperations() public {
        uint256 timestamp = block.timestamp;
        
        // Test cancel bank addition
        coreBank.scheduleAddBank(address(bank1), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        bytes32 addBankOpId = keccak256(abi.encode(
            "addBank",
            address(bank1)
        ));
        vm.expectEmit(true, true, true, true);
        emit BankAdditionCancelled(address(bank1), addBankOpId);
        coreBank.cancelAddBank(address(bank1));
        
        // Test cancel bank removal
        coreBank.scheduleAddBank(address(bank1), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeAddBank(address(bank1));
        
        coreBank.scheduleRemoveBank(address(bank1), MIN_DELAY);
        bytes32 removeBankOpId = keccak256(abi.encode(
            "removeBank",
            address(bank1)
        ));
        vm.expectEmit(true, true, true, true);
        emit BankRemovalCancelled(address(bank1), removeBankOpId);
        coreBank.cancelRemoveBank(address(bank1));
        
        // Test cancel allocation update
        // new allocations
        ICoreBank.BankAllocation[] memory newAllocations = new ICoreBank.BankAllocation[](1);
        newAllocations[0] = ICoreBank.BankAllocation({
            bank: IBank(bank1),
            allocation: 10000
        });
        coreBank.scheduleUpdateAllocations(newAllocations, MIN_DELAY);
        bytes32 updateAllocationOpId = keccak256(abi.encode(
            "updateAllocations",
            newAllocations
        ));
        vm.expectEmit(true, true, true, true);
        emit AllocationsUpdateCancelled(newAllocations, updateAllocationOpId);
        coreBank.cancelUpdateAllocations(newAllocations);
    }

    function testMultipleBanks() public {
        uint256 timestamp = block.timestamp;
        
        // Add first bank with 60% allocation
        coreBank.scheduleAddBank(address(bank1), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeAddBank(address(bank1));

        // Add second bank with 40% allocation
        coreBank.scheduleAddBank(address(bank2), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeAddBank(address(bank2));

        // new allocations
        ICoreBank.BankAllocation[] memory newAllocations = new ICoreBank.BankAllocation[](2);
        newAllocations[0] = ICoreBank.BankAllocation({
            bank: IBank(bank1),
            allocation: 6000
        });
        newAllocations[1] = ICoreBank.BankAllocation({
            bank: IBank(bank2),
            allocation: 4000
        });
        coreBank.scheduleUpdateAllocations(newAllocations, MIN_DELAY);
        // Warp time and execute
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeUpdateAllocations(newAllocations);

        // Test deposit distribution
        uint256 depositAmount = 100e18;
        vm.prank(user1);
        coreBank.deposit(depositAmount, user1);

        // Verify deposit distribution
        assertEq(bank1.balanceOf(address(coreBank)), 60e18); // 60%
        assertEq(bank2.balanceOf(address(coreBank)), 40e18); // 40%

        // Test withdrawal from multiple banks
        vm.prank(user1);
        coreBank.withdraw(50e18, user1, user1);

        // Verify proportional withdrawal
        assertEq(bank1.balanceOf(address(coreBank)), 30e18);
        assertEq(bank2.balanceOf(address(coreBank)), 20e18);
    }

    function testUpdateAllocation() public {
        uint256 timestamp = block.timestamp;
        
        // Add bank with initial allocation
        coreBank.scheduleAddBank(address(bank1), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeAddBank(address(bank1));

        // Schedule allocation update
        // new allocations
        ICoreBank.BankAllocation[] memory newAllocations = new ICoreBank.BankAllocation[](1);
        newAllocations[0] = ICoreBank.BankAllocation({
            bank: IBank(bank1),
            allocation: 10000
        });
        coreBank.scheduleUpdateAllocations(newAllocations, MIN_DELAY);
        
        // Warp time and execute
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        vm.expectEmit(true, true, true, true);
        emit AllocationsUpdated(newAllocations);
        coreBank.executeUpdateAllocations(newAllocations);

        // Verify allocation update
        ICoreBank.BankAllocation[] memory allocations = coreBank.getBankAllocations();
        assertEq(allocations[0].allocation, newAllocations[0].allocation);
    }

    function testInvalidBankAddition() public {
        uint256 timestamp = block.timestamp;

        // Deploy invalid bank with initialize
        MockERC20 differentToken = new MockERC20("Different Token", "DIFF");
        TestBank invalidBank = new TestBank();
        invalidBank.initialize(
            IERC20(address(differentToken)),
            "Invalid Bank",
            "INVALID",
            untitledHub,
            500,
            feeRecipient,
            MIN_DELAY,
            owner,
            IBank.BankType.Public
        );

        coreBank.scheduleAddBank(address(invalidBank), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        vm.expectRevert("CoreBank: Bank asset mismatch");
        coreBank.executeAddBank(address(invalidBank));
    }

    function testPrivateBankAddition() public {
        uint256 timestamp = block.timestamp;
        
        // Deploy private bank with initialize
        TestBank privateBank = new TestBank();
        privateBank.initialize(
            IERC20(address(loanToken)),
            "Private Bank",
            "PRIV",
            untitledHub,
            500,
            feeRecipient,
            MIN_DELAY,
            owner,
            IBank.BankType.Private
        );

        // Try to add private bank
        coreBank.scheduleAddBank(address(privateBank), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        vm.expectRevert("CoreBank: Not a Public Bank");
        coreBank.executeAddBank(address(privateBank));
    }

    function testComplexScenario() public {
        uint256 timestamp = block.timestamp;
        
        // Add banks
        coreBank.scheduleAddBank(address(bank1), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeAddBank(address(bank1));

        coreBank.scheduleAddBank(address(bank2), MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeAddBank(address(bank2));

        // Set initial allocations (60% bank1, 40% bank2)
        ICoreBank.BankAllocation[] memory initialAllocations = new ICoreBank.BankAllocation[](2);
        initialAllocations[0] = ICoreBank.BankAllocation({
            bank: IBank(bank1),
            allocation: 6000
        });
        initialAllocations[1] = ICoreBank.BankAllocation({
            bank: IBank(bank2),
            allocation: 4000
        });
        coreBank.scheduleUpdateAllocations(initialAllocations, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeUpdateAllocations(initialAllocations);

        // User1 deposits 1000 tokens
        vm.startPrank(user1);
        uint256 depositAmount = 1000e18;
        coreBank.deposit(depositAmount, user1);
        vm.stopPrank();

        // Verify initial deposit distribution
        assertEq(bank1.balanceOf(address(coreBank)), 600e18); // 60%
        assertEq(bank2.balanceOf(address(coreBank)), 400e18); // 40%

        // User2 deposits 500 tokens
        vm.startPrank(user2);
        coreBank.deposit(500e18, user2);
        vm.stopPrank();

        // Verify total deposits
        assertEq(bank1.balanceOf(address(coreBank)), 900e18); // 60% of 1500
        assertEq(bank2.balanceOf(address(coreBank)), 600e18); // 40% of 1500

        // Update allocations to new ratio (70% bank1, 30% bank2)
        ICoreBank.BankAllocation[] memory newAllocations = new ICoreBank.BankAllocation[](2);
        newAllocations[0] = ICoreBank.BankAllocation({
            bank: IBank(bank1),
            allocation: 7000
        });
        newAllocations[1] = ICoreBank.BankAllocation({
            bank: IBank(bank2),
            allocation: 3000
        });

        // Schedule and execute reallocation
        address[] memory withdrawBanks = new address[](1);
        withdrawBanks[0] = address(bank2);
        uint256[] memory withdrawAmounts = new uint256[](1);
        withdrawAmounts[0] = 150e18; // Withdraw from bank2

        address[] memory depositBanks = new address[](1);
        depositBanks[0] = address(bank1);
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 150e18; // Deposit to bank1

        coreBank.scheduleReallocate(
            withdrawBanks,
            withdrawAmounts,
            depositBanks,
            depositAmounts,
            MIN_DELAY
        );
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeReallocate(
            withdrawBanks,
            withdrawAmounts,
            depositBanks,
            depositAmounts
        );

        // Update allocations
        coreBank.scheduleUpdateAllocations(newAllocations, MIN_DELAY);
        timestamp += MIN_DELAY;
        vm.warp(timestamp);
        coreBank.executeUpdateAllocations(newAllocations);

        // Verify new balances after reallocation
        assertEq(bank1.balanceOf(address(coreBank)), 1050e18); // 70% of 1500
        assertEq(bank2.balanceOf(address(coreBank)), 450e18);  // 30% of 1500

        // User1 withdraws 400 tokens
        vm.startPrank(user1);
        coreBank.withdraw(400e18, user1, user1);
        vm.stopPrank();

        // Verify
    }
}
