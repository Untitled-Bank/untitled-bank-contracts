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
