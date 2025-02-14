// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./Bank.sol";

contract BankFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    mapping(address => bool) public isBank;
    address[] public banks;
    address public bankImplementation;
    UntitledHub public untitledHub;
    
    event BankCreated(address bank, address asset, string name, string symbol);
    event BankImplementationUpdated(address oldImplementation, address newImplementation);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _bankImplementation, address _untitledHub) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        
        bankImplementation = _bankImplementation;
        untitledHub = UntitledHub(_untitledHub);
    }

    function createBank(
        IERC20 asset,
        string memory name,
        string memory symbol,
        uint256 fee,
        address feeRecipient,
        uint32 minDelay,
        address initialAdmin,
        IBank.BankType bankType
    ) external returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            Bank.initialize.selector,
            asset,
            name,
            symbol,
            untitledHub,
            fee,
            feeRecipient,
            minDelay,
            initialAdmin,
            bankType
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            bankImplementation,
            initData
        );

        address newBank = address(proxy);
        isBank[newBank] = true;
        banks.push(newBank);

        emit BankCreated(address(proxy), address(asset), name, symbol);
        return address(proxy);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getBankCount() external view returns (uint256) {
        return banks.length;
    }

    function getBankAt(uint256 index) external view returns (address) {
        require(index < banks.length, "Index out of bounds");
        return banks[index];
    }

    function isBankCreatedByFactory(address bank) external view returns (bool) {
        return isBank[bank];
    }

    function updateBankImplementation(address newImplementation) external onlyOwner {
        address oldImplementation = bankImplementation;
        bankImplementation = newImplementation;
        emit BankImplementationUpdated(oldImplementation, newImplementation);
    }
}
