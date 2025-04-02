import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Contract, Signer } from "ethers";

describe("UntitledHubOperation", function () {
  let untitledHub: Contract;
  let untitledHubOperation: Contract;
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

    // Deploy UntitledHubOperation
    const UntitledHubOperation = await ethers.getContractFactory("UntitledHubOperation");
    untitledHubOperation = await UntitledHubOperation.deploy(await untitledHub.getAddress());
    await untitledHubOperation.waitForDeployment();

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

    // Create a market for testing
    const configs = {
      loanToken: await loanToken.getAddress(),
      collateralToken: await collateralToken.getAddress(),
      oracle: await priceProvider.getAddress(),
      irm: await interestRateModel.getAddress(),
      lltv: ethers.parseEther("0.8"),
    };

    await untitledHub.createMarket(configs, { value: ethers.parseEther("0.01") });
    
    // User1 supplies 100 tokens to the market
    await untitledHub.connect(user1).supply(1, ethers.parseEther("100"), "0x");
  });

  describe("supplyCollateralAndBorrow", function () {
    it("should revert when permission is not granted", async function () {
      // No permission granted yet
      await expect(
        untitledHubOperation.connect(user2).supplyCollateralAndBorrow(
          1,
          ethers.parseEther("50"),
          ethers.parseEther("30"),
          await collateralToken.getAddress(),
          await user2.getAddress()
        )
      ).to.be.revertedWith("Permission not granted");
    });

    it("should supply collateral and borrow in a single transaction", async function () {
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Approve the operation contract to spend user2's collateral tokens
      await collateralToken.connect(user2).approve(
        await untitledHubOperation.getAddress(),
        ethers.parseEther("50")
      );
      
      // Get initial balances
      const initialLoanBalance = await loanToken.balanceOf(await user2.getAddress());
      const initialCollateralBalance = await collateralToken.balanceOf(await user2.getAddress());
      
      // Execute the combined operation
      await untitledHubOperation.connect(user2).supplyCollateralAndBorrow(
        1,
        ethers.parseEther("50"),
        ethers.parseEther("30"),
        await collateralToken.getAddress(),
        await user2.getAddress()
      );
      
      // Check final balances
      const finalLoanBalance = await loanToken.balanceOf(await user2.getAddress());
      const finalCollateralBalance = await collateralToken.balanceOf(await user2.getAddress());
      
      // Verify collateral was taken and loan was received
      expect(initialCollateralBalance - finalCollateralBalance).to.equal(ethers.parseEther("50"));
      expect(finalLoanBalance - initialLoanBalance).to.equal(ethers.parseEther("30"));
      
      // Verify position in the hub
      const position = await untitledHub.position(1, await user2.getAddress());
      expect(position.collateral).to.equal(ethers.parseEther("50"));
      expect(position.borrowShares).to.be.gt(0);
    });

    it("should only supply collateral without borrowing", async function () {
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Approve the operation contract to spend user2's collateral tokens
      await collateralToken.connect(user2).approve(
        await untitledHubOperation.getAddress(),
        ethers.parseEther("50")
      );
      
      // Execute the operation with zero borrow amount
      await untitledHubOperation.connect(user2).supplyCollateralAndBorrow(
        1,
        ethers.parseEther("50"),
        0,
        await collateralToken.getAddress(),
        await user2.getAddress()
      );
      
      // Verify position in the hub
      const position = await untitledHub.position(1, await user2.getAddress());
      expect(position.collateral).to.equal(ethers.parseEther("50"));
      expect(position.borrowShares).to.equal(0);
    });

    it("should only borrow without supplying additional collateral", async function () {
      // First supply some collateral directly
      await untitledHub.connect(user2).supplyCollateral(1, ethers.parseEther("50"), "0x");
      
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Execute the operation with zero collateral amount
      await untitledHubOperation.connect(user2).supplyCollateralAndBorrow(
        1,
        0,
        ethers.parseEther("30"),
        await collateralToken.getAddress(),
        await user2.getAddress()
      );
      
      // Verify position in the hub
      const position = await untitledHub.position(1, await user2.getAddress());
      expect(position.collateral).to.equal(ethers.parseEther("50"));
      expect(position.borrowShares).to.be.gt(0);
    });

    it("should revert when trying to use invalid collateral token", async function () {
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Deploy a different token
      const MockERC20 = await ethers.getContractFactory("MockERC20");
      const wrongToken = await MockERC20.deploy("Wrong Token", "WRONG");
      await wrongToken.waitForDeployment();
      
      // Try to use the wrong token
      await expect(
        untitledHubOperation.connect(user2).supplyCollateralAndBorrow(
          1,
          ethers.parseEther("50"),
          ethers.parseEther("30"),
          await wrongToken.getAddress(),
          await user2.getAddress()
        )
      ).to.be.revertedWith("Invalid collateral token");
    });
  });

  describe("repayAndWithdrawCollateral", function () {
    beforeEach(async function () {
      // Setup: User2 supplies collateral and borrows
      await untitledHub.connect(user2).supplyCollateral(1, ethers.parseEther("50"), "0x");
      await untitledHub.connect(user2).borrow(1, ethers.parseEther("30"), await user2.getAddress());
    });

    it("should revert when permission is not granted", async function () {
      // No permission granted yet
      await expect(
        untitledHubOperation.connect(user2).repayAndWithdrawCollateral(
          1,
          ethers.parseEther("20"),
          ethers.parseEther("10"),
          await loanToken.getAddress(),
          await user2.getAddress()
        )
      ).to.be.revertedWith("Permission not granted");
    });

    it("should repay loan and withdraw collateral in a single transaction", async function () {
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Approve the operation contract to spend user2's loan tokens for repayment
      await loanToken.connect(user2).approve(
        await untitledHubOperation.getAddress(),
        ethers.parseEther("20")
      );
      
      // Get initial balances
      const initialLoanBalance = await loanToken.balanceOf(await user2.getAddress());
      const initialCollateralBalance = await collateralToken.balanceOf(await user2.getAddress());
      
      const beforePosition = await untitledHub.position(1, await user2.getAddress());
      expect(beforePosition.collateral).to.equal(ethers.parseEther("50"));
      const beforeMarket = await untitledHub.market(1);
      const beforeBorrowedAmount = beforePosition.borrowShares * beforeMarket.totalBorrowAssets / beforeMarket.totalBorrowShares;

      // Execute the combined operation
      await untitledHubOperation.connect(user2).repayAndWithdrawCollateral(
        1,
        ethers.parseEther("20"),
        ethers.parseEther("10"),
        await loanToken.getAddress(),
        await user2.getAddress()
      );
      
      // Check final balances
      const finalLoanBalance = await loanToken.balanceOf(await user2.getAddress());
      const finalCollateralBalance = await collateralToken.balanceOf(await user2.getAddress());
      
      // Verify loan was repaid and collateral was received
      expect(initialLoanBalance - finalLoanBalance).to.equal(ethers.parseEther("20"));
      expect(finalCollateralBalance - initialCollateralBalance).to.equal(ethers.parseEther("10"));
      
      // Verify position in the hub
      const market = await untitledHub.market(1);
      const position = await untitledHub.position(1, await user2.getAddress());
      const borrowedAmount = position.borrowShares * market.totalBorrowAssets / market.totalBorrowShares;
      expect(position.collateral).to.equal(ethers.parseEther("40")); // 50 - 10
      expect(borrowedAmount).to.be.lt(beforeBorrowedAmount); // Less than initial borrow
    });

    it("should only repay without withdrawing collateral", async function () {
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Approve the operation contract to spend user2's loan tokens
      await loanToken.connect(user2).approve(
        await untitledHubOperation.getAddress(),
        ethers.parseEther("20")
      );

      const beforePosition = await untitledHub.position(1, await user2.getAddress());
      expect(beforePosition.collateral).to.equal(ethers.parseEther("50"));
      const beforeMarket = await untitledHub.market(1);
      const beforeBorrowedAmount = beforePosition.borrowShares * beforeMarket.totalBorrowAssets / beforeMarket.totalBorrowShares;

      // Execute the operation with zero withdraw amount
      await untitledHubOperation.connect(user2).repayAndWithdrawCollateral(
        1,
        ethers.parseEther("20"),
        0,
        await loanToken.getAddress(),
        await user2.getAddress()
      );
      
      // Verify position in the hub
      const position = await untitledHub.position(1, await user2.getAddress());
      const market = await untitledHub.market(1);
      const borrowedAmount = position.borrowShares * market.totalBorrowAssets / market.totalBorrowShares;
      expect(position.collateral).to.equal(ethers.parseEther("50")); // Unchanged
      expect(borrowedAmount).to.be.lt(beforeBorrowedAmount); // Less than initial borrow
    });

    it("should only withdraw collateral without repaying", async function () {
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Execute the operation with zero repay amount
      await untitledHubOperation.connect(user2).repayAndWithdrawCollateral(
        1,
        0,
        ethers.parseEther("10"),
        await loanToken.getAddress(),
        await user2.getAddress()
      );
      
      // Verify position in the hub
      const position = await untitledHub.position(1, await user2.getAddress());
      expect(position.collateral).to.equal(ethers.parseEther("40")); // 50 - 10
      // Borrow shares remain unchanged
    });

    it("should repay the full loan amount when using max uint256", async function () {
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Approve the operation contract to spend user2's loan tokens
      await loanToken.connect(user2).approve(
        await untitledHubOperation.getAddress(),
        ethers.parseEther("40") // More than enough to cover the debt
      );
      
      // Execute the operation with max uint256 as repay amount
      await untitledHubOperation.connect(user2).repayAndWithdrawCollateral(
        1,
        ethers.MaxUint256,
        0,
        await loanToken.getAddress(),
        await user2.getAddress()
      );
      
      // Verify position in the hub - should have no more debt
      const position = await untitledHub.position(1, await user2.getAddress());
      expect(position.borrowShares).to.equal(0);
    });

    it("should refund excess tokens when repaying more than the debt", async function () {
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Approve the operation contract to spend user2's loan tokens
      await loanToken.connect(user2).approve(
        await untitledHubOperation.getAddress(),
        ethers.parseEther("40") // More than the debt
      );
      
      // Get initial balance
      const initialLoanBalance = await loanToken.balanceOf(await user2.getAddress());
      
      // Execute the operation with an amount higher than the debt
      await untitledHubOperation.connect(user2).repayAndWithdrawCollateral(
        1,
        ethers.parseEther("40"),
        0,
        await loanToken.getAddress(),
        await user2.getAddress()
      );
      
      // Check final balance
      const finalLoanBalance = await loanToken.balanceOf(await user2.getAddress());
      
      // Verify that less than 40 tokens were actually spent (only the debt amount)
      expect(initialLoanBalance - finalLoanBalance).to.be.lt(ethers.parseEther("40"));
      
      // Verify position in the hub - should have no more debt
      const position = await untitledHub.position(1, await user2.getAddress());
      expect(position.borrowShares).to.equal(0);
    });

    it("should revert when trying to use invalid loan token", async function () {
      // Grant permission to the operation contract
      await untitledHub.connect(user2).setGrantPermission(await untitledHubOperation.getAddress(), true);
      
      // Deploy a different token
      const MockERC20 = await ethers.getContractFactory("MockERC20");
      const wrongToken = await MockERC20.deploy("Wrong Token", "WRONG");
      await wrongToken.waitForDeployment();
      
      // Try to use the wrong token
      await expect(
        untitledHubOperation.connect(user2).repayAndWithdrawCollateral(
          1,
          ethers.parseEther("20"),
          ethers.parseEther("10"),
          await wrongToken.getAddress(),
          await user2.getAddress()
        )
      ).to.be.revertedWith("Invalid loan token");
    });
  });
});