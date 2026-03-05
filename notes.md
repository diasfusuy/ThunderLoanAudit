## Protocol
~350 nsloc/complexity 

### My Notes

## Flash Loan
- All action happens only in one transaction.
- User borrows form a contract (liquidity provider), uses it for whatever reason he borrowed for, and returns the same amount in the same transaction.
- User cannot borrow and ruun away because if cannot pay back the same amount in the same transaction the flash loan reverts.
- Liquidity provider doesnt lose anything while user lose the gas fee for the reverted transaction.

