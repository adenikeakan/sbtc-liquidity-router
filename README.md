# Cross-Chain sBTC Liquidity Router

## Overview
A decentralized liquidity routing protocol for sBTC across multiple blockchain networks, featuring MEV protection, fee optimization, and cross-chain messaging capabilities.

## Features
- Unified sBTC liquidity routing
- MEV protection mechanisms
- Cross-chain compatibility
- Fee optimization algorithms
- Emergency controls

## Technology Stack
- **Smart Contracts**: Clarity 3 (Epoch 3.0)
- **Testing**: Clarinet v3.4.0 + Vitest
- **Frontend**: React + TypeScript + Stacks.js v7
- **Cross-Chain**: LayerZero, Axelar, Wormhole
- **Backend**: Node.js + TypeScript

## Development Setup

### Prerequisites
- Clarinet v3.4.0+
- Node.js 18+
- Git

### Installation
```bash
# Clone repository
git clone [your-repo-url]
cd sbtc-liquidity-router

# Install dependencies
npm install

# Run tests
clarinet test

# Check contracts
clarinet check
```

## Contract Architecture
1. `liquidity-router.clar` - Main routing logic
2. `cross-chain.clar` - Cross-chain messaging
3. `mev-guard.clar` - MEV protection
4. `fee-optimizer.clar` - Fee optimization

## Code4STX Compliance
- ✅ Open source on GitHub
- ✅ Valid Clarity 3 code (passes clarinet check)
- ✅ Uses @stacks/* libraries
- ✅ Meaningful monthly commits
- ✅ Comprehensive testing

## License
MIT

## Smart Contract Integration

### Contract Addresses (Testnet)
- Liquidity Router: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.liquidity-router`
- Cross-Chain: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.cross-chain`
- MEV Guard: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.mev-guard`
- Fee Optimizer: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.fee-optimizer`

### Frontend Integration
```typescript
import { StacksNetwork } from '@stacks/network';
import { callReadOnlyFunction } from '@stacks/transactions';

// Example: Get optimal route for sBTC swap
const getOptimalRoute = async (amount: number, fromChain: string, toChain: string) => {
  const network = new StacksNetwork('testnet');
  
  const result = await callReadOnlyFunction({
    network,
    contractAddress: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM',
    contractName: 'liquidity-router',
    functionName: 'get-optimal-route',
    functionArgs: [
      uintCV(amount),
      stringAsciiCV(fromChain),
      stringAsciiCV(toChain)
    ],
    senderAddress: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM',
  });
  
  return result;
};
```

## Testing
```bash
# Run all contract tests
clarinet test

# Run frontend tests
npm test

# Check contract validity
clarinet check

# Start development server
npm run dev
```

## Contributing
1. Fork the repository
2. Create feature branch from `feature/sbtc-router-development`
3. Make meaningful commits
4. Submit pull request

## Code4STX Submissions
Each month, submit meaningful updates:
- Month 1: Core routing logic
- Month 2: Cross-chain integration
- Month 3: MEV protection
- Month 4: Fee optimization
- Month 5: Frontend integration