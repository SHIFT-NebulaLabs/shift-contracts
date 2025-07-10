# Shift Contracts

This repository contains the smart contracts powering the Shift protocol, developed and maintained by NebulaLabs. All contracts are written in Solidity and utilize [Foundry](https://book.getfoundry.sh/) for development, testing, and deployment.

---

## Overview

Shift aims to deliver robust, secure, and efficient smart contracts for decentralized applications. This repo is structured for clarity, reproducibility, and ease of use for both contributors and integrators.

- **Language**: Solidity
- **Toolkit**: Foundry
- **Deployment**: On-chain & simulation scripts included

🔗 **[Shift Documentation](https://nebulalabs-organization.gitbook.io/shift/)**

---

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed (`forge`)
- A configured `.env` file with relevant environment variables (RPC endpoints, API keys, etc.)

### Environment Setup

```sh
source .env
```

---

## 🛠️ Core Commands

Replace `<Filename>` and environment variables as needed for your use-case.

**📦 Build Contracts**
```sh
forge build
```

**🧹 Clean Build Artifacts**
```sh
forge clean
```

**🛡️ Test Coverage**
```sh
forge coverage
```

---

## ⚙️ Script Execution

**Local Simulation**
```sh
forge script script/<Filename>.s.sol:<DeployFunction>
```

**Local On-chain Simulation**
```sh
forge script script/<Filename>.s.sol:<DeployFunction> --rpc-url $RPC_URL_TEST
```

**Real On-chain Deployment & Verification**
```sh
forge script script/<Filename>.s.sol:<DeployFunction> \
  --rpc-url $RPC_URL \
  --interactives 1 \
  --broadcast \
  --verifier etherscan \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --verify
```

---

## 🧪 Testing

**Run All Tests**
```sh
forge test
```

**Medium Verbosity**
```sh
forge test -vv
```

**Maximum Verbosity**
```sh
forge test -vvvv
```

**Specific Test File**
```sh
forge test --match-path test/<TestFile>.t.sol
```

---

## 🤝 Contributing

Please review our documentation for architectural details, contribution guidelines, and FAQs:  
🔗 [Shift Documentation](https://nebulalabs-organization.gitbook.io/shift/)

If you encounter issues or have feature requests, feel free to open an issue or join our community!

---