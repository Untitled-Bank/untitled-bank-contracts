// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/core/UntitledHub.sol";

contract DeployUntitledHub is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy UntitledHub with deployer as owner
        UntitledHub hub = new UntitledHub(msg.sender);
        console.log("UntitledHub deployed at:", address(hub));

        vm.stopBroadcast();
    }
}