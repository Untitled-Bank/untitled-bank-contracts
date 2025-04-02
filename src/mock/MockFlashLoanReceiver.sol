// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/IUntitledHubCallbacks.sol";
import "../interfaces/IUntitledHub.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFlashLoanReceiver is IUntitledHubFlashLoanCallback {
    address public hub;
    
    constructor(address hubAddress) {
        hub = hubAddress;
    }
    
    function executeFlashLoan(address token, uint256 assets) external {
        // Calculate the fee that will need to be repaid
        uint256 fee = IUntitledHub(hub).flashLoanFeeRate() * assets / 1e18;
        uint256 totalRepayment = assets + fee;
        
        // Approve the hub to take the tokens before the flash loan
        ERC20(token).approve(hub, totalRepayment);
        
        // Execute the flash loan
        IUntitledHub(hub).flashLoan(token, assets, "0x");
    }

    function onUntitledHubFlashLoan(uint256 assets, bytes calldata data) external override {
        // This callback is called during the flash loan        
    }
}