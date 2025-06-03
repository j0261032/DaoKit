# 🏛️ DaoKit - Modular DAO Framework

> 🔧 Plug-and-play DAO contracts for the Stacks blockchain

## 📋 Overview

DaoKit is a comprehensive, modular DAO (Decentralized Autonomous Organization) framework built on Clarity for the Stacks blockchain. It provides a flexible foundation for creating and managing DAOs with customizable modules, token-based governance, and proposal management.

## ✨ Features

- 🗳️ **Token-based Voting**: Members vote with governance tokens
- 📝 **Proposal Management**: Create, vote on, and execute proposals
- 🔌 **Modular Architecture**: Add custom modules for extended functionality
- 👥 **Member Management**: Token distribution and delegation
- 🔐 **Permission System**: Fine-grained access control for modules
- ⏰ **Time-based Voting**: Configurable voting periods

## 🚀 Quick Start

### Prerequisites

- Clarinet installed
- Stacks wallet for testing

### Installation

```bash
git clone <your-repo>
cd daokit
clarinet check
```

### 🏗️ Basic Setup

1. **Initialize your DAO**:
```clarity
(contract-call? .DaoKit initialize-dao "MyDAO" u1000 u1440)
```

2. **Mint tokens to members**:
```clarity
(contract-call? .DaoKit mint-tokens 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u5000)
```

3. **Register a module**:
```clarity
(contract-call? .DaoKit register-module "treasury" 'ST1TREASURY... 'ST1ADMIN...)
```

## 📖 Usage Guide

### 🏛️ DAO Administration

**Initialize DAO**
```clarity
(initialize-dao "DAO Name" min-tokens-to-propose voting-duration-blocks)
```

**Mint Governance Tokens**
```clarity
(mint-tokens recipient-principal amount)
```

### 🔌 Module Management

**Register Module**
```clarity
(register-module "module-name" contract-principal admin-principal)
```

**Toggle Module Status**
```clarity
(toggle-module "module-name")
```

**Set Module Permissions**
```clarity
(set-module-permission "module-name" "permission-name" true)
```

### 📝 Proposal Lifecycle

**Create Proposal**
```clarity
(create-proposal "Proposal Title" "Detailed description" "target-module")
```

**Vote on Proposal**
```clarity
(vote proposal-id true) ;; true for yes, false for no
```

**Execute Proposal**
```clarity
(execute-proposal proposal-id)
```

### 💰 Token Operations

**Delegate Tokens**
```clarity
(delegate-tokens recipient-principal amount)
```

**Check Token Balance**
```clarity
(get-member-tokens member-principal)
```

## 🔍 Read-Only Functions

### 📊 DAO Information
- `(get-dao-info)` - Get DAO configuration
- `(get-proposal proposal-id)` - Get proposal details
- `(get-proposal-status proposal-id)` - Get voting status
- `(get-member-tokens principal)` - Get member's token balance
- `(get-module "name")` - Get module information
- `(has-module-permission "module" "permission")` - Check permissions

### ✅ Validation Functions
- `(can-vote proposal-id voter)` - Check if user can vote
- `(get-vote proposal-id voter)` - Get user's vote on proposal

## 🏗️ Architecture

### Core Components

1. **👥 Membership System**: Token-based membership with delegation
2. **🗳️ Governance Engine**: Proposal creation, voting, and execution
3. **🔌 Module Registry**: Pluggable components for extended functionality
4. **🔐 Permission Framework**: Role-based access control

### 📊 Data Structures

- **Proposals**: Title, description, voting period, results
- **Votes**: Member votes with token-weighted power
- **Modules**: External contracts with permissions
- **Members**: Token balances and delegation

## 🛠️ Development

### Testing
```bash
clarinet test
```

### Console Testing
```bash
clarinet console
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

MIT License - see LICENSE file for details

## 🆘 Support

- 📚 Documentation: Check the code comments
- 🐛 Issues: Open a GitHub issue
- 💬 Discussions: Use GitHub Discussions

---

