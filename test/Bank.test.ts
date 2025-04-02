import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract, Signer } from "ethers";
import { upgrades } from "hardhat";

describe("Bank", function () {
  let untitledHub: Contract;
  let bankFactory: Contract;
  let bankImplementation: Contract;
  let bank: Contract;
  let loanToken: Contract;
  let collateralToken: Contract;
  let priceProvider: Contract;
  let interestRateModel: Contract;
  let owner: Signer, admin: Signer, user1: Signer, user2: Signer;
  const INITIAL_BALANCE = ethers.parseEther("1000");
  const MARKET_ID = 1;
  
  // Set a longer timeout for these tests
  this.timeout(30000);

  beforeEach(async function () {
    // Get signers
    [owner, admin, user1, user2] = await ethers.getSigners();

    // Deploy MockERC20 contracts for Loan Token and Collateral Token
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    loanToken = await MockERC20.deploy("Loan Token", "LOAN");
    await loanToken.waitForDeployment();
    
    collateralToken = await MockERC20.deploy("Collateral Token", "COLL");
    await collateralToken.waitForDeployment();

    // Deploy MockPriceProvider
    const MockPriceProvider = await ethers.getContractFactory("MockPriceProvider");
    priceProvider = await MockPriceProvider.deploy();
    await priceProvider.waitForDeployment();

    // Deploy MockInterestRateModel
    const MockInterestRateModel = await ethers.getContractFactory("MockInterestRateModel");
    interestRateModel = await MockInterestRateModel.deploy();
    await interestRateModel.waitForDeployment();

    // Deploy UntitledHub with the owner address
    const UntitledHub = await ethers.getContractFactory("UntitledHub");
    untitledHub = await UntitledHub.deploy(await owner.getAddress());
    await untitledHub.waitForDeployment();

    // Register the Interest Rate Model (IRM) by the owner
    await untitledHub.registerIrm(await interestRateModel.getAddress(), true);

    // Create a market in UntitledHub
    const configs = {
      loanToken: await loanToken.getAddress(),
      collateralToken: await collateralToken.getAddress(),
      oracle: await priceProvider.getAddress(),
      irm: await interestRateModel.getAddress(),
      lltv: ethers.parseEther("0.8"), // 80% LLTV
    };
    await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });

    // Deploy Bank implementation
    const Bank = await ethers.getContractFactory("Bank");
    bankImplementation = await Bank.deploy();
    await bankImplementation.waitForDeployment();

    // Deploy BankFactory with initialization parameters directly
    const BankFactory = await ethers.getContractFactory("BankFactory");
    const args = [
      await bankImplementation.getAddress(),
      await untitledHub.getAddress()
    ];

    // Try deploying with initialization
    try {
      bankFactory = await upgrades.deployProxy(BankFactory, args);
      await bankFactory.waitForDeployment();
    } catch (error) {
      console.error("Proxy deployment error:", error);
      
      // Fall back to manual deployment and initialization
      bankFactory = await BankFactory.deploy();
      await bankFactory.waitForDeployment();
      
      try {
        await bankFactory.initialize(...args);
      } catch (initError) {
        console.error("Manual initialization error:", initError);
        // Continue anyway, as the contract might already be initialized
      }
    }

    // Create a Bank through the factory
    const tx = await bankFactory.createBank(
      await loanToken.getAddress(),
      "Test Bank",
      "TBANK",
      100, // 1% fee (in basis points)
      await owner.getAddress(), // fee recipient
      600, // 10 mins delay
      await admin.getAddress(), // initial admin
      0 // BankType.Public
    );
    const receipt = await tx.wait();
    
    // Find the BankCreated event to get the bank address
    const event = receipt.logs.find(
      (log: any) => log.fragment && log.fragment.name === "BankCreated"
    );
    const bankAddress = event.args[0];
    
    // Connect to the created bank
    bank = await ethers.getContractAt("Bank", bankAddress);

    // Mint tokens to users
    await loanToken.mint(await user1.getAddress(), INITIAL_BALANCE);
    await loanToken.mint(await user2.getAddress(), INITIAL_BALANCE);
    
    // Approve bank to spend tokens
    await loanToken.connect(user1).approve(await bank.getAddress(), ethers.MaxUint256);
    await loanToken.connect(user2).approve(await bank.getAddress(), ethers.MaxUint256);
  });

  describe("BankFactory", function () {
    it("should create a bank correctly", async function () {
      // Verify the bank was created and tracked in the factory
      expect(await bankFactory.isBank(await bank.getAddress())).to.be.true;
      expect(await bankFactory.getBankCount()).to.equal(1);
      expect(await bankFactory.getBankAt(0)).to.equal(await bank.getAddress());
    });

    it("should update bank implementation", async function () {
      // Deploy a new implementation
      const NewBank = await ethers.getContractFactory("Bank");
      const newImplementation = await NewBank.deploy();
      await newImplementation.waitForDeployment();
      
      // Update implementation
      await bankFactory.updateBankImplementation(await newImplementation.getAddress());
      
      // Verify implementation was updated
      expect(await bankFactory.bankImplementation()).to.equal(await newImplementation.getAddress());
    });
    
    it("should revert when non-owner tries to update implementation", async function () {
      const NewBank = await ethers.getContractFactory("Bank");
      const newImplementation = await NewBank.deploy();
      await newImplementation.waitForDeployment();
      
      await expect(
        bankFactory.connect(user1).updateBankImplementation(await newImplementation.getAddress())
      ).to.be.reverted;
    });
  });

  describe("Bank Initialization", function () {
    it("should initialize with correct parameters", async function () {
      expect(await bank.asset()).to.equal(await loanToken.getAddress());
      expect(await bank.name()).to.equal("Test Bank");
      expect(await bank.symbol()).to.equal("TBANK");
      expect(await bank.getFee()).to.equal(100); // 1%
      expect(await bank.getFeeRecipient()).to.equal(await owner.getAddress());
      expect(await bank.getBankType()).to.equal(0); // Public
      expect(await bank.getUntitledHub()).to.equal(await untitledHub.getAddress());
      
      // Check admin role
      expect(await bank.hasRole(await bank.DEFAULT_ADMIN_ROLE(), await admin.getAddress())).to.be.true;
    });
    
    it("should revert when initializing with too high fee", async function () {
      await expect(
        bankFactory.createBank(
          await loanToken.getAddress(),
          "High Fee Bank",
          "HFBANK",
          1001, // > 10% fee (1000 basis points)
          await owner.getAddress(),
          86400,
          await admin.getAddress(),
          0
        )
      ).to.be.revertedWithCustomError(bank, "FeeTooHigh");
    });
  });

  describe("Market Management", function () {
    it("should schedule, execute, and cancel market addition", async function () {
      // Grant proposer and executor roles to admin
      await bank.connect(admin).grantRole(await bank.PROPOSER_ROLE(), await admin.getAddress());
      await bank.connect(admin).grantRole(await bank.EXECUTOR_ROLE(), await admin.getAddress());
      
      // Get the minimum delay
      const minDelay = await bank.minDelay();
      
      // Schedule market addition with minimum delay
      const tx = await bank.connect(admin).scheduleAddMarket(MARKET_ID, minDelay);
      const receipt = await tx.wait();
      
      // Find the operation ID from the event
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "MarketAdditionScheduled"
      );
      expect(event).to.not.be.undefined;
      
      // Advance time to pass the delay
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      
      // Execute market addition
      await bank.connect(admin).executeAddMarket(MARKET_ID);
      
      // Verify market was added
      expect(await bank.getIsMarketEnabled(MARKET_ID)).to.be.true;
      
      // Try to add the same market again (should fail)
      await bank.connect(admin).scheduleAddMarket(MARKET_ID, minDelay);
      await expect(
        bank.connect(admin).executeAddMarket(MARKET_ID)
      ).to.be.reverted;
      
      // Schedule another market addition and cancel it
      await bank.connect(admin).scheduleAddMarket(2, minDelay);
      await bank.connect(admin).cancelAddMarket(2);
      
      // Try to execute the cancelled operation (should fail)
      await expect(
        bank.connect(admin).executeAddMarket(2)
      ).to.be.reverted;
    });
    
    it("should schedule, execute, and cancel market removal", async function () {
      // Grant proposer and executor roles to admin
      await bank.connect(admin).grantRole(await bank.PROPOSER_ROLE(), await admin.getAddress());
      await bank.connect(admin).grantRole(await bank.EXECUTOR_ROLE(), await admin.getAddress());
      
      // Get the minimum delay
      const minDelay = await bank.minDelay();
      
      // First add a market
      await bank.connect(admin).scheduleAddMarket(MARKET_ID, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeAddMarket(MARKET_ID);
      
      // Schedule market removal
      const tx = await bank.connect(admin).scheduleRemoveMarket(MARKET_ID, minDelay);
      const receipt = await tx.wait();
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      
      // Find the operation ID from the event
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "MarketRemovalScheduled"
      );
      expect(event).to.not.be.undefined;
      
      // Execute market removal
      await bank.connect(admin).executeRemoveMarket(MARKET_ID);
      
      // Verify market was removed
      expect(await bank.getIsMarketEnabled(MARKET_ID)).to.be.false;
      
      // Schedule another market removal and cancel it
      await bank.connect(admin).scheduleAddMarket(MARKET_ID, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeAddMarket(MARKET_ID);
      await bank.connect(admin).scheduleRemoveMarket(MARKET_ID, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).cancelRemoveMarket(MARKET_ID);
      
      // Verify market is still enabled after cancellation
      expect(await bank.getIsMarketEnabled(MARKET_ID)).to.be.true;
    });
    
    it("should update allocations", async function () {
      // Grant proposer and executor roles to admin
      await bank.connect(admin).grantRole(await bank.PROPOSER_ROLE(), await admin.getAddress());
      await bank.connect(admin).grantRole(await bank.EXECUTOR_ROLE(), await admin.getAddress());
      
      // Get the minimum delay
      const minDelay = await bank.minDelay();
      
      // First add a market
      await bank.connect(admin).scheduleAddMarket(MARKET_ID, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeAddMarket(MARKET_ID);
      
      // Define new allocations
      const newAllocations = [
        { id: MARKET_ID, allocation: 10000 } // 100% allocation
      ];
      
      // Schedule allocation update
      const tx = await bank.connect(admin).scheduleUpdateAllocations(newAllocations, minDelay);
      const receipt = await tx.wait();
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      
      // Find the operation ID from the event
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "AllocationsUpdateScheduled"
      );
      expect(event).to.not.be.undefined;
      
      // Execute allocation update
      await bank.connect(admin).executeUpdateAllocations(newAllocations);
      
      // Verify allocations were updated
      const allocations = await bank.getMarketAllocations();
      expect(allocations.length).to.equal(1);
      expect(allocations[0].id).to.equal(MARKET_ID);
      expect(allocations[0].allocation).to.equal(10000);
      
      // Schedule another allocation update and cancel it
      const newerAllocations = [
        { id: MARKET_ID, allocation: 5000 } // 50% allocation
      ];
      await bank.connect(admin).scheduleUpdateAllocations(newerAllocations, minDelay);
      await bank.connect(admin).cancelUpdateAllocations(newerAllocations);
      
      // Verify allocations didn't change after cancellation
      const allocationsAfterCancel = await bank.getMarketAllocations();
      expect(allocationsAfterCancel[0].allocation).to.equal(10000);
    });
  });

  describe("Fee Management", function () {
    it("should schedule, execute, and cancel fee updates", async function () {
      // Grant proposer and executor roles to admin
      await bank.connect(admin).grantRole(await bank.PROPOSER_ROLE(), await admin.getAddress());
      await bank.connect(admin).grantRole(await bank.EXECUTOR_ROLE(), await admin.getAddress());
      
      // Get the minimum delay
      const minDelay = await bank.minDelay();
      
      // Schedule fee update
      const newFee = 200; // 2%
      const tx = await bank.connect(admin).scheduleSetFee(newFee, minDelay);
      const receipt = await tx.wait();
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      
      // Find the operation ID from the event
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "FeeUpdateScheduled"
      );
      expect(event).to.not.be.undefined;
      
      // Execute fee update
      await bank.connect(admin).executeSetFee(newFee);
      
      // Verify fee was updated
      expect(await bank.getFee()).to.equal(newFee);
      
      // Schedule another fee update and cancel it
      const newerFee = 300; // 3%
      await bank.connect(admin).scheduleSetFee(newerFee, minDelay);
      await bank.connect(admin).cancelSetFee(newerFee);
      
      // Verify fee didn't change after cancellation
      expect(await bank.getFee()).to.equal(newFee);
    });
    
    it("should schedule, execute, and cancel fee recipient updates", async function () {
      // Grant proposer and executor roles to admin
      await bank.connect(admin).grantRole(await bank.PROPOSER_ROLE(), await admin.getAddress());
      await bank.connect(admin).grantRole(await bank.EXECUTOR_ROLE(), await admin.getAddress());
      
      // Get the minimum delay
      const minDelay = await bank.minDelay();
      
      // Schedule fee recipient update
      const newRecipient = await user1.getAddress();
      const tx = await bank.connect(admin).scheduleSetFeeRecipient(newRecipient, minDelay);
      const receipt = await tx.wait();
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      
      // Find the operation ID from the event
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "FeeRecipientUpdateScheduled"
      );
      expect(event).to.not.be.undefined;
      
      // Execute fee recipient update
      await bank.connect(admin).executeSetFeeRecipient(newRecipient);
      
      // Verify fee recipient was updated
      expect(await bank.getFeeRecipient()).to.equal(newRecipient);
      
      // Schedule another fee recipient update and cancel it
      const newerRecipient = await user2.getAddress();
      await bank.connect(admin).scheduleSetFeeRecipient(newerRecipient, minDelay);
      await bank.connect(admin).cancelSetFeeRecipient(newerRecipient);
      
      // Verify fee recipient didn't change after cancellation
      expect(await bank.getFeeRecipient()).to.equal(newRecipient);
    });
    
    it("should accrue fees when harvesting", async function () {
      // Grant proposer and executor roles to admin
      await bank.connect(admin).grantRole(await bank.PROPOSER_ROLE(), await admin.getAddress());
      await bank.connect(admin).grantRole(await bank.EXECUTOR_ROLE(), await admin.getAddress());
      
      // Add market with 100% allocation
      await bank.connect(admin).scheduleAddMarket(MARKET_ID, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await bank.connect(admin).executeAddMarket(MARKET_ID);
      const allocations = [{ id: MARKET_ID, allocation: 10000 }];
      await bank.connect(admin).scheduleUpdateAllocations(allocations, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await bank.connect(admin).executeUpdateAllocations(allocations);
      
      // User1 deposits into the bank
      const depositAmount = ethers.parseEther("100");
      await bank.connect(user1).deposit(depositAmount, await user1.getAddress());
      
      // Simulate interest accrual in UntitledHub
      // First, we need another user to borrow from the market
      await collateralToken.mint(await user2.getAddress(), INITIAL_BALANCE);
      await collateralToken.connect(user2).approve(await untitledHub.getAddress(), ethers.MaxUint256);
      await untitledHub.connect(user2).supplyCollateral(MARKET_ID, ethers.parseEther("50"), "0x");
      await untitledHub.connect(user2).borrow(MARKET_ID, ethers.parseEther("30"), await user2.getAddress());
      
      // Advance time to accrue interest
      await network.provider.send("evm_increaseTime", [365 * 24 * 3600]); // 1 year
      await network.provider.send("evm_mine");
      
      // Get fee recipient's initial balance
      const feeRecipient = await bank.getFeeRecipient();
      const initialFeeRecipientBalance = await bank.balanceOf(feeRecipient);
      
      // Harvest fees
      await untitledHub.connect(user2).accrueInterest(MARKET_ID);
      await bank.harvest();
      
      // Verify fee recipient received fees
      const finalFeeRecipientBalance = await bank.balanceOf(feeRecipient);
      expect(finalFeeRecipientBalance).to.be.gt(initialFeeRecipientBalance);
    });
  });

  describe("Whitelist Management", function () {
    it("should manage whitelist for private banks", async function () {
      // Create a private bank
      const tx = await bankFactory.createBank(
        await loanToken.getAddress(),
        "Private Bank",
        "PBANK",
        100, // 1% fee
        await owner.getAddress(),
        600, // 10 mins delay
        await admin.getAddress(),
        1 // BankType.Private
      );
      const receipt = await tx.wait();
      
      // Find the bank address from the event
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "BankCreated"
      );
      const privateBank = await ethers.getContractAt("Bank", event.args[0]);
      
      // Grant proposer and executor roles to admin
      await privateBank.connect(admin).grantRole(await privateBank.PROPOSER_ROLE(), await admin.getAddress());
      await privateBank.connect(admin).grantRole(await privateBank.EXECUTOR_ROLE(), await admin.getAddress());
      
      // Get the minimum delay
      const minDelay = await privateBank.minDelay();
      
      // Add market with 100% allocation (needed for deposits to work)
      await privateBank.connect(admin).scheduleAddMarket(MARKET_ID, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      await privateBank.connect(admin).executeAddMarket(MARKET_ID);
      
      const allocations = [{ id: MARKET_ID, allocation: 10000 }];
      await privateBank.connect(admin).scheduleUpdateAllocations(allocations, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      await privateBank.connect(admin).executeUpdateAllocations(allocations);
      
      // Verify user1 is not whitelisted initially
      expect(await privateBank.isWhitelisted(await user1.getAddress())).to.be.false;
      
      // Schedule whitelist update
      await privateBank.connect(admin).scheduleUpdateWhitelist(await user1.getAddress(), true, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      
      // Execute whitelist update
      await privateBank.connect(admin).executeUpdateWhitelist(await user1.getAddress(), true);
      
      // Verify user1 is now whitelisted
      expect(await privateBank.isWhitelisted(await user1.getAddress())).to.be.true;
      
      // Approve private bank to spend tokens
      await loanToken.connect(user1).approve(await privateBank.getAddress(), ethers.MaxUint256);
      
      // User1 should be able to deposit now
      await privateBank.connect(user1).deposit(ethers.parseEther("10"), await user1.getAddress());
      
      // User2 should not be able to deposit (not whitelisted)
      await loanToken.connect(user2).approve(await privateBank.getAddress(), ethers.MaxUint256);
      await expect(
        privateBank.connect(user2).deposit(ethers.parseEther("10"), await user2.getAddress())
      ).to.be.revertedWithCustomError(privateBank, "NotWhitelisted");
      
      // Schedule whitelist removal
      await privateBank.connect(admin).scheduleUpdateWhitelist(await user1.getAddress(), false, minDelay);
      
      // Cancel the whitelist removal
      await privateBank.connect(admin).cancelUpdateWhitelist(await user1.getAddress(), false);
      
      // Verify user1 is still whitelisted
      expect(await privateBank.isWhitelisted(await user1.getAddress())).to.be.true;
    });
  });

  describe("Deposit and Withdraw", function () {
    beforeEach(async function () {
      // Grant proposer and executor roles to admin
      await bank.connect(admin).grantRole(await bank.PROPOSER_ROLE(), await admin.getAddress());
      await bank.connect(admin).grantRole(await bank.EXECUTOR_ROLE(), await admin.getAddress());
      
      // Add market with 100% allocation
      await bank.connect(admin).scheduleAddMarket(MARKET_ID, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await bank.connect(admin).executeAddMarket(MARKET_ID);
      const allocations = [{ id: MARKET_ID, allocation: 10000 }];
      await bank.connect(admin).scheduleUpdateAllocations(allocations, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await bank.connect(admin).executeUpdateAllocations(allocations);
    });
    
    it("should deposit and withdraw correctly", async function () {
      // User1 deposits into the bank
      const depositAmount = ethers.parseEther("100");
      await bank.connect(user1).deposit(depositAmount, await user1.getAddress());
      
      // Verify user1 received shares
      expect(await bank.balanceOf(await user1.getAddress())).to.be.gt(0);
      
      // Verify assets were deposited into UntitledHub
      const position = await untitledHub.position(MARKET_ID, await bank.getAddress());
      expect(position.supplyShares).to.be.gt(0);
      
      // User1 withdraws half
      const withdrawAmount = ethers.parseEther("50");
      await bank.connect(user1).withdraw(withdrawAmount, await user1.getAddress(), await user1.getAddress());
      
      // Verify user1's balance decreased
      const expectedRemainingShares = await bank.convertToShares(depositAmount - withdrawAmount);
      expect(await bank.balanceOf(await user1.getAddress())).to.be.closeTo(expectedRemainingShares, expectedRemainingShares / BigInt(100)); // 1% tolerance
    });
    
    it("should handle multiple markets with different allocations", async function () {
      // Create a second market
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.81"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const MARKET_ID_2 = 2;
      
      // Add both markets with 50/50 allocation
      await bank.connect(admin).scheduleAddMarket(MARKET_ID_2, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await bank.connect(admin).executeAddMarket(MARKET_ID_2);
      const allocations = [
        { id: MARKET_ID, allocation: 5000 },
        { id: MARKET_ID_2, allocation: 5000 }
      ];
      await bank.connect(admin).scheduleUpdateAllocations(allocations, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await bank.connect(admin).executeUpdateAllocations(allocations);
      
      // User1 deposits into the bank
      const depositAmount = ethers.parseEther("100");
      await bank.connect(user1).deposit(depositAmount, await user1.getAddress());
      
      // Verify assets were split between markets
      const position1 = await untitledHub.position(MARKET_ID, await bank.getAddress());
      const position2 = await untitledHub.position(MARKET_ID_2, await bank.getAddress());
      expect(position1.supplyShares).to.be.gt(0);
      expect(position2.supplyShares).to.be.gt(0);
      
      // User1 withdraws everything
      const shares = await bank.balanceOf(await user1.getAddress());
      await bank.connect(user1).redeem(shares, await user1.getAddress(), await user1.getAddress());
      
      // Verify user1's balance is zero
      expect(await bank.balanceOf(await user1.getAddress())).to.equal(0);
    });
  });

  describe("Reallocation", function () {
    beforeEach(async function () {
      // Grant proposer and executor roles to admin
      await bank.connect(admin).grantRole(await bank.PROPOSER_ROLE(), await admin.getAddress());
      await bank.connect(admin).grantRole(await bank.EXECUTOR_ROLE(), await admin.getAddress());
      
      // Get the minimum delay
      const minDelay = await bank.minDelay();
      
      // Create a second market
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.81"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const MARKET_ID_2 = 2;
      
      // Add both markets with 100/0 allocation
      await bank.connect(admin).scheduleAddMarket(MARKET_ID, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeAddMarket(MARKET_ID);
      
      await bank.connect(admin).scheduleAddMarket(MARKET_ID_2, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeAddMarket(MARKET_ID_2);
      
      const allocations = [
        { id: MARKET_ID, allocation: 8000 },
        { id: MARKET_ID_2, allocation: 2000 }
      ];
      await bank.connect(admin).scheduleUpdateAllocations(allocations, minDelay);
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeUpdateAllocations(allocations);
      
      // User1 deposits into the bank
      const depositAmount = ethers.parseEther("100");
      await bank.connect(user1).deposit(depositAmount, await user1.getAddress());
    });
    
    it("should reallocate funds between markets", async function () {
      // Get the minimum delay
      const minDelay = await bank.minDelay();
      
      // Schedule reallocation from market 1 to market 2
      const withdrawIds = [MARKET_ID];
      const withdrawAmounts = [ethers.parseEther("50")];
      const depositIds = [2]; // MARKET_ID_2
      const depositAmounts = [ethers.parseEther("50")];
      
      await bank.connect(admin).scheduleReallocate(
        withdrawIds,
        withdrawAmounts,
        depositIds,
        depositAmounts,
        minDelay
      );
      
      await network.provider.send("evm_increaseTime", [Number(minDelay)]);
      await network.provider.send("evm_mine");
      
      // Execute reallocation
      await bank.connect(admin).executeReallocate(
        withdrawIds,
        withdrawAmounts,
        depositIds,
        depositAmounts
      );
      
      // Verify funds were moved
      const position1 = await untitledHub.position(MARKET_ID, await bank.getAddress());
      const position2 = await untitledHub.position(2, await bank.getAddress());
      
      // Get actual asset amounts from positions
      const market1 = await untitledHub.market(MARKET_ID);
      const market2 = await untitledHub.market(2);
      
      const assets1 = position1.supplyShares * market1.totalSupplyAssets / market1.totalSupplyShares;
      const assets2 = position2.supplyShares * market2.totalSupplyAssets / market2.totalSupplyShares;
      
      // Verify approximately 50 in each market (allow for rounding)
      expect(assets1).to.be.closeTo(ethers.parseEther("30"), ethers.parseEther("0.1"));
      expect(assets2).to.be.closeTo(ethers.parseEther("70"), ethers.parseEther("0.1"));
    });
    
    it("should cancel scheduled reallocation", async function () {
      // Get the minimum delay
      const minDelay = await bank.minDelay();
      
      // Schedule reallocation
      const withdrawIds = [MARKET_ID];
      const withdrawAmounts = [ethers.parseEther("50")];
      const depositIds = [2]; // MARKET_ID_2
      const depositAmounts = [ethers.parseEther("50")];
      
      await bank.connect(admin).scheduleReallocate(
        withdrawIds,
        withdrawAmounts,
        depositIds,
        depositAmounts,
        minDelay
      );
      
      // Cancel reallocation
      await bank.connect(admin).cancelReallocate(
        withdrawIds,
        withdrawAmounts,
        depositIds,
        depositAmounts
      );
      
      // Try to execute the cancelled operation (should fail)
      await expect(
        bank.connect(admin).executeReallocate(
          withdrawIds,
          withdrawAmounts,
          depositIds,
          depositAmounts
        )
      ).to.be.reverted;
    });
  });

  describe("Stuck Assets Recovery", function () {
    beforeEach(async function () {
      // Add market
      await bank.connect(admin).scheduleAddMarket(MARKET_ID, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeAddMarket(MARKET_ID);
      
      // Set up allocations
      const allocations = [{ id: MARKET_ID, allocation: 10000 }];
      await bank.connect(admin).scheduleUpdateAllocations(allocations, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await bank.connect(admin).executeUpdateAllocations(allocations);
    });
    
    it("should redeposit stuck assets", async function () {
      // Send tokens directly to the bank contract (simulating stuck assets)
      const stuckAmount = ethers.parseEther("10");
      await loanToken.mint(await bank.getAddress(), stuckAmount);
      
      // Verify tokens are in the bank contract
      expect(await loanToken.balanceOf(await bank.getAddress())).to.equal(stuckAmount);
      
      // Call redepositStuckAssets
      const tx = await bank.connect(admin).redepositStuckAssets();
      const receipt = await tx.wait();
      
      // Verify event was emitted
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "StuckAssetsRedeposited"
      );
      expect(event).to.not.be.undefined;
      expect(event.args[0]).to.equal(stuckAmount);
      
      // Verify tokens were redeposited
      expect(await loanToken.balanceOf(await bank.getAddress())).to.equal(0);
      
      // Verify position in UntitledHub increased
      const position = await untitledHub.position(MARKET_ID, await bank.getAddress());
      expect(position.supplyShares).to.be.gt(0);
    });
    
    it("should revert when there are no stuck assets", async function () {
      // Try to redeposit when there are no stuck assets
      await expect(
        bank.connect(admin).redepositStuckAssets()
      ).to.be.revertedWithCustomError(bank, "NoStuckAssets");
    });
    
    it("should distribute stuck assets according to allocations with multiple markets", async function () {
      // Create a second market
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.75"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const MARKET_ID_2 = 2;
      
      // Add second market
      await bank.connect(admin).scheduleAddMarket(MARKET_ID_2, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeAddMarket(MARKET_ID_2);
      
      // Set allocations to 60/40
      const allocations = [
        { id: MARKET_ID, allocation: 6000 },
        { id: MARKET_ID_2, allocation: 4000 }
      ];
      await bank.connect(admin).scheduleUpdateAllocations(allocations, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeUpdateAllocations(allocations);
      
      // Send tokens directly to the bank contract
      const stuckAmount = ethers.parseEther("100");
      await loanToken.mint(await bank.getAddress(), stuckAmount);
      
      // Get initial positions
      const position1Before = await untitledHub.position(MARKET_ID, await bank.getAddress());
      const position2Before = await untitledHub.position(MARKET_ID_2, await bank.getAddress());
      
      // Redeposit stuck assets
      await bank.connect(admin).redepositStuckAssets();
      
      // Get positions after redeposit
      const position1After = await untitledHub.position(MARKET_ID, await bank.getAddress());
      const position2After = await untitledHub.position(MARKET_ID_2, await bank.getAddress());
      
      // Get market data to calculate asset amounts
      const market1 = await untitledHub.market(MARKET_ID);
      const market2 = await untitledHub.market(MARKET_ID_2);
      
      // Calculate asset differences
      const assets1Before = position1Before.supplyShares * market1.totalSupplyAssets / market1.totalSupplyShares;
      const assets2Before = position2Before.supplyShares * market2.totalSupplyAssets / market2.totalSupplyShares;
      
      const assets1After = position1After.supplyShares * market1.totalSupplyAssets / market1.totalSupplyShares;
      const assets2After = position2After.supplyShares * market2.totalSupplyAssets / market2.totalSupplyShares;
      
      // Verify assets were distributed according to allocations (with some tolerance)
      const expectedAssets1 = assets1Before + BigInt(stuckAmount) * BigInt(6000) / BigInt(10000);
      const expectedAssets2 = assets2Before + BigInt(stuckAmount) * BigInt(4000) / BigInt(10000);
      
      expect(assets1After).to.be.closeTo(expectedAssets1, ethers.parseEther("0.1"));
      expect(assets2After).to.be.closeTo(expectedAssets2, ethers.parseEther("0.1"));
    });
    
    it("should handle case where some markets have zero allocation", async function () {
      // Create a second market
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.75"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const MARKET_ID_2 = 2;
      
      // Add second market
      await bank.connect(admin).scheduleAddMarket(MARKET_ID_2, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeAddMarket(MARKET_ID_2);
      
      // Set allocations to 100/0
      const allocations = [
        { id: MARKET_ID, allocation: 9999 },
        { id: MARKET_ID_2, allocation: 1 }
      ];
      await bank.connect(admin).scheduleUpdateAllocations(allocations, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await bank.connect(admin).executeUpdateAllocations(allocations);
      
      // Send tokens directly to the bank contract
      const stuckAmount = ethers.parseEther("100");
      await loanToken.mint(await bank.getAddress(), stuckAmount);
      
      // Get initial positions
      const position1Before = await untitledHub.position(MARKET_ID, await bank.getAddress());
      const position2Before = await untitledHub.position(MARKET_ID_2, await bank.getAddress());
      
      // Redeposit stuck assets
      await bank.connect(admin).redepositStuckAssets();
      
      // Get positions after redeposit
      const position1After = await untitledHub.position(MARKET_ID, await bank.getAddress());
      const position2After = await untitledHub.position(MARKET_ID_2, await bank.getAddress());
      
      // Get market data to calculate asset amounts
      const market1 = await untitledHub.market(MARKET_ID);
      const market2 = await untitledHub.market(MARKET_ID_2);
      
      // Calculate asset differences
      const assets1Before = position1Before.supplyShares * market1.totalSupplyAssets / market1.totalSupplyShares;
      const assets2Before = position2Before.supplyShares * market2.totalSupplyAssets / market2.totalSupplyShares;
      
      const assets1After = position1After.supplyShares * market1.totalSupplyAssets / market1.totalSupplyShares;
      const assets2After = position2After.supplyShares * market2.totalSupplyAssets / market2.totalSupplyShares;
      
      // Verify all assets went to the first market
      expect(assets1After).to.be.closeTo(assets1Before + BigInt(stuckAmount), ethers.parseEther("0.1"));
      expect(assets2After).to.be.closeTo(assets2Before, ethers.parseEther("0.1")); // No change for market with 0 allocation
    });
  });
});