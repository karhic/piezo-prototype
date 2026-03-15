
# Piezo Prototype
 
Prototype smart contract system for a **trust-minimized trading challenge**.
 
The goal is to remove discretionary payout decisions from prop-style trading challenges by enforcing the rules directly in a smart contract.
 
---
 
## Status
 
- Smart contract implemented
- Full Foundry test suite passing
- Local simulation running on Anvil
- Contract depolyed on testnet : https://sepolia.arbiscan.io/address/0x66f4bAeda936548126A1BA330b03Aa9e9F2B287a
 
This repository is an early **mechanism prototype**, not the final production system.
 
---
 
## The Idea
 
Prop trading challenge platforms operate with discretionary payout decisions. Traders may complete the challenge rules but still depend on the platform to approve withdrawals. In practice this happens frequently and is a major pain point.
 
This prototype explores a model where:
 
1. A trader pays a fee in USDC.
2. The contract records the trader's starting balance.
3. The trader must reach a deterministic target before expiration.
4. If the target is reached, the reward payout executes automatically.
 
The contract therefore acts as the rule enforcement layer.
 
---
 
## Mechanism
 
High-level flow:
 
1. Trader pays entry fee.
2. Contract records **starting balance after fee**.
3. Trader must reach **target balance** before expiration.
4. If conditions are met, reward is paid automatically from the reward pool.
 
Example:
Entry fee:        10 USDC Balance after fee: 10 USDC Target:           20 USDC Reward:           50 USDC

 
If the trader's balance reaches the target before expiration, the reward is paid automatically by the contract.
 
---
 
## Contracts
src/MultiSlotChallenge.sol

 
Core contract implementing the trading challenge logic.

src/MockUSDC.sol

 
Mock token used for local testing.
 
---
 
## Tests
test/MultiSlotChallenge.t.sol

 
End-to-end test suite covering:
 
- challenge creation
- fee handling
- escrow reserve requirements
- successful payout
- expiry conditions
- edge cases
 
---
 
## Run Tests
 
Requires **Foundry**.
 
Install Foundry:
curl -L https://foundry.paradigm.xyz | bash foundryup

 
Run the test suite:
forge test -vv

 
All tests should pass.
 
---
 
## Local Simulation
 
Local testing uses **Anvil**.
 
Start Anvil:
anvil

 
The test suite deploys contracts and simulates challenge scenarios automatically.
 
---

## Deployment

With Anvil running:

forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast

This deploys:
-MockUSDC
-MultiSlotChallenge

The script prints the deployed addresses.

Export them for later interaction:

export MOCK_USDC=0x....
export CHALLENGE=0x.....

 
## Next Steps
 
Planned development:
 
- tests on testnet
- small live user test
- frontend or interaction guide
- reward pool management improvements
- oracle integration for external trading platforms
 
---
 
## Limitations (Prototype)
 
This repository focuses only on the **core mechanism**.
 
It does not yet include:
 
- production security review
- UI / frontend
- oracle integration
- production token support
- full trading platform integration
 
---
 
 
## License
 
MIT
