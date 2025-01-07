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

        // Output verification commands to console
        console.log("\n=== To verify the contracts, run the following commands ===\n");
        
        // Bank implementation verification
        console.log("1. Verify Bank implementation:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(bankImpl)),
                " src/core/Bank.sol:Bank",
                " --verifier-url https://soneium-minato.blockscout.com/api/",
                " --verifier blockscout",
                " --optimizer-runs 200",
                " --via-ir"
            )
        );

        // BankFactory implementation verification
        console.log("\n2. Verify BankFactory implementation:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(bankFactoryImpl)),
                " src/core/BankFactory.sol:BankFactory",
                " --verifier-url https://soneium-minato.blockscout.com/api/",
                " --verifier blockscout",
                " --optimizer-runs 200",
                " --via-ir"
            )
        );

        // BankFactory proxy verification
        console.log("\n3. Verify BankFactory proxy:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(proxy)),
                " @openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
                " --verifier-url https://soneium-minato.blockscout.com/api/",
                " --verifier blockscout",
                " --constructor-args $(cast abi-encode 'constructor(address,bytes)' ",
                vm.toString(address(bankFactoryImpl)),
                " $(cast abi-encode 'initialize(address,address)' ",
                vm.toString(address(bankImpl)),
                " ",
                vm.toString(untitledHub),
                "))",
                " --optimizer-runs 200",
                " --via-ir"
            )
        );
        
        console.log("\n=====================================================\n");
    }
}