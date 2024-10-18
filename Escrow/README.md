# Advanced Escrow Smart Contract

An advanced, secure and flexible escrow smart contract implementation in Clarity for the Stacks blockchain. This contract facilitates secure transactions between buyers and sellers with optional arbiter involvement.

## Features

- **Secure Fund Management**: Automated handling of deposits and releases
- **Multiple Parties**: Support for buyers, sellers, and arbiters
- **Dispute Resolution**: Built-in dispute management system
- **Flexible Timeouts**: Configurable transaction timeouts
- **Rating System**: Transaction rating functionality
- **Fee Management**: Configurable fee structure
- **User Transaction History**: Tracking of user-associated escrows

## Contract Constants

- `contract-owner`: The address that deployed the contract
- `fee-percentage`: Default 1% fee (10/1000)
- `timeout-blocks`: Default 1440 blocks (approximately 10 days)
- Maximum of 100 escrows per user

## Error Codes

- `u100`: Owner-only operation
- `u101`: Unauthorized access
- `u102`: Already initialized
- `u103`: Not initialized
- `u104`: Already funded
- `u105`: Not funded
- `u106`: Already completed
- `u107`: Invalid amount
- `u108`: Fee too high
- `u109`: Not disputed
- `u110`: Timeout not reached
- `u111`: Invalid status for rating
- `u112`: Invalid rating
- `u113`: User escrow list full

## Read-Only Functions

- `get-escrow`: Retrieve escrow details
- `get-escrow-status`: Get current status of an escrow
- `get-user-escrows`: List all escrows associated with a user
- `get-timeout`: Get current timeout setting

## Transaction Flow

1. Buyer creates escrow with specified seller and arbiter
2. Funds are locked in contract
3. Transaction can proceed in following ways:
   - Normal completion (release to seller)
   - Refund to buyer
   - Dispute resolution
   - Timeout-based cancellation

## Security Features

- Role-based access control
- Timelock mechanisms
- Secure fund handling
- Error handling for edge cases
- Transaction status tracking


## Best Practices

1. Always verify escrow details before sending funds
2. Set reasonable timeout periods
3. Choose trusted arbiters
4. Maintain clear communication between parties
5. Use dispute resolution as last resort

## Notes

- All amounts are in microSTX
- Ratings must be between 0 and 5
- Contract owner can only modify fees and timeout settings
- Users can track their escrows through the `get-user-escrows` function

## Error Handling

The contract includes comprehensive error handling for various scenarios:
- Invalid amounts
- Unauthorized access attempts
- Invalid state transitions
- Timeout violations
- Rating constraints

## Author

Chukwudi Nwaneri Daniel