// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/Bank.sol";
import "../src/core/BankFactory.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployBankFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address untitledHub = vm.envAddress("UNTITLED_HUB_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Bank implementation
        Bank bankImpl = new Bank();
        console.log("Bank implementation deployed at:", address(bankImpl));

        // Deploy BankFactory implementation
        BankFactory bankFactoryImpl = new BankFactory();
    
        bytes memory initData = abi.encodeWithSelector(
            BankFactory.initialize.selector,
            address(bankImpl),
            untitledHub
        );

        // Deploy BankFactory proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(bankFactoryImpl),
            initData
        );
        console.log("BankFactory proxy deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}