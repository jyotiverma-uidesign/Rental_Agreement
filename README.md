# Rental Agreement Smart Contract

A decentralized rental agreement system built on blockchain technology using Solidity and Hardhat framework.

## Project Description

The Rental Agreement Smart Contract is a blockchain-based solution that digitizes and automates traditional rental agreements between landlords and tenants. This system eliminates the need for intermediaries while providing transparency, security, and automated execution of rental terms.

The contract manages the entire rental lifecycle including agreement creation, rent payments, security deposits, late fees, and agreement termination. All transactions are recorded on the blockchain, ensuring immutable records and dispute resolution capabilities.

## Project Vision

Our vision is to revolutionize the rental industry by creating a trustless, transparent, and efficient system that:

- **Eliminates intermediaries** and reduces associated costs
- **Provides immutable records** of all rental transactions and agreements
- **Automates payment processing** and reduces manual intervention
- **Ensures fair dispute resolution** through transparent blockchain records
- **Enables global accessibility** to rental services without geographical barriers
- **Promotes financial inclusion** by providing decentralized rental solutions

## Key Features

### 🏠 **Agreement Management**
- Create comprehensive rental agreements with customizable terms
- Set monthly rent, security deposits, and lease duration
- Automatic agreement expiration handling
- Support for multiple concurrent agreements per user

### 💰 **Payment Processing**
- Automated rent collection with timestamp tracking
- Security deposit management with escrow functionality
- Late fee calculation and automatic application (5% penalty)
- Overpayment refund system

### 🔒 **Security & Access Control**
- Role-based access control (landlord/tenant permissions)
- Reentrancy protection for all financial transactions
- Input validation and error handling
- Emergency withdrawal functionality for contract owner

### 📊 **Transparency & Tracking**
- Real-time payment history and status tracking
- Agreement status monitoring (active/terminated)
- Rent due notifications and late payment detection
- Complete audit trail of all contract interactions

### 🔗 **Blockchain Integration**
- Deployed on Core Testnet 2 blockchain
- Gas-optimized contract design
- Event emission for off-chain tracking
- Cross-platform compatibility

## Future Scope

### 🚀 **Phase 1: Enhanced Features**
- **Multi-currency support** for international rentals
- **Fractional ownership** capabilities for property sharing
- **Insurance integration** for property damage coverage
- **Dispute resolution system** with arbitration mechanisms

### 🏗️ **Phase 2: Advanced Functionality**
- **IoT integration** for smart home automation and monitoring
- **Credit scoring system** based on rental payment history
- **Decentralized identity verification** for KYC compliance
- **Mobile application** for easy contract management

### 🌐 **Phase 3: Ecosystem Expansion**
- **Multi-chain deployment** for broader accessibility
- **Integration with real estate platforms** and property management systems
- **Governance token** for community-driven platform decisions
- **Rental marketplace** with property listing and discovery features

### 📈 **Phase 4: Enterprise Solutions**
- **Property management company** integration tools
- **Regulatory compliance** features for different jurisdictions
- **Analytics dashboard** for market insights and trends
- **API development** for third-party integrations

## Technical Architecture

- **Smart Contract**: Solidity ^0.8.19
- **Framework**: Hardhat
- **Network**: Core Testnet 2
- **Security**: OpenZeppelin contracts
- **Testing**: Comprehensive unit and integration tests

## Getting Started

### Prerequisites
- Node.js (v14 or higher)
- npm or yarn
- MetaMask or compatible wallet
- Core Testnet 2 tokens for deployment

### Installation

1. Clone the repository
```bash
git clone <repository-url>
cd rental-agreement
```

2. Install dependencies
```bash
npm install
```

3. Configure environment variables
```bash
cp .env.example .env
# Add your private key and API keys
```

4. Compile contracts
```bash
npm run compile
```

5. Deploy to Core Testnet 2
```bash
npm run deploy
```

### Testing

Run the test suite:
```bash
npm test
```

## Contract Functions

### Core Functions

1. **createAgreement()**
   - Creates a new rental agreement
   - Parameters: tenant address, monthly rent, security deposit, duration
   - Only callable by landlords

2. **payRent()**
   - Processes rent payments including security deposit
   - Handles late fees and overpayment refunds
   - Only callable by tenants

3. **terminateAgreement()**
   - Terminates active agreements
   - Handles security deposit returns
   - Callable by both landlord and tenant

## Network Configuration

- **Network**: Core Testnet 2
- **RPC URL**: https://rpc.test2.btcs.network
- **Chain ID**: 1115
- **Explorer**: https://scan.test2.btcs.network

## Security Considerations

- All financial functions include reentrancy protection
- Input validation on all user inputs
- Access control modifiers for role-based permissions
- Emergency withdrawal function for contract owner
- Comprehensive error handling and revert messages

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions, issues, or contributions, please:
- Open an issue on GitHub
- Contact the development team
- Join our community discussions

---

**Disclaimer**: This smart contract is provided as-is for educational and development purposes. Always conduct thorough testing and security audits before deploying to mainnet or handling real funds.

0xd5ecc9b006359e6c7a6cb1ed5986251862b57d2b4a5733069d547bd52b6ddc07<img width="1920" height="1080" alt="Screenshot (42)" src="https://github.com/user-attachments/assets/91d80571-4369-4601-b7a9-1c17d75c4631" />

