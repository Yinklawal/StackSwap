# StackSwap - Decentralized Exchange Smart Contract

A decentralized exchange (DEX) smart contract built for the Stacks blockchain using Clarity. StackSwap implements an Automated Market Maker (AMM) model enabling users to trade tokens, provide liquidity, and earn fees.

## Features

- **Token Swapping**: Trade between primary and secondary tokens using constant product formula
- **Liquidity Provision**: Add liquidity to earn trading fees
- **Liquidity Withdrawal**: Remove liquidity and receive proportional tokens
- **Fee Management**: Configurable trading fees with admin controls
- **Input Validation**: Comprehensive validation to prevent malicious inputs

## Contract Architecture

### Token Types
- `primary-coin`: First token in the trading pair
- `secondary-coin`: Second token in the trading pair
- `liquidity-shares`: LP tokens representing share of pool ownership

### Key Constants
- `max-deposit-amount`: Maximum allowed deposit (1,000,000,000,000 units)
- `trading-fee-basis-points`: Default 0.3% trading fee (30 basis points)

### Error Codes
- `u100`: Access denied
- `u101`: Insufficient balance
- `u102`: Pool empty
- `u103`: Zero value input
- `u104`: Price impact too high
- `u105`: Invalid amount

## Public Functions

### Trading Functions

#### `trade-primary-for-secondary`
Swap primary tokens for secondary tokens.
```clarity
(trade-primary-for-secondary (input-amount uint) (minimum-output uint))
```
- `input-amount`: Amount of primary tokens to swap
- `minimum-output`: Minimum secondary tokens expected (slippage protection)

#### `trade-secondary-for-primary`
Swap secondary tokens for primary tokens.
```clarity
(trade-secondary-for-primary (input-amount uint) (minimum-output uint))
```
- `input-amount`: Amount of secondary tokens to swap
- `minimum-output`: Minimum primary tokens expected (slippage protection)

### Liquidity Functions

#### `provide-liquidity`
Add liquidity to the pool and receive LP tokens.
```clarity
(provide-liquidity (primary-deposit uint) (secondary-deposit uint) (minimum-shares uint))
```
- `primary-deposit`: Amount of primary tokens to deposit
- `secondary-deposit`: Amount of secondary tokens to deposit
- `minimum-shares`: Minimum LP tokens expected

**Note**: For existing pools, deposits must maintain the current pool ratio.

#### `withdraw-liquidity`
Remove liquidity from the pool by burning LP tokens.
```clarity
(withdraw-liquidity (shares-to-burn uint) (min-primary uint) (min-secondary uint))
```
- `shares-to-burn`: Amount of LP tokens to burn
- `min-primary`: Minimum primary tokens to receive
- `min-secondary`: Minimum secondary tokens to receive

### Administrative Functions

#### `claim-accumulated-fees`
Allows contract deployer to claim accumulated trading fees.
```clarity
(claim-accumulated-fees)
```

#### `update-trading-fee`
Update the trading fee percentage (max 10%).
```clarity
(update-trading-fee (new-fee-basis-points uint))
```
- `new-fee-basis-points`: New fee in basis points (100 = 1%)

## Read-Only Functions

### Balance Queries
- `get-user-primary-balance`: Get caller's primary token balance
- `get-user-secondary-balance`: Get caller's secondary token balance
- `get-user-share-balance`: Get caller's LP token balance

### Pool Information
- `get-pool-reserves`: Get current pool reserves for both tokens
- `get-estimated-shares`: Estimate LP tokens for given deposit amounts

## Liquidity Calculations

### Initial Liquidity
For the first liquidity provision:
```
shares = (primary_amount + secondary_amount) / 2
```

### Proportional Liquidity
For subsequent liquidity additions:
```
shares = min(
  (primary_amount * total_shares) / primary_reserve,
  (secondary_amount * total_shares) / secondary_reserve
)
```

## Trading Formula

Uses the constant product formula with fees:
```
output = (input_after_fee * output_reserve) / (input_reserve + input_after_fee)
```

Where:
- `input_after_fee = input * (10000 - fee_basis_points) / 10000`
- `fee_basis_points` defaults to 30 (0.3%)

## Security Features

### Input Validation
- All user inputs are validated for reasonable bounds
- Maximum deposit limits prevent overflow attacks
- Zero-value inputs are rejected
- Slippage protection through minimum output parameters

### Access Control
- Only contract deployer can claim fees
- Only contract deployer can update trading fees
- Fee updates are capped at 10% maximum

### Proportional Deposits
- Existing pools require proportional token deposits
- Prevents liquidity providers from manipulating pool ratios

## Usage Examples

### Adding Initial Liquidity
```clarity
;; Add 1000 primary tokens and 2000 secondary tokens
(contract-call? .stackswap provide-liquidity u1000 u2000 u1400)
```

### Trading Tokens
```clarity
;; Swap 100 primary tokens for secondary tokens (min 190 expected)
(contract-call? .stackswap trade-primary-for-secondary u100 u190)
```

### Removing Liquidity
```clarity
;; Burn 500 LP tokens (expect at least 250 primary and 500 secondary back)
(contract-call? .stackswap withdraw-liquidity u500 u250 u500)
```

## Deployment

1. Deploy the contract to Stacks blockchain
2. The deployer becomes the admin with fee claiming rights
3. Users can immediately start trading and providing liquidity

## Testing

Before mainnet deployment, thoroughly test:
- Token swapping in both directions
- Liquidity provision and withdrawal
- Fee calculations
- Access control restrictions
- Edge cases (empty pools, large amounts, etc.)
