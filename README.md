## Untitled Bank Contracts

## Contracts
| Contract | # Functions | Description |
|----------|------------|-------------|
| UntitledHub | 75 | Core lending protocol contract that manages lending markets. Handles market creation, supply/borrow operations, collateral management, liquidations, and interest accrual. Acts as the primary lending engine. |
| BankFactory | 36 | Factory contract for deploying new Bank instances. Manages bank creation, implementation upgrades, and maintains a registry of all created banks. |
| Bank | 194 | ERC4626-compliant vault that allocates assets across multiple UntitledHub markets. Manages market allocations, fee collection, and provides yield generation through lending. Can be public or private (whitelisted). |
| BankActions | 5 | Library containing Bank functionality for market management, including adding/removing markets, updating allocations, and rebalancing assets across markets. |
| CoreBankFactory | 37 | Factory contract for deploying new CoreBank instances. Similar to BankFactory but specifically for CoreBank deployment and management. |
| CoreBank | 152 | ERC4626-compliant aggregator vault that allocates assets across multiple Banks. Acts as a "fund of funds" by managing allocations across different Bank strategies. |

## Build & Test

### Requirements
- Forge v1.0.0 (use `foundryup` to upgrade if needed)

### Commands

```bash
forge clean
forge build
forge test
```
