# Shift Contracts

This repository contains the smart contracts powering the Shift protocol, developed and maintained by NebulaLabs. All contracts are written in Solidity and utilize [Foundry](https://book.getfoundry.sh/) for development, testing, and deployment.

---

## Table of Contents

- [Overview](#overview)
- [Security & Audit](#security--audit-on-going)
- [Smart Contract Technical Specification](#smart-contract-technical-specification)
  - [ShiftAccessControl.sol](#shiftaccesscontrolsol)
  - [ShiftManager.sol](#shiftmanagersol)
  - [ShiftTvlFeed.sol](#shifttvlfeedsol)
  - [ShiftVault.sol](#shiftvaultsol)
- [Getting Started](#-getting-started)
- [Core Commands](#-core-commands)
- [Script Execution](#-script-execution)
- [Testing](#-testing)
- [Contributing](#-contributing)
- [License](#license)

---

## Overview

Shift aims to deliver robust, secure, and efficient smart contracts for decentralized applications. This repo is structured for clarity, reproducibility, and ease of use for both contributors and integrators.

- **Language**: Solidity
- **Toolkit**: Foundry
- **Deployment**: On-chain & simulation scripts included

🔗 **[Shift Documentation](https://nebulalabs-organization.gitbook.io/shift/)**

---

## 🛡️ Security & Audit

Security is a top priority for the Shift protocol.  
The following contracts are currently undergoing a professional external security audit.

| Audit firm                                 | Report                                       | Year |
|--------------------------------------------|----------------------------------------------|------|
| [SB Security](https://www.sbsecurity.net/) | [Shift Protocol Security Review ](./audits/shift-sbsecurity-audit-2025.pdf)  | 2025 |

---

## 📄 Smart Contract Technical Specification

This section describes the core Solidity contracts found in `src/`, outlining their roles, main mechanisms, and how they interoperate to realize the Shift protocol.

### **ShiftAccessControl.sol**

Handles protocol-wide role-based access control by extending OpenZeppelin's `AccessControl`. It defines key roles such as `ORACLE_ROLE` and `EXECUTOR_ROLE`, enabling fine-grained permission management for protocol operations. The contract is initialized with an admin address, which receives the default admin role and can grant or revoke other roles. This ensures only authorized entities can manage sensitive protocol functions.

**Key Features:**
- Role management for protocol actors (Oracle, Executor, Admin).
- Foundation for secure access throughout all contracts.

---

### **ShiftManager.sol**

An abstract contract providing configurable protocol parameters and administrative controls. It manages fees (performance, maintenance, buffer), deposit limits, TVL caps, whitelisting, and pausing/unpausing the protocol. Only authorized admins can update these configurations. The contract validates input parameters to maintain protocol integrity and emits events on critical changes.

**Key Features:**
- Protocol fee configuration and conversion to 18-decimal fixed-point.
- Toggleable whitelisting mechanism for user access control.
- Emergency pause and release controls.
- Modular design for extension by vault contracts.

---

### **ShiftTvlFeed.sol**

Provides a secure, auditable feed of the protocol’s Total Value Locked (TVL). Designed for integration with the Shift vault, it maintains a historical record of TVL updates, each snapshotting value, timestamp, and supply. Only addresses with the Oracle role can update TVL data. The contract supports initialization, single or batched TVL updates, retrieval of historical data, and exposes TVL precision.

**Key Features:**
- Oracle-driven TVL updates with on-chain history.
- Data retrieval functions for analytics and vault logic.
- Initialization gating for safe deployment.

---

### **ShiftVault.sol**

Implements the core liquidity management logic for the Shift protocol, inheriting from **ShiftManager.sol**, `ERC20`, and `ReentrancyGuard`. It handles deposits, withdrawals, batch processing, fee calculation, and share price computation. Users interact via deposit and withdrawal requests, managed through time locks and batch states. Admins and Executors resolve batches, claim fees, and manage protocol liquidity. The contract ensures security via access modifiers, checks, and safe token transfer routines.

**Key Features:**
- Deposit and withdrawal management with batch processing and timelocks.
- ERC20 share token logic for vault participants.
- Automated performance and maintenance fee claiming.
- Buffer and resolver liquidity calculations for robust fund management.
- Secure interactions with the TVL feed and access control layers.

---

**Integration Notes:**
All contracts are designed for composability and security, leveraging OpenZeppelin standards and Foundry tooling. Each contract exposes clear interfaces for interaction, and administrative functions are protected by role-based access control.

For deeper architectural details, see the [Shift Documentation](https://nebulalabs-organization.gitbook.io/shift/).

---

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/introduction/installation) installed (`forge`)
- [Make](https://www.gnu.org/software/make/) installed (`make`)
- A configured `.env` file with relevant environment variables (RPC endpoints, API keys, etc.)

In this repo it uses `Make`, to find the specific commant see [Foundry](https://getfoundry.sh/forge/overview)

## 🛠️ Core Commands

**📦 Build Contracts**
```sh
make build
```

**🧹 Clean Build Artifacts**
```sh
make clean
```

## ⚙️ Script Execution

**Local Simulation**
```sh
make sim-deploy-local
```

**Local On-chain Simulation**
```sh
make sim-deploy-sepolia || make sim-deploy-arbitrum
```

**Real On-chain Deployment & Verification**
```sh
make deploy-sepolia || make deploy-arbitrum:
```

---

## 🧪 Testing

**Run All Tests**
```sh
make testing
```
---

## 🤝 Contributing

If you encounter issues or have feature requests, feel free to open an issue or join our community!

---

## License

This repository and its smart contracts are released under the **MIT License**.  
See [`LICENSE`](./LICENSE) for full details.

---