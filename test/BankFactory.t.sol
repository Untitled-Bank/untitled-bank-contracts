// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/BankFactory.sol";
import "../src/core/Bank.sol";
import "../src/core/UntitledHub.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Create a TestBank contract that inherits from Bank but doesn't disable initializers
contract TestBank is Bank {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Remove the Bank() call and don't initialize anything in constructor
    }

    function _disableInitializers() internal override {
        // Override to prevent disabling initializers
    }
}

// Create a TestBankFactory contract that inherits from BankFactory but doesn't disable initializers
contract TestBankFactory is BankFactory {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Remove the BankFactory() call and don't initialize anything in constructor
    }

    function _disableInitializers() internal override {
        // Override to prevent disabling initializers
    }
}

contract BankFactoryTest is Test {
    TestBankFactory public factory;
    TestBank public bankImplementation;
    UntitledHub public untitledHub;
    MockERC20 public token;
    
    address public owner;
    address public user1;
    uint32 public constant MIN_DELAY = 1 days;
    uint256 public constant FEE = 500; // 5%

    event BankCreated(address bank, address asset, string name, string symbol);
    event BankImplementationUpdated(address oldImplementation, address newImplementation);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);

        // Deploy mock token
        token = new MockERC20("Test Token", "TEST");

        // Deploy UntitledHub
        untitledHub = new UntitledHub(owner);

        // Deploy TestBank implementation
        bankImplementation = new TestBank();

        // Deploy and initialize TestBankFactory
        factory = new TestBankFactory();
        factory.initialize(address(bankImplementation), address(untitledHub));
    }

    function testInitialState() public {
        assertEq(factory.owner(), owner);
        assertEq(factory.bankImplementation(), address(bankImplementation));
        assertEq(address(factory.untitledHub()), address(untitledHub));
    }

    function testCreatePublicBank() public {
        string memory name = "Test Bank";
        string memory symbol = "tBANK";

        // Compute the expected proxy address
        address predictedAddress = computeCreateAddress(
            address(factory),
            vm.getNonce(address(factory))
        );

        // Expect the BankCreated event with the predicted address
        vm.expectEmit(true, true, true, true);
        emit BankCreated(predictedAddress, address(token), name, symbol);

        address bankAddress = factory.createBank(
            IERC20(address(token)),
            name,
            symbol,
            FEE,
            user1, // fee recipient
            MIN_DELAY,
            owner,
            IBank.BankType.Public
        );

        assertTrue(factory.isBank(bankAddress));
        assertEq(factory.getBankCount(), 1);
        assertEq(factory.getBankAt(0), bankAddress);
        assertTrue(factory.isBankCreatedByFactory(bankAddress));

        Bank bank = Bank(bankAddress);
        assertEq(address(bank.asset()), address(token));
        assertEq(bank.name(), name);
        assertEq(bank.symbol(), symbol);
        assertEq(bank.getFee(), FEE);
        assertEq(bank.getFeeRecipient(), user1);
        assertEq(uint8(bank.getBankType()), uint8(IBank.BankType.Public));
    }

    function testCreatePrivateBank() public {
        string memory name = "Private Bank";
        string memory symbol = "pBANK";

        address bankAddress = factory.createBank(
            IERC20(address(token)),
            name,
            symbol,
            FEE,
            user1, // fee recipient
            MIN_DELAY,
            owner,
            IBank.BankType.Private
        );

        Bank bank = Bank(bankAddress);
        assertEq(uint8(bank.getBankType()), uint8(IBank.BankType.Private));
    }

    function testUpdateBankImplementation() public {
        // Deploy new implementation using TestBank
        TestBank newImplementation = new TestBank();

        vm.expectEmit(true, true, true, true);
        emit BankImplementationUpdated(address(bankImplementation), address(newImplementation));

        factory.updateBankImplementation(address(newImplementation));
        assertEq(factory.bankImplementation(), address(newImplementation));
    }

    function testFailUpdateImplementationNonOwner() public {
        TestBank newImplementation = new TestBank();
        
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.updateBankImplementation(address(newImplementation));
    }

    function testFailGetBankAtInvalidIndex() public view {
        factory.getBankAt(999);
    }

    function testCreateMultipleBanks() public {
        uint256 numBanks = 3;
        address[] memory bankAddresses = new address[](numBanks);

        for (uint256 i = 0; i < numBanks; i++) {
            string memory name = string(abi.encodePacked("Bank ", vm.toString(i)));
            string memory symbol = string(abi.encodePacked("BANK", vm.toString(i)));

            bankAddresses[i] = factory.createBank(
                IERC20(address(token)),
                name,
                symbol,
                FEE,
                user1,
                MIN_DELAY,
                owner,
                IBank.BankType.Public
            );
        }

        assertEq(factory.getBankCount(), numBanks);

        for (uint256 i = 0; i < numBanks; i++) {
            assertEq(factory.getBankAt(i), bankAddresses[i]);
            assertTrue(factory.isBank(bankAddresses[i]));
        }
    }

    function testFailCreateBankWithInvalidFee() public {
        factory.createBank(
            IERC20(address(token)),
            "Test Bank",
            "tBANK",
            1001, // fee > 10%
            user1,
            MIN_DELAY,
            owner,
            IBank.BankType.Public
        );
    }
}
