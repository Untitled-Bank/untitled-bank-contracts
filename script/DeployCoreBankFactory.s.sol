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
    }
}