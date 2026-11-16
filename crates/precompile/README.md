# nbnet-precompile

Two precompiles used by `EvmExecutor`. They do not call `hotmint-staking`.

| Address | Name | Selectors |
|---------|------|-----------|
| `0x0800` | Balances | `balanceOf(address)` `0x70a08231`, `transfer(address,uint256)` `0xa9059cbb` |
| `0x0801` | Staking lock | `delegate(address,uint256)` `0x026e402b`, `unbond(address,uint256)` `0xa5d059ca`, `getStake(address,address)` `0x82dda22d`, `totalStake(address)` `0xb273fc9a` |

`balanceOf` and `transfer` use the revm journal, so those balances are part of the state trie.

`delegate` moves tokens to `0x0801` through the journal, then records `(delegator, validator) → amount` in a process-local `HashMap` (`StakingState` behind `SharedStakingState`). That map is not hashed into `app_hash` and is empty after a restart. There is no validator registration or reward selector.

## License

GPL-3.0-only
