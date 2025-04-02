import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract, Signer } from "ethers";
import { upgrades } from "hardhat";

describe("CoreBank", function () {
  let coreBankFactory: Contract;
  let coreBankImplementation: Contract;
  let coreBank: Contract;
  let bankFactory: Contract;
  let bankImplementation: Contract;
  let bank1: Contract;
  let bank2: Contract;
  let untitledHub: Contract;
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

    // Deploy BankFactory
    const BankFactory = await ethers.getContractFactory("BankFactory");
    const bankFactoryArgs = [
      await bankImplementation.getAddress(),
      await untitledHub.getAddress()
    ];

    try {
      bankFactory = await upgrades.deployProxy(BankFactory, bankFactoryArgs);
      await bankFactory.waitForDeployment();
    } catch (error) {
      console.error("Proxy deployment error:", error);
      
      // Fall back to manual deployment and initialization
      bankFactory = await BankFactory.deploy();
      await bankFactory.waitForDeployment();
      
      try {
        await bankFactory.initialize(...bankFactoryArgs);
      } catch (initError) {
        console.error("Manual initialization error:", initError);
      }
    }

    // Create two Banks through the factory
    const tx1 = await bankFactory.createBank(
      await loanToken.getAddress(),
      "Test Bank 1",
      "TBANK1",
      100, // 1% fee (in basis points)
      await owner.getAddress(), // fee recipient
      600, // 10 mins delay
      await admin.getAddress(), // initial admin
      0 // BankType.Public
    );
    const receipt1 = await tx1.wait();
    
    // Find the BankCreated event to get the bank address
    const event1 = receipt1.logs.find(
      (log: any) => log.fragment && log.fragment.name === "BankCreated"
    );
    const bank1Address = event1.args[0];
    
    // Connect to the created bank
    bank1 = await ethers.getContractAt("Bank", bank1Address);

    // Create a second bank
    const tx2 = await bankFactory.createBank(
      await loanToken.getAddress(),
      "Test Bank 2",
      "TBANK2",
      150, // 1.5% fee (in basis points)
      await owner.getAddress(), // fee recipient
      600, // 10 mins delay
      await admin.getAddress(), // initial admin
      0 // BankType.Public
    );
    const receipt2 = await tx2.wait();
    
    // Find the BankCreated event to get the bank address
    const event2 = receipt2.logs.find(
      (log: any) => log.fragment && log.fragment.name === "BankCreated"
    );
    const bank2Address = event2.args[0];
    
    // Connect to the created bank
    bank2 = await ethers.getContractAt("Bank", bank2Address);

    // Deploy CoreBank implementation
    const CoreBank = await ethers.getContractFactory("CoreBank");
    coreBankImplementation = await CoreBank.deploy();
    await coreBankImplementation.waitForDeployment();

    // Deploy CoreBankFactory
    const CoreBankFactory = await ethers.getContractFactory("CoreBankFactory");
    const coreBankFactoryArgs = [await coreBankImplementation.getAddress()];

    try {
      coreBankFactory = await upgrades.deployProxy(CoreBankFactory, coreBankFactoryArgs);
      await coreBankFactory.waitForDeployment();
    } catch (error) {
      console.error("CoreBankFactory proxy deployment error:", error);
      
      // Fall back to manual deployment and initialization
      coreBankFactory = await CoreBankFactory.deploy();
      await coreBankFactory.waitForDeployment();
      
      try {
        await coreBankFactory.initialize(...coreBankFactoryArgs);
      } catch (initError) {
        console.error("Manual initialization error:", initError);
      }
    }

    // Create a CoreBank through the factory
    const coreBankTx = await coreBankFactory.createCoreBank(
      await loanToken.getAddress(),
      "Core Bank",
      "CBANK",
      600, // 10 mins delay
      await admin.getAddress() // initial admin
    );
    const coreBankReceipt = await coreBankTx.wait();
    
    // Find the CoreBankCreated event to get the coreBank address
    const coreBankEvent = coreBankReceipt.logs.find(
      (log: any) => log.fragment && log.fragment.name === "CoreBankCreated"
    );
    const coreBankAddress = coreBankEvent.args[0];
    
    // Connect to the created CoreBank
    coreBank = await ethers.getContractAt("CoreBank", coreBankAddress);

    // Mint tokens to users
    await loanToken.mint(await user1.getAddress(), INITIAL_BALANCE);
    await loanToken.mint(await user2.getAddress(), INITIAL_BALANCE);
    
    // Approve CoreBank to spend tokens
    await loanToken.connect(user1).approve(await coreBank.getAddress(), ethers.MaxUint256);
    await loanToken.connect(user2).approve(await coreBank.getAddress(), ethers.MaxUint256);

    // Grant proposer and executor roles to admin for CoreBank
    await coreBank.connect(admin).grantRole(await coreBank.PROPOSER_ROLE(), await admin.getAddress());
    await coreBank.connect(admin).grantRole(await coreBank.EXECUTOR_ROLE(), await admin.getAddress());

    // Grant proposer and executor roles to admin for both banks
    await bank1.connect(admin).grantRole(await bank1.PROPOSER_ROLE(), await admin.getAddress());
    await bank1.connect(admin).grantRole(await bank1.EXECUTOR_ROLE(), await admin.getAddress());
    await bank2.connect(admin).grantRole(await bank2.PROPOSER_ROLE(), await admin.getAddress());
    await bank2.connect(admin).grantRole(await bank2.EXECUTOR_ROLE(), await admin.getAddress());

    // Add market to both banks
    await bank1.connect(admin).scheduleAddMarket(MARKET_ID, 600);
    await bank2.connect(admin).scheduleAddMarket(MARKET_ID, 600);
    await network.provider.send("evm_increaseTime", [600]);
    await network.provider.send("evm_mine");
    await bank1.connect(admin).executeAddMarket(MARKET_ID);
    await bank2.connect(admin).executeAddMarket(MARKET_ID);

    // Set allocations for both banks
    const allocations = [{ id: MARKET_ID, allocation: 10000 }]; // 100% allocation
    await bank1.connect(admin).scheduleUpdateAllocations(allocations, 600);
    await bank2.connect(admin).scheduleUpdateAllocations(allocations, 600);
    await network.provider.send("evm_increaseTime", [600]);
    await network.provider.send("evm_mine");
    await bank1.connect(admin).executeUpdateAllocations(allocations);
    await bank2.connect(admin).executeUpdateAllocations(allocations);
  });

  describe("CoreBankFactory", function () {
    it("should create a CoreBank correctly", async function () {
      // Verify the CoreBank was created and tracked in the factory
      expect(await coreBankFactory.isCoreBank(await coreBank.getAddress())).to.be.true;
      expect(await coreBankFactory.getCoreBankCount()).to.equal(1);
      expect(await coreBankFactory.getCoreBankAt(0)).to.equal(await coreBank.getAddress());
    });

    it("should update CoreBank implementation", async function () {
      // Deploy a new implementation
      const NewCoreBank = await ethers.getContractFactory("CoreBank");
      const newImplementation = await NewCoreBank.deploy();
      await newImplementation.waitForDeployment();
      
      // Update implementation
      await coreBankFactory.updateCoreBankImplementation(await newImplementation.getAddress());
      
      // Verify implementation was updated
      expect(await coreBankFactory.coreBankImplementation()).to.equal(await newImplementation.getAddress());
    });
    
    it("should revert when non-owner tries to update implementation", async function () {
      const NewCoreBank = await ethers.getContractFactory("CoreBank");
      const newImplementation = await NewCoreBank.deploy();
      await newImplementation.waitForDeployment();
      
      await expect(
        coreBankFactory.connect(user1).updateCoreBankImplementation(await newImplementation.getAddress())
      ).to.be.reverted;
    });
  });

  describe("CoreBank Initialization", function () {
    it("should initialize with correct parameters", async function () {
      expect(await coreBank.asset()).to.equal(await loanToken.getAddress());
      expect(await coreBank.name()).to.equal("Core Bank");
      expect(await coreBank.symbol()).to.equal("CBANK");
      
      // Check admin role
      expect(await coreBank.hasRole(await coreBank.DEFAULT_ADMIN_ROLE(), await admin.getAddress())).to.be.true;
    });
  });

  describe("Bank Management", function () {
    it("should schedule, execute, and cancel bank addition", async function () {
      // Schedule bank addition
      const tx = await coreBank.connect(admin).scheduleAddBank(await bank1.getAddress(), 600);
      const receipt = await tx.wait();
      
      // Find the operation ID from the event
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "BankAdditionScheduled"
      );
      expect(event).to.not.be.undefined;
      
      // Advance time to pass the delay
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      
      // Execute bank addition
      await coreBank.connect(admin).executeAddBank(await bank1.getAddress());
      
      // Verify bank was added
      expect(await coreBank.isBankEnabled(await bank1.getAddress())).to.be.true;
      
      // Schedule another bank addition and cancel it
      await coreBank.connect(admin).scheduleAddBank(await bank2.getAddress(), 600);
      await coreBank.connect(admin).cancelAddBank(await bank2.getAddress());
      
      // Advance time
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      
      // Try to execute the cancelled operation (should fail)
      await expect(
        coreBank.connect(admin).executeAddBank(await bank2.getAddress())
      ).to.be.reverted;
    });
    
    it("should schedule, execute, and cancel bank removal", async function () {
      // First add a bank
      await coreBank.connect(admin).scheduleAddBank(await bank1.getAddress(), 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await coreBank.connect(admin).executeAddBank(await bank1.getAddress());
      
      // Schedule bank removal
      const tx = await coreBank.connect(admin).scheduleRemoveBank(await bank1.getAddress(), 600);
      const receipt = await tx.wait();
      
      // Find the operation ID from the event
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "BankRemovalScheduled"
      );
      expect(event).to.not.be.undefined;
      
      // Advance time
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      
      // Execute bank removal
      await coreBank.connect(admin).executeRemoveBank(await bank1.getAddress());
      
      // Verify bank was removed
      expect(await coreBank.isBankEnabled(await bank1.getAddress())).to.be.false;
      
      // Add bank again, then schedule removal and cancel it
      await coreBank.connect(admin).scheduleAddBank(await bank1.getAddress(), 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await coreBank.connect(admin).executeAddBank(await bank1.getAddress());
      
      await coreBank.connect(admin).scheduleRemoveBank(await bank1.getAddress(), 600);
      await coreBank.connect(admin).cancelRemoveBank(await bank1.getAddress());
      
      // Advance time
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      
      // Verify bank is still enabled after cancellation
      expect(await coreBank.isBankEnabled(await bank1.getAddress())).to.be.true;
    });
    
    it("should update allocations", async function () {
      // Add two banks
      await coreBank.connect(admin).scheduleAddBank(await bank1.getAddress(), 600);
      await coreBank.connect(admin).scheduleAddBank(await bank2.getAddress(), 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await coreBank.connect(admin).executeAddBank(await bank1.getAddress());
      await coreBank.connect(admin).executeAddBank(await bank2.getAddress());
      
      // Define new allocations
      const newAllocations = [
        { bank: await bank1.getAddress(), allocation: 7000 }, // 70%
        { bank: await bank2.getAddress(), allocation: 3000 }  // 30%
      ];
      
      // Schedule allocation update
      const tx = await coreBank.connect(admin).scheduleUpdateAllocations(newAllocations, 600);
      const receipt = await tx.wait();
      
      // Find the operation ID from the event
      const event = receipt.logs.find(
        (log: any) => log.fragment && log.fragment.name === "AllocationsUpdateScheduled"
      );
      expect(event).to.not.be.undefined;
      
      // Advance time
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      
      // Execute allocation update
      await coreBank.connect(admin).executeUpdateAllocations(newAllocations);
      
      // Verify allocations were updated
      const allocations = await coreBank.getBankAllocations();
      expect(allocations.length).to.equal(2);
      expect(allocations[0].bank).to.equal(await bank1.getAddress());
      expect(allocations[0].allocation).to.equal(7000);
      expect(allocations[1].bank).to.equal(await bank2.getAddress());
      expect(allocations[1].allocation).to.equal(3000);
      
      // Schedule another allocation update and cancel it
      const newerAllocations = [
        { bank: await bank1.getAddress(), allocation: 5000 }, // 50%
        { bank: await bank2.getAddress(), allocation: 5000 }  // 50%
      ];
      await coreBank.connect(admin).scheduleUpdateAllocations(newerAllocations, 600);
      await coreBank.connect(admin).cancelUpdateAllocations(newerAllocations);
      
      // Advance time
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      
      // Verify allocations didn't change after cancellation
      const allocationsAfterCancel = await coreBank.getBankAllocations();
      expect(allocationsAfterCancel[0].allocation).to.equal(7000);
      expect(allocationsAfterCancel[1].allocation).to.equal(3000);
    });
  });

  describe("Deposit and Withdraw", function () {
    beforeEach(async function () {
      // Add both banks to CoreBank
      await coreBank.connect(admin).scheduleAddBank(await bank1.getAddress(), 600);
      await coreBank.connect(admin).scheduleAddBank(await bank2.getAddress(), 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await coreBank.connect(admin).executeAddBank(await bank1.getAddress());
      await coreBank.connect(admin).executeAddBank(await bank2.getAddress());
      
      // Set allocations (70% to bank1, 30% to bank2)
      const allocations = [
        { bank: await bank1.getAddress(), allocation: 7000 },
        { bank: await bank2.getAddress(), allocation: 3000 }
      ];
      await coreBank.connect(admin).scheduleUpdateAllocations(allocations, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await coreBank.connect(admin).executeUpdateAllocations(allocations);
    });
    
    it("should deposit and withdraw correctly", async function () {
      // User1 deposits into the CoreBank
      const depositAmount = ethers.parseEther("100");
      await coreBank.connect(user1).deposit(depositAmount, await user1.getAddress());
      
      // Verify user1 received shares
      expect(await coreBank.balanceOf(await user1.getAddress())).to.be.gt(0);
      
      // Verify assets were distributed to banks according to allocations
      expect(await bank1.balanceOf(await coreBank.getAddress())).to.be.gt(0);
      expect(await bank2.balanceOf(await coreBank.getAddress())).to.be.gt(0);
      
      // Verify approximate distribution (70/30)
      const bank1Assets = await bank1.convertToAssets(await bank1.balanceOf(await coreBank.getAddress()));
      const bank2Assets = await bank2.convertToAssets(await bank2.balanceOf(await coreBank.getAddress()));
      
      expect(bank1Assets).to.be.closeTo(ethers.parseEther("70"), ethers.parseEther("1"));
      expect(bank2Assets).to.be.closeTo(ethers.parseEther("30"), ethers.parseEther("1"));
      
      // User1 withdraws half
      const withdrawAmount = ethers.parseEther("50");
      await coreBank.connect(user1).withdraw(withdrawAmount, await user1.getAddress(), await user1.getAddress());
      
      // Verify user1's balance decreased
      const expectedRemainingShares = await coreBank.convertToShares(depositAmount - withdrawAmount);
      expect(await coreBank.balanceOf(await user1.getAddress())).to.be.closeTo(expectedRemainingShares, expectedRemainingShares / BigInt(100)); // 1% tolerance
      
      // Verify assets were withdrawn proportionally from banks
      const bank1AssetsAfter = await bank1.convertToAssets(await bank1.balanceOf(await coreBank.getAddress()));
      const bank2AssetsAfter = await bank2.convertToAssets(await bank2.balanceOf(await coreBank.getAddress()));
      
      expect(bank1AssetsAfter).to.be.closeTo(ethers.parseEther("35"), ethers.parseEther("1"));
      expect(bank2AssetsAfter).to.be.closeTo(ethers.parseEther("15"), ethers.parseEther("1"));
    });
    
    it("should handle full withdrawal", async function () {
      // User1 deposits into the CoreBank
      const depositAmount = ethers.parseEther("100");
      await coreBank.connect(user1).deposit(depositAmount, await user1.getAddress());
      
      // User1 withdraws everything
      const shares = await coreBank.balanceOf(await user1.getAddress());
      await coreBank.connect(user1).redeem(shares, await user1.getAddress(), await user1.getAddress());
      
      // Verify user1's balance is zero
      expect(await coreBank.balanceOf(await user1.getAddress())).to.equal(0);
      
      // Verify banks have minimal or no assets from CoreBank
      const bank1Assets = await bank1.convertToAssets(await bank1.balanceOf(await coreBank.getAddress()));
      const bank2Assets = await bank2.convertToAssets(await bank2.balanceOf(await coreBank.getAddress()));
      
      expect(bank1Assets).to.be.lt(ethers.parseEther("0.1"));
      expect(bank2Assets).to.be.lt(ethers.parseEther("0.1"));
    });
  });

  describe("Reallocation", function () {
    beforeEach(async function () {
      // Add both banks to CoreBank
      await coreBank.connect(admin).scheduleAddBank(await bank1.getAddress(), 600);
      await coreBank.connect(admin).scheduleAddBank(await bank2.getAddress(), 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await coreBank.connect(admin).executeAddBank(await bank1.getAddress());
      await coreBank.connect(admin).executeAddBank(await bank2.getAddress());
      
      // Set allocations (80% to bank1, 20% to bank2)
      const allocations = [
        { bank: await bank1.getAddress(), allocation: 8000 },
        { bank: await bank2.getAddress(), allocation: 2000 }
      ];
      await coreBank.connect(admin).scheduleUpdateAllocations(allocations, 600);
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      await coreBank.connect(admin).executeUpdateAllocations(allocations);
      
      // User1 deposits into the CoreBank
      const depositAmount = ethers.parseEther("100");
      await coreBank.connect(user1).deposit(depositAmount, await user1.getAddress());
    });
    
    it("should reallocate funds between banks", async function () {
      // Schedule reallocation from bank1 to bank2
      const withdrawBanks = [await bank1.getAddress()];
      const withdrawAmounts = [ethers.parseEther("30")];
      const depositBanks = [await bank2.getAddress()];
      const depositAmounts = [ethers.parseEther("30")];
      
      await coreBank.connect(admin).scheduleReallocate(
        withdrawBanks,
        withdrawAmounts,
        depositBanks,
        depositAmounts,
        600
      );
      
      // Advance time
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      
      // Execute reallocation
      await coreBank.connect(admin).executeReallocate(
        withdrawBanks,
        withdrawAmounts,
        depositBanks,
        depositAmounts
      );
      
      // Verify funds were moved
      const bank1Assets = await bank1.convertToAssets(await bank1.balanceOf(await coreBank.getAddress()));
      const bank2Assets = await bank2.convertToAssets(await bank2.balanceOf(await coreBank.getAddress()));
      
      // Should now be approximately 50/50 instead of 80/20
      expect(bank1Assets).to.be.closeTo(ethers.parseEther("50"), ethers.parseEther("1"));
      expect(bank2Assets).to.be.closeTo(ethers.parseEther("50"), ethers.parseEther("1"));
    });
    
    it("should cancel scheduled reallocation", async function () {
      // Schedule reallocation
      const withdrawBanks = [await bank1.getAddress()];
      const withdrawAmounts = [ethers.parseEther("30")];
      const depositBanks = [await bank2.getAddress()];
      const depositAmounts = [ethers.parseEther("30")];
      
      await coreBank.connect(admin).scheduleReallocate(
        withdrawBanks,
        withdrawAmounts,
        depositBanks,
        depositAmounts,
        600
      );
      
      // Cancel reallocation
      await coreBank.connect(admin).cancelReallocate(
        withdrawBanks,
        withdrawAmounts,
        depositBanks,
        depositAmounts
      );
      
      // Advance time
      await network.provider.send("evm_increaseTime", [600]);
      await network.provider.send("evm_mine");
      
      // Try to execute the cancelled operation (should fail)
      await expect(
        coreBank.connect(admin).executeReallocate(
          withdrawBanks,
          withdrawAmounts,
          depositBanks,
          depositAmounts
        )
      ).to.be.reverted;
      
      // Verify funds were not moved
      const bank1Assets = await bank1.convertToAssets(await bank1.balanceOf(await coreBank.getAddress()));
      const bank2Assets = await bank2.convertToAssets(await bank2.balanceOf(await coreBank.getAddress()));
      
      // Should still be approximately 80/20
      expect(bank1Assets).to.be.closeTo(ethers.parseEther("80"), ethers.parseEther("1"));
      expect(bank2Assets).to.be.closeTo(ethers.parseEther("20"), ethers.parseEther("1"));
    });
  });
});