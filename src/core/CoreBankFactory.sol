// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./CoreBank.sol";

contract CoreBankFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    mapping(address => bool) public isCoreBank;
    address[] public coreBanks;
    address public coreBankImplementation;

    event CoreBankCreated(
        address indexed coreBank,
        address indexed asset,
        string name,
        string symbol,
        uint256 minDelay,
        address initialAdmin
    );

    event CoreBankImplementationUpdated(
        address indexed oldImplementation,
        address indexed newImplementation
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _coreBankImplementation) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        
        coreBankImplementation = _coreBankImplementation;
    }

    function createCoreBank(
        IERC20 asset,
        string memory name,
        string memory symbol,
        uint32 minDelay,
        address initialAdmin
    ) external onlyOwner returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            CoreBank.initialize.selector,
            asset,
            name,
            symbol,
            minDelay,
            initialAdmin
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            coreBankImplementation,
            initData
        );

        address newCoreBank = address(proxy);
        isCoreBank[newCoreBank] = true;
        coreBanks.push(newCoreBank);

        emit CoreBankCreated(newCoreBank, address(asset), name, symbol, minDelay, initialAdmin);
        return newCoreBank;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getCoreBankCount() external view returns (uint256) {
        return coreBanks.length;
    }

    function getCoreBankAt(uint256 index) external view returns (address) {
        require(index < coreBanks.length, "Index out of bounds");
        return coreBanks[index];
    }

    function isCoreBankCreatedByFactory(
        address coreBank
    ) external view returns (bool) {
        return isCoreBank[coreBank];
    }

    function setOwner(address newOwner) external onlyOwner {
        transferOwnership(newOwner);
    }

    function updateCoreBankImplementation(address newImplementation) external onlyOwner {
        address oldImplementation = coreBankImplementation;
        coreBankImplementation = newImplementation;
        emit CoreBankImplementationUpdated(oldImplementation, newImplementation);
    }
}
