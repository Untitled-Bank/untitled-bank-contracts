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

// Helper contract for testing all callbacks
contract MockCallbackReceiver is 
    IUntitledHubSupplyCallback,
    IUntitledHubRepayCallback,
    IUntitledHubSupplyCollateralCallback,
    IUntitledHubLiquidateCallback,
    IUntitledHubFlashLoanCallback 
{
    address public hub;
    address public loanToken;
    address public collateralToken;
    
    bool public supplyCallbackCalled;
    bool public repayCallbackCalled;
    bool public supplyCollateralCallbackCalled;
    bool public liquidateCallbackCalled;
    bool public flashLoanCallbackCalled;

    constructor(address _hub, address _loanToken, address _collateralToken) {
        hub = _hub;
        loanToken = _loanToken;
        collateralToken = _collateralToken;
    }

    function onUntitledHubSupply(uint256 assets, bytes calldata) external {
        supplyCallbackCalled = true;
        IERC20(loanToken).approve(hub, assets);
    }

    function onUntitledHubRepay(uint256 assets, bytes calldata) external {
        repayCallbackCalled = true;
        IERC20(loanToken).approve(hub, assets);
    }

    function onUntitledHubSupplyCollateral(uint256 assets, bytes calldata) external {
        supplyCollateralCallbackCalled = true;
        IERC20(collateralToken).approve(hub, assets);
    }

    function onUntitledHubLiquidate(uint256 assets, bytes calldata) external {
        liquidateCallbackCalled = true;
        IERC20(loanToken).approve(hub, assets);
    }

    function onUntitledHubFlashLoan(uint256 assets, bytes calldata) external {
        flashLoanCallbackCalled = true;
        IERC20(loanToken).approve(hub, assets);
    }
}

contract UntitledHubCallbackTest is Test {
    receive() external payable {}

    UntitledHub public untitledHub;
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    MockPriceProvider public priceProvider;
    MockInterestRateModel public interestRateModel;

    address public owner;
    address public user1;
    address public user2;

    uint256 public constant INITIAL_BALANCE = 1000e18;

    uint256 public marketId;

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

        // Create a market
        MarketConfigs memory configs = MarketConfigs({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(priceProvider),
            irm: address(interestRateModel),
            lltv: 0.8e18 // 80% LLTV
        });

        marketId = untitledHub.createMarket{value: 0.01 ether}(configs);
    }

    function testSupplyCallback() public {
        MockCallbackReceiver callbackReceiver = new MockCallbackReceiver(
            address(untitledHub),
            address(loanToken),
            address(collateralToken)
        );
        
        // Mint tokens to callback receiver
        loanToken.mint(address(callbackReceiver), 100e18);

        bytes memory data = "supply data";
        vm.prank(address(callbackReceiver));
        untitledHub.supply(marketId, 50e18, data);

        assertTrue(callbackReceiver.supplyCallbackCalled(), "Supply callback not called");
    }

    function testRepayCallback() public {
        MockCallbackReceiver callbackReceiver = new MockCallbackReceiver(
            address(untitledHub),
            address(loanToken),
            address(collateralToken)
        );

        // Add liquidity
        vm.startPrank(user2);
        untitledHub.supply(marketId, 1000e18, "");
        vm.stopPrank();

        // Setup initial state for repayment
        vm.startPrank(user1);
        untitledHub.supplyCollateral(marketId, 100e18, "");
        untitledHub.borrow(marketId, 50e18, user1);
        vm.stopPrank();

        // Mint tokens to callback receiver for repayment
        loanToken.mint(address(callbackReceiver), 100e18);

        bytes memory data = "repay data";
        vm.prank(address(callbackReceiver));
        untitledHub.repay(marketId, 25e18, data);

        assertTrue(callbackReceiver.repayCallbackCalled(), "Repay callback not called");
    }

    function testSupplyCollateralCallback() public {
        MockCallbackReceiver callbackReceiver = new MockCallbackReceiver(
            address(untitledHub),
            address(loanToken),
            address(collateralToken)
        );
        
        // Mint collateral tokens to callback receiver
        collateralToken.mint(address(callbackReceiver), 100e18);

        bytes memory data = "supply collateral data";
        vm.prank(address(callbackReceiver));
        untitledHub.supplyCollateral(marketId, 50e18, data);

        assertTrue(callbackReceiver.supplyCollateralCallbackCalled(), "Supply collateral callback not called");
    }

    function testLiquidateCallback() public {
        MockCallbackReceiver callbackReceiver = new MockCallbackReceiver(
            address(untitledHub),
            address(loanToken),
            address(collateralToken)
        );

        // Add liquidity for liquidation
        vm.startPrank(user2);
        untitledHub.supply(marketId, 1000e18, "");
        vm.stopPrank();

        // Setup position for liquidation
        vm.startPrank(user1);
        untitledHub.supplyCollateral(marketId, 100e18, "");
        untitledHub.borrow(marketId, 50e18, user1);
        vm.stopPrank();

        // Change price to make position liquidatable
        priceProvider.setCollateralTokenPrice(0.5e36); // Drop price by 50%

        // Mint tokens to callback receiver for liquidation
        loanToken.mint(address(callbackReceiver), 100e18);

        bytes memory data = "liquidate data";
        vm.prank(address(callbackReceiver));
        untitledHub.liquidateBySeizedAssets(marketId, user1, 25e18, data);

        assertTrue(callbackReceiver.liquidateCallbackCalled(), "Liquidate callback not called");
    }

    function testFlashLoanCallback() public {
        MockCallbackReceiver callbackReceiver = new MockCallbackReceiver(
            address(untitledHub),
            address(loanToken),
            address(collateralToken)
        );
        
        // Mint tokens to flash loan receiver for repayment
        loanToken.mint(address(callbackReceiver), 100e18);
        loanToken.mint(address(untitledHub), 100e18);

        bytes memory data = "flash loan data";
        vm.prank(address(callbackReceiver));
        untitledHub.flashLoan(address(loanToken), 50e18, data);

        assertTrue(callbackReceiver.flashLoanCallbackCalled(), "Flash loan callback not called");
    }
}
