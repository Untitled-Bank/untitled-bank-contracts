// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/UntitledHub.sol";

contract DeployUntitledHub is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.rememberKey(deployerPrivateKey);
        address deployer = vm.rememberKey(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy UntitledHub with deployer as owner
        UntitledHub hub = new UntitledHub(deployer);
        console.log("UntitledHub deployed at:", address(hub));
        console.log("Deployer address:", deployer);

        vm.stopBroadcast();

        // Output verification command to console
        console.log("\n=== To verify the contract, run the following command ===\n");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(hub)),
                " src/core/UntitledHub.sol:UntitledHub",
                " --verifier-url https://soneium-minato.blockscout.com/api/",
                " --verifier blockscout",
                " --constructor-args $(cast abi-encode 'constructor(address)' ",
                vm.toString(deployer),
                ")",
                " --optimizer-runs 200",
                " --via-ir"
            )
        );
        console.log("\n=====================================================\n");
    }
}