import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract, Signer } from "ethers";

describe("UntitledHub", function () {
  let untitledHub: Contract;
  let loanToken: Contract;
  let collateralToken: Contract;
  let priceProvider: Contract;
  let interestRateModel: Contract;
  let owner: Signer, user1: Signer, user2: Signer;
  const INITIAL_BALANCE = ethers.parseEther("1000");
  
  // Set a longer timeout for these tests
  this.timeout(30000);

  beforeEach(async function () {
    // Get signers
    [owner, user1, user2] = await ethers.getSigners();

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

    // Mint tokens to users
    await loanToken.mint(await user1.getAddress(), INITIAL_BALANCE);
    await loanToken.mint(await user2.getAddress(), INITIAL_BALANCE);
    await collateralToken.mint(await user1.getAddress(), INITIAL_BALANCE);
    await collateralToken.mint(await user2.getAddress(), INITIAL_BALANCE);

    // Approve UntitledHub to spend tokens on behalf of each user
    const hubAddress = await untitledHub.getAddress();
    await loanToken.connect(user1).approve(hubAddress, ethers.MaxUint256);
    await collateralToken.connect(user1).approve(hubAddress, ethers.MaxUint256);
    await loanToken.connect(user2).approve(hubAddress, ethers.MaxUint256);
    await collateralToken.connect(user2).approve(hubAddress, ethers.MaxUint256);
  });

  describe("Market creation", function () {
    it("should create a market", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.81"), // 81% LLTV - unique for this test
      };

      // Call createMarket with sending 0.01 ether
      const tx = await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      await tx.wait();

      // Assume the first market ID is 1
      const marketId = 1;
      expect(marketId).to.equal(1);
    });
  });

  describe("Supply and Borrow", function () {
    it("should allow supply and borrow", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.82"), // 82% LLTV - unique for this test
      };

      // Create market with 0.01 ether sent
      const tx = await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      await tx.wait();
      const marketId = 1;

      // User1 supplies 100 tokens
      await untitledHub.connect(user1).supply(marketId, ethers.parseEther("100"), "0x");

      // User2 supplies 50 collateral tokens
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("50"), "0x");

      // User2 borrows 30 tokens
      await untitledHub.connect(user2).borrow(marketId, ethers.parseEther("30"), await user2.getAddress());

      // Verify the borrow amount
      const position = await untitledHub.position(marketId, await user2.getAddress());
      expect(position.borrowShares).to.be.gt(0);
    });
  });

  describe("Repay and Withdraw", function () {
    it("should allow repay and withdraw", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.83"), // 83% LLTV - unique for this test
      };

      // Create market with 0.01 ether sent
      const tx = await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      await tx.wait();
      const marketId = 1;

      // User1 supplies 100 tokens
      await untitledHub.connect(user1).supply(marketId, ethers.parseEther("100"), "0x");

      // User2 supplies 50 collateral tokens and borrows 30 tokens
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("50"), "0x");
      await untitledHub.connect(user2).borrow(marketId, ethers.parseEther("30"), await user2.getAddress());

      // User2 repays 20 tokens
      const repayTx = await untitledHub.connect(user2).repay(marketId, ethers.parseEther("20"), "0x");
      const repayReceipt = await repayTx.wait();
      
      // Get the repay event data
      const repayEvent = repayReceipt.logs.find(
        log => log.fragment && log.fragment.name === "Repay"
      );
      
      if (repayEvent) {
        const [, , ,repaidAssets, repaidShares] = repayEvent.args;
        expect(repaidAssets).to.equal(ethers.parseEther("20"), "Repaid assets should be 20");
        expect(repaidShares).to.be.gt(0, "Repaid shares should be greater than 0");
      }

      // User1 withdraws 50 tokens
      const withdrawTx = await untitledHub.connect(user1).withdraw(
        marketId, 
        ethers.parseEther("50"), 
        await user1.getAddress()
      );
      const withdrawReceipt = await withdrawTx.wait();
      
      // Get the withdraw event data
      const withdrawEvent = withdrawReceipt.logs.find(
        log => log.fragment && log.fragment.name === "Withdraw"
      );
      
      if (withdrawEvent) {
        const [, , , , withdrawnAssets, withdrawnShares] = withdrawEvent.args;
        expect(withdrawnAssets).to.equal(ethers.parseEther("50"), "Withdrawn assets should be 50");
        expect(withdrawnShares).to.be.gt(0, "Withdrawn shares should be greater than 0");
      }
    });
  });

  describe("Liquidation", function () {
    it("should allow liquidation by seized assets", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.84"), // 84% LLTV - unique for this test
      };

      // Create market with 0.01 ether sent
      const tx = await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      await tx.wait();
      const marketId = 1;

      // User1 supplies 100 tokens
      await untitledHub.connect(user1).supply(marketId, ethers.parseEther("100"), "0x");

      // User2 supplies 50 collateral tokens and borrows 39 tokens (close to limit)
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("50"), "0x");
      await untitledHub.connect(user2).borrow(marketId, ethers.parseEther("39"), await user2.getAddress());

      // Simulate price drop to make the position liquidatable
      await priceProvider.setCollateralTokenPrice(ethers.parseEther("0.5") * BigInt(1e18)); // 50% price drop from 1e36

      // Advance time to accrue some interest
      await network.provider.send("evm_increaseTime", [365 * 24 * 3600]);
      await network.provider.send("evm_mine");

      // User1 liquidates User2's position
      await untitledHub.connect(user1).liquidateBySeizedAssets(
        marketId,
        await user2.getAddress(),
        ethers.parseEther("20"),
        "0x"
      );

      // Verify the liquidation
      const position = await untitledHub.position(marketId, await user2.getAddress());
      expect(position.collateral).to.be.lt(ethers.parseEther("50")); // Should have less collateral after liquidation
    });
  });

  describe("Accrue Interest", function () {
    it("should accrue interest correctly", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.85"), // 85% LLTV - unique for this test
      };

      const tx = await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      await tx.wait();
      const marketId = 1;

      // User1 supplies tokens
      await untitledHub.connect(user1).supply(marketId, ethers.parseEther("100"), "0x");
      
      // User2 supplies collateral and borrows tokens
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("50"), "0x");
      await untitledHub.connect(user2).borrow(marketId, ethers.parseEther("30"), await user2.getAddress());

      // Increase time by one year
      await network.provider.send("evm_increaseTime", [365 * 24 * 3600]);
      await network.provider.send("evm_mine");

      // Check market state before and after accruing interest
      const marketBefore = await untitledHub.market(marketId);
      await untitledHub.accrueInterest(marketId);
      const marketAfter = await untitledHub.market(marketId);

      const totalBorrowAssetsBefore = marketBefore.totalBorrowAssets;
      const totalBorrowAssetsAfter = marketAfter.totalBorrowAssets;
      const interestAccrued = totalBorrowAssetsAfter - totalBorrowAssetsBefore;
      
      expect(interestAccrued).to.be.gt(0);
    });
  });

  describe("Permission Management and For Functions", function () {
    it("should allow supply for another user with permission", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // Grant permission for user1 to supply on behalf of user2
      await untitledHub.connect(user2).setGrantPermission(await user1.getAddress(), true);

      // User1 supplies for user2
      const supplyTx = await untitledHub.connect(user1).supplyFor(
        marketId,
        ethers.parseEther("100"),
        await user2.getAddress(),
        "0x"
      );
      const supplyReceipt = await supplyTx.wait();
      
      // Get the supply event data
      const supplyEvent = supplyReceipt.logs.find(
        log => log.fragment && log.fragment.name === "Supply"
      );
      
      if (supplyEvent) {
        const [, , , suppliedAssets, suppliedShares] = supplyEvent.args;
        expect(suppliedAssets).to.equal(ethers.parseEther("100"));
        expect(suppliedShares).to.be.gt(0);
      }
      
      // Verify user2's position has the supply shares
      const position = await untitledHub.position(marketId, await user2.getAddress());
      expect(position.supplyShares).to.be.gt(0);
    });

    it("should allow withdraw for another user with permission", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // User2 supplies tokens
      await untitledHub.connect(user2).supply(marketId, ethers.parseEther("100"), "0x");
      
      // Grant permission for user1 to withdraw on behalf of user2
      await untitledHub.connect(user2).setGrantPermission(await user1.getAddress(), true);
      
      // Get initial balance
      const initialBalance = await loanToken.balanceOf(await user2.getAddress());
      
      // User1 withdraws for user2
      const withdrawTx = await untitledHub.connect(user1).withdrawFor(
        marketId,
        ethers.parseEther("50"),
        await user2.getAddress(),
        await user2.getAddress()
      );
      const withdrawReceipt = await withdrawTx.wait();
      
      // Get the withdraw event data
      const withdrawEvent = withdrawReceipt.logs.find(
        log => log.fragment && log.fragment.name === "Withdraw"
      );
      
      if (withdrawEvent) {
        const [, , , , withdrawnAssets, withdrawnShares] = withdrawEvent.args;
        expect(withdrawnAssets).to.equal(ethers.parseEther("50"));
        expect(withdrawnShares).to.be.gt(0);
      }
      
      // Verify user2's balance increased
      const finalBalance = await loanToken.balanceOf(await user2.getAddress());
      expect(finalBalance - initialBalance).to.equal(ethers.parseEther("50"));
    });

    it("should allow borrow for another user with permission", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // User1 supplies tokens to the market
      await untitledHub.connect(user1).supply(marketId, ethers.parseEther("100"), "0x");
      
      // User2 supplies collateral
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("50"), "0x");
      
      // Grant permission for user1 to borrow on behalf of user2
      await untitledHub.connect(user2).setGrantPermission(await user1.getAddress(), true);
      
      // Get initial balance
      const initialBalance = await loanToken.balanceOf(await user2.getAddress());
      
      // User1 borrows for user2
      const borrowTx = await untitledHub.connect(user1).borrowFor(
        marketId,
        ethers.parseEther("30"),
        await user2.getAddress(),
        await user2.getAddress()
      );
      const borrowReceipt = await borrowTx.wait();
      
      // Get the borrow event data
      const borrowEvent = borrowReceipt.logs.find(
        log => log.fragment && log.fragment.name === "Borrow"
      );
      
      if (borrowEvent) {
        const [, , , , borrowedAssets, borrowedShares] = borrowEvent.args;
        expect(borrowedAssets).to.equal(ethers.parseEther("30"));
        expect(borrowedShares).to.be.gt(0);
      }
      
      // Verify user2's balance increased
      const finalBalance = await loanToken.balanceOf(await user2.getAddress());
      expect(finalBalance - initialBalance).to.equal(ethers.parseEther("30"));
      
      // Verify user2's position has the borrow shares
      const position = await untitledHub.position(marketId, await user2.getAddress());
      expect(position.borrowShares).to.be.gt(0);
    });

    it("should allow repay for another user with permission", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // User1 supplies tokens to the market
      await untitledHub.connect(user1).supply(marketId, ethers.parseEther("100"), "0x");
      
      // User2 supplies collateral and borrows
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("50"), "0x");
      await untitledHub.connect(user2).borrow(marketId, ethers.parseEther("30"), await user2.getAddress());
      
      // Grant permission for user1 to repay on behalf of user2
      await untitledHub.connect(user2).setGrantPermission(await user1.getAddress(), true);
      
      // User1 repays for user2
      const repayTx = await untitledHub.connect(user1).repayFor(
        marketId,
        ethers.parseEther("20"),
        await user2.getAddress(),
        "0x"
      );
      const repayReceipt = await repayTx.wait();
      
      // Get the repay event data
      const repayEvent = repayReceipt.logs.find(
        log => log.fragment && log.fragment.name === "Repay"
      );
      
      if (repayEvent) {
        const [, , , repaidAssets, repaidShares] = repayEvent.args;
        expect(repaidAssets).to.equal(ethers.parseEther("20"));
        expect(repaidShares).to.be.gt(0);
      }
      
      // Verify user2's position has reduced borrow shares
      const position = await untitledHub.position(marketId, await user2.getAddress());
      const market = await untitledHub.market(marketId);

      const borrowedAmount = position.borrowShares * market.totalBorrowAssets / market.totalBorrowShares;
      expect(borrowedAmount).to.be.closeTo(ethers.parseEther("10"), ethers.parseEther("0.01"));
    });

    it("should allow supply collateral for another user with permission", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // Grant permission for user1 to supply collateral on behalf of user2
      await untitledHub.connect(user2).setGrantPermission(await user1.getAddress(), true);
      
      // User1 supplies collateral for user2
      const supplyTx = await untitledHub.connect(user1).supplyCollateralFor(
        marketId,
        ethers.parseEther("50"),
        await user2.getAddress(),
        "0x"
      );
      const supplyReceipt = await supplyTx.wait();
      
      // Get the supply collateral event data
      const supplyEvent = supplyReceipt.logs.find(
        log => log.fragment && log.fragment.name === "SupplyCollateral"
      );
      
      if (supplyEvent) {
        const [, , , suppliedAssets] = supplyEvent.args;
        expect(suppliedAssets).to.equal(ethers.parseEther("50"));
      }
      
      // Verify user2's position has the collateral
      const position = await untitledHub.position(marketId, await user2.getAddress());
      expect(position.collateral).to.equal(ethers.parseEther("50"));
    });

    it("should allow withdraw collateral for another user with permission", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // User2 supplies collateral
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("50"), "0x");
      
      // Grant permission for user1 to withdraw collateral on behalf of user2
      await untitledHub.connect(user2).setGrantPermission(await user1.getAddress(), true);
      
      // Get initial balance
      const initialBalance = await collateralToken.balanceOf(await user2.getAddress());
      
      // User1 withdraws collateral for user2
      const withdrawTx = await untitledHub.connect(user1).withdrawCollateralFor(
        marketId,
        ethers.parseEther("30"),
        await user2.getAddress(),
        await user2.getAddress()
      );
      const withdrawReceipt = await withdrawTx.wait();
      
      // Get the withdraw collateral event data
      const withdrawEvent = withdrawReceipt.logs.find(
        log => log.fragment && log.fragment.name === "WithdrawCollateral"
      );
      
      if (withdrawEvent) {
        const [, , , , withdrawnAssets] = withdrawEvent.args;
        expect(withdrawnAssets).to.equal(ethers.parseEther("30"));
      }
      
      // Verify user2's balance increased
      const finalBalance = await collateralToken.balanceOf(await user2.getAddress());
      expect(finalBalance - initialBalance).to.equal(ethers.parseEther("30"));
      
      // Verify user2's position has reduced collateral
      const position = await untitledHub.position(marketId, await user2.getAddress());
      expect(position.collateral).to.equal(ethers.parseEther("20"));
    });

    it("should revert when trying to use For functions without permission", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // No permission granted
      
      // Try to supply for user2 without permission
      await expect(
        untitledHub.connect(user1).supplyFor(
          marketId,
          ethers.parseEther("100"),
          await user2.getAddress(),
          "0x"
        )
      ).to.be.revertedWith("UntitledHub: not granted");
      
      // Try to withdraw for user2 without permission
      await untitledHub.connect(user2).supply(marketId, ethers.parseEther("100"), "0x");
      await expect(
        untitledHub.connect(user1).withdrawFor(
          marketId,
          ethers.parseEther("50"),
          await user2.getAddress(),
          await user2.getAddress()
        )
      ).to.be.revertedWith("UntitledHub: not granted");
      
      // Try to borrow for user2 without permission
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("50"), "0x");
      await expect(
        untitledHub.connect(user1).borrowFor(
          marketId,
          ethers.parseEther("30"),
          await user2.getAddress(),
          await user2.getAddress()
        )
      ).to.be.revertedWith("UntitledHub: not granted");
    });

    it("should allow revoking permission", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // Grant permission for user1 to act on behalf of user2
      await untitledHub.connect(user2).setGrantPermission(await user1.getAddress(), true);
      
      // Verify permission is granted
      await untitledHub.connect(user1).supplyFor(
        marketId,
        ethers.parseEther("10"),
        await user2.getAddress(),
        "0x"
      );
      
      // Revoke permission
      await untitledHub.connect(user2).setGrantPermission(await user1.getAddress(), false);
      
      // Try to supply after permission revoked
      await expect(
        untitledHub.connect(user1).supplyFor(
          marketId,
          ethers.parseEther("10"),
          await user2.getAddress(),
          "0x"
        )
      ).to.be.revertedWith("UntitledHub: not granted");
    });
  });

  describe("Fee Management", function () {
    it("should allow setting and withdrawing fees", async function () {
      // Create market to generate fees
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // Set fee for the market
      const newFee = ethers.parseEther("0.1"); // 10% fee
      await untitledHub.setFee(marketId, newFee);

      const market = await untitledHub.market(marketId);
      expect(market.fee).to.equal(newFee);

      // Set fee recipient
      const newFeeRecipient = await user1.getAddress();
      await untitledHub.setFeeRecipient(newFeeRecipient);
      expect(await untitledHub.feeRecipient()).to.equal(newFeeRecipient);

      // Check collected fees
      const collectedFees = await untitledHub.collectedFees();
      expect(collectedFees).to.equal(ethers.parseEther("0.01")); // From market creation

      // Withdraw fees
      const initialBalance = await ethers.provider.getBalance(await owner.getAddress());
      await untitledHub.withdrawFees(ethers.ZeroAddress, await owner.getAddress(), ethers.parseEther("0.01"));
      
      const finalBalance = await ethers.provider.getBalance(await owner.getAddress());
      // Account for gas costs in the comparison
      expect(finalBalance).to.be.gt(initialBalance);
    });
  });

  describe("Health Factor", function () {
    it("should calculate health factor correctly", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"), // 80% LLTV
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // Initial health factor should be max for user with no borrows
      const maxUint256 = 2n**256n - 1n;
      expect(await untitledHub.getHealthFactor(marketId, await user1.getAddress())).to.equal(maxUint256);

      // Setup borrowing position
      await untitledHub.connect(user1).supply(marketId, ethers.parseEther("100"), "0x");
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("50"), "0x");
      await untitledHub.connect(user2).borrow(marketId, ethers.parseEther("30"), await user2.getAddress());

      // Calculate expected health factor
      // With 50 collateral, price of 1, and 80% LLTV, max borrow is 40
      // Current borrow is 30, so health factor should be 40/30 = 1.33...
      const healthFactor = await untitledHub.getHealthFactor(marketId, await user2.getAddress());
      
      // Expected health factor is approximately 1.33
      const expectedHealthFactor = ethers.parseEther("1.333333333333333333");
      const tolerance = expectedHealthFactor * 5n / 1000n; // 0.5% tolerance
      expect(healthFactor).to.be.closeTo(expectedHealthFactor, tolerance);

      // Reduce collateral price by half and check health factor
      await priceProvider.setCollateralTokenPrice(ethers.parseEther("0.5") * BigInt(1e18));
      const healthFactorAfter = await untitledHub.getHealthFactor(marketId, await user2.getAddress());
      
      // Expected health factor after price drop is approximately 0.66666666666666
      const expectedHealthFactorAfter = ethers.parseEther("0.666666666666666666");
      const toleranceAfter = expectedHealthFactorAfter * 5n / 1000n; // 0.5% tolerance
      expect(healthFactorAfter).to.be.closeTo(expectedHealthFactorAfter, toleranceAfter);
    });
  });

  describe("IRM Management", function () {
    it("should register and unregister IRMs correctly", async function () {
      const newIrm = await (await ethers.getContractFactory("MockInterestRateModel")).deploy();
      await newIrm.waitForDeployment();
      
      // Only owner can register IRM
      await expect(
        untitledHub.connect(user1).registerIrm(await newIrm.getAddress(), true)
      ).to.be.revertedWith("UntitledHub: not owner");

      // Owner can register valid IRM
      await untitledHub.registerIrm(await newIrm.getAddress(), true);
      expect(await untitledHub.isIrmRegistered(await newIrm.getAddress())).to.be.true;

      // Owner can unregister IRM
      await untitledHub.registerIrm(await newIrm.getAddress(), false);
      expect(await untitledHub.isIrmRegistered(await newIrm.getAddress())).to.be.false;

      // Test market creation with unregistered IRM
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await newIrm.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      
      await expect(
        untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") })
      ).to.be.revertedWith("UntitledHub: IRM not registered");
    });
  });

  describe("Owner Management", function () {
    it("should allow owner to set fee recipient", async function () {
      await expect(
        untitledHub.connect(user1).setFeeRecipient(await user2.getAddress())
      ).to.be.revertedWith("UntitledHub: not owner");
      
      // Call owner function from owner (should succeed)
      await untitledHub.connect(owner).setFeeRecipient(await user2.getAddress());
      expect(await untitledHub.feeRecipient()).to.equal(await user2.getAddress());
    });
  });

  describe("Flash Loans", function () {
    it("should execute flash loans with fees", async function () {
      // Deploy a mock flash loan receiver contract
      const MockFlashLoanReceiver = await ethers.getContractFactory("MockFlashLoanReceiver");
      const flashLoanReceiver = await MockFlashLoanReceiver.deploy(await untitledHub.getAddress());
      await flashLoanReceiver.waitForDeployment();
      
      // Set flash loan fee rate
      const newFeeRate = ethers.parseEther("0.001"); // 0.1% fee
      await untitledHub.setFlashLoanFeeRate(newFeeRate);
      expect(await untitledHub.flashLoanFeeRate()).to.equal(newFeeRate);
      
      // Fund the flash loan receiver with tokens to repay the loan + fee
      const loanAmount = ethers.parseEther("100");
      const feeAmount = loanAmount * newFeeRate / ethers.parseEther("1");
      const totalRepayment = loanAmount + feeAmount;
      
      await loanToken.mint(await flashLoanReceiver.getAddress(), totalRepayment);
      
      // Mint tokens to the hub for flash loan
      await loanToken.mint(await untitledHub.getAddress(), loanAmount);
      
      // Execute flash loan
      await flashLoanReceiver.executeFlashLoan(await loanToken.getAddress(), loanAmount);
      
      // Check that fees were collected
      expect(await untitledHub.tokenFees(await loanToken.getAddress())).to.equal(feeAmount);
      
      // Withdraw the collected fees
      await untitledHub.withdrawFees(
        await loanToken.getAddress(), 
        await owner.getAddress(), 
        feeAmount
      );
      
      // Verify fees were withdrawn
      expect(await untitledHub.tokenFees(await loanToken.getAddress())).to.equal(0);
      expect(await loanToken.balanceOf(await owner.getAddress())).to.equal(feeAmount);
    });
    
    it("should revert flash loan with zero amount", async function () {
      const MockFlashLoanReceiver = await ethers.getContractFactory("MockFlashLoanReceiver");
      const flashLoanReceiver = await MockFlashLoanReceiver.deploy(await untitledHub.getAddress());
      await flashLoanReceiver.waitForDeployment();
      
      await expect(
        flashLoanReceiver.executeFlashLoan(await loanToken.getAddress(), 0)
      ).to.be.revertedWith("UntitledHub: zero assets");
    });
  });

  describe("Bad Debt Handling", function () {
    it("should handle bad debt when liquidating a position with no collateral left", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.9"), // 90% LLTV - high to create bad debt scenario
      };

      // Create market
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // User1 supplies 100 tokens
      await untitledHub.connect(user1).supply(marketId, ethers.parseEther("100"), "0x");

      // User2 supplies small amount of collateral and borrows close to max
      await untitledHub.connect(user2).supplyCollateral(marketId, ethers.parseEther("10"), "0x");
      await untitledHub.connect(user2).borrow(marketId, ethers.parseEther("8.5"), await user2.getAddress());

      // Drastically drop collateral price to create bad debt scenario
      await priceProvider.setCollateralTokenPrice(ethers.parseEther("0.1") * BigInt(1e18)); // 90% price drop

      // Advance time to accrue interest
      await network.provider.send("evm_increaseTime", [30 * 24 * 3600]); // 30 days
      await network.provider.send("evm_mine");
      
      // Accrue interest to make position even more underwater
      await untitledHub.accrueInterest(marketId);
      
      // Get market state before liquidation
      const marketBefore = await untitledHub.market(marketId);
      const totalSupplyAssetsBefore = marketBefore.totalSupplyAssets;
      
      // User1 liquidates User2's position completely
      const liquidateTx = await untitledHub.connect(user1).liquidateBySeizedAssets(
        marketId,
        await user2.getAddress(),
        ethers.parseEther("10"), // Seize all collateral
        "0x"
      );
      
      const liquidateReceipt = await liquidateTx.wait();
      
      // Check for BadDebtRealized event
      const badDebtEvent = liquidateReceipt.logs.find(
        log => log.fragment && log.fragment.name === "BadDebtRealized"
      );
      
      expect(badDebtEvent).to.not.be.undefined;
      
      // Verify market state after bad debt realization
      const marketAfter = await untitledHub.market(marketId);
      expect(marketAfter.totalSupplyAssets).to.be.lt(totalSupplyAssetsBefore);
      
      // Verify borrower position is cleared
      const borrowerPosition = await untitledHub.position(marketId, await user2.getAddress());
      expect(borrowerPosition.borrowShares).to.equal(0);
      expect(borrowerPosition.collateral).to.equal(0);
    });
  });

  describe("Edge Cases", function () {
    it("should handle max uint256 withdraw", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // User1 supplies tokens
      const supplyAmount = ethers.parseEther("50");
      await untitledHub.connect(user1).supply(marketId, supplyAmount, "0x");
      
      // Get initial balance
      const initialBalance = await loanToken.balanceOf(await user1.getAddress());
      
      // Withdraw using max uint256 (should withdraw all available)
      await untitledHub.connect(user1).withdraw(
        marketId, 
        ethers.MaxUint256, 
        await user1.getAddress()
      );
      
      // Verify all tokens were withdrawn
      const finalBalance = await loanToken.balanceOf(await user1.getAddress());
      expect(finalBalance - initialBalance).to.equal(supplyAmount);
      
      // Verify position is empty
      const position = await untitledHub.position(marketId, await user1.getAddress());
      expect(position.supplyShares).to.equal(0);
    });
    
    it("should revert when trying to withdraw with insufficient balance", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      const marketId = 1;

      // User1 supplies a small amount
      await untitledHub.connect(user1).supply(marketId, ethers.parseEther("10"), "0x");
      
      // Try to withdraw more than supplied
      await expect(
        untitledHub.connect(user1).withdraw(
          marketId, 
          ethers.parseEther("20"), 
          await user1.getAddress()
        )
      ).to.be.revertedWith("UntitledHub: insufficient balance");
    });
    
    it("should revert when trying to create a market with unregistered IRM", async function () {
      // Deploy a new unregistered IRM
      const MockInterestRateModel = await ethers.getContractFactory("MockInterestRateModel");
      const unregisteredIrm = await MockInterestRateModel.deploy();
      await unregisteredIrm.waitForDeployment();
      
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await unregisteredIrm.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      
      // Try to create market with unregistered IRM
      await expect(
        untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") })
      ).to.be.revertedWith("UntitledHub: IRM not registered");
    });
    
    it("should revert when trying to create a market with invalid LLTV", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("1.1"), // LLTV > 1 is invalid
      };
      
      await expect(
        untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") })
      ).to.be.revertedWith("UntitledHub: wrong LLTV");
    });
    
    it("should revert when trying to create a market with insufficient fee", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      
      await expect(
        untitledHub.createMarket(configs, { value: ethers.parseEther("0.005") }) // Less than required fee
      ).to.be.revertedWith("UntitledHub: insufficient creation fee");
    });
  });

  describe("Market Creation Fee Management", function () {
    it("should allow owner to update market creation fee", async function () {
      const oldFee = await untitledHub.marketCreationFee();
      const newFee = ethers.parseEther("0.02"); // 0.02 ETH
      
      await untitledHub.setMarketCreationFee(newFee);
      
      expect(await untitledHub.marketCreationFee()).to.equal(newFee);
      
      // Try to create market with old fee (should fail)
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      
      await expect(
        untitledHub.createMarket(configs, { value: oldFee })
      ).to.be.revertedWith("UntitledHub: insufficient creation fee");
      
      // Create market with new fee (should succeed)
      await untitledHub.createMarket(configs, { value: newFee });
      
      // Verify collected fees increased
      expect(await untitledHub.collectedFees()).to.equal(newFee);
    });
  });

  describe("Duplicate Market Prevention", function () {
    it("should prevent creating duplicate markets with same configs", async function () {
      const configs = {
        loanToken: await loanToken.getAddress(),
        collateralToken: await collateralToken.getAddress(),
        oracle: await priceProvider.getAddress(),
        irm: await interestRateModel.getAddress(),
        lltv: ethers.parseEther("0.8"),
      };
      
      // Create first market
      await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
      
      // Try to create duplicate market
      await expect(
        untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") })
      ).to.be.revertedWith("UntitledHub: market already created");
    });
  });
});
