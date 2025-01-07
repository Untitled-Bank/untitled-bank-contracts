// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/CoreBank.sol";
import "../src/core/CoreBankFactory.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployCoreBankFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy CoreBank implementation
        CoreBank coreBankImpl = new CoreBank();
        console.log("CoreBank implementation deployed at:", address(coreBankImpl));

        // Deploy CoreBankFactory implementation
        CoreBankFactory coreBankFactoryImpl = new CoreBankFactory();
    
        bytes memory initData = abi.encodeWithSelector(
            CoreBankFactory.initialize.selector,
            address(coreBankImpl)
        );

        // Deploy CoreBankFactory proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(coreBankFactoryImpl),
            initData
        );
        console.log("CoreBankFactory proxy deployed at:", address(proxy));

        vm.stopBroadcast();

        // Output verification commands to console
        console.log("\n=== To verify the contracts, run the following commands ===\n");
        
        // CoreBank implementation verification
        console.log("1. Verify CoreBank implementation:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(coreBankImpl)),
                " src/core/CoreBank.sol:CoreBank",
                " --verifier-url https://soneium-minato.blockscout.com/api/",
                " --verifier blockscout",
                " --optimizer-runs 200",
                " --via-ir"
            )
        );

        // CoreBankFactory implementation verification
        console.log("\n2. Verify CoreBankFactory implementation:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(coreBankFactoryImpl)),
                " src/core/CoreBankFactory.sol:CoreBankFactory",
                " --verifier-url https://soneium-minato.blockscout.com/api/",
                " --verifier blockscout",
                " --optimizer-runs 200",
                " --via-ir"
            )
        );

        // CoreBankFactory proxy verification
        console.log("\n3. Verify CoreBankFactory proxy:");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(proxy)),
                " @openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy",
                " --verifier-url https://soneium-minato.blockscout.com/api/",
                " --verifier blockscout",
                " --constructor-args $(cast abi-encode 'constructor(address,bytes)' ",
                vm.toString(address(coreBankFactoryImpl)),
                " $(cast abi-encode 'initialize(address)' ",
                vm.toString(address(coreBankImpl)),
                "))",
                " --optimizer-runs 200",
                " --via-ir"
            )
        );
        
        console.log("\n=====================================================\n");
    }
}