## Untitled Bank Contracts

**Untitled Bank** is a permissionless, and modular lending platform designed to provide a seamless and inclusive experience for all users. Our mission is to unlock the potential of underutilized assets by leveraging our unique Aggregated and Layered Bank architecture. Untitled Bank simplifies asset management and lending operations, making decentralized finance (DeFi) more accessible to both novice and experienced users.

---

### What is Markets?
At Untitled Bank, anyone can create a Market by leveraging the platform's modular components. Each Market matches lenders, borrowers, and Bank Operators in a permissionless and overcollateralized manner. Markets are fully customizable with components like Interest Rate Models (IRM), Oracles, and asset selection, ensuring flexibility and optimization for various financial strategies.

### What is Banks?
At Untitled Bank, anyone can create a Bank in the form of an ERC-4626 vault. Each Bank functions as an independent lending vault, holding a single loan asset and serving specific lending markets within the platform.

Banks are created and managed by Bank Operators—which can include individuals, financial institutions, DAOs, or project treasuries. Untitled Bank’s permissionless design allows anyone to become a Bank Operator, fostering diverse participation.

---

## Contracts
| Contract | # Functions | Description |
|----------|------------|-------------|
| UntitledHub | 75 | Core lending protocol contract that manages lending markets. Handles market creation, supply/borrow operations, collateral management, liquidations, and interest accrual. Acts as the primary lending engine. |
| BankFactory | 36 | Factory contract for deploying new Bank instances. Manages bank creation, implementation upgrades, and maintains a registry of all created banks. |
| Bank | 194 | ERC4626-compliant vault that allocates assets across multiple UntitledHub markets. Manages market allocations, fee collection, and provides yield generation through lending. Can be public or private (whitelisted). |
| BankActions | 5 | Library containing Bank functionality for market management, including adding/removing markets, updating allocations, and rebalancing assets across markets. |
| CoreBankFactory | 37 | Factory contract for deploying new CoreBank instances. Similar to BankFactory but specifically for CoreBank deployment and management. |
| CoreBank | 152 | ERC4626-compliant aggregator vault that allocates assets across multiple Banks. Acts as a "fund of funds" by managing allocations across different Bank strategies. |

---

## Build & Test

### Requirements
- Forge v1.0.0 (use `foundryup` to upgrade if needed)

### Commands

```bash
forge clean
forge build
forge test
```

### Test Coverage

To generate test coverage, run the following command:

```bash
npx hardhat clean & npx hardhat coverage
```


#### Current Coverage Results

| File | % Funcs | % Lines |
|------|---------|---------|
| core/Bank.sol | 96.97 | 99.11 |
| core/BankFactory.sol | 75 | 94.74 |
| core/BankInternal.sol | 92.31 | 84.47 |
| core/BankStorage.sol | 100 | 100 |
| core/CoreBank.sol | 93.75 | 80.33 |
| core/CoreBankFactory.sol | 66.67 | 89.47 |
| core/CoreBankInternal.sol | 100 | 83.72 |
| core/CoreBankStorage.sol | 100 | 100 |
| core/UntitledHub.sol | 87.5 | 86.67 |
| core/UntitledHubBase.sol | 96 | 92.34 |
| core/UntitledHubOperation.sol | 100 | 100 |
| core/UntitledHubStorage.sol | 100 | 100 |
| interfaces/* | 100 | 100 |
| libraries/BankActions.sol | 80 | 69.23 |
| libraries/ConstantsLib.sol | 100 | 100 |
| libraries/Timelock.sol | 80 | 95.45 |
| libraries/UtilsLib.sol | 100 | 100 |
| libraries/math/SharesMath.sol | 100 | 100 |
| libraries/math/WadMath.sol | 85.71 | 90 |
| **All files** | **90.91** | **87.92** |