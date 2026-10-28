# royalty_lock

Locks a `Stake<Share>` and directs part of its royalties to a recipient. The recipient takes `recipient_share` of each claim until it has been paid `amount`, until the term ends, or both. After that the stake goes back to its owner.

Three ways to use it:
- **Recouping an off-chain advance**, such as studio costs paid in fiat. The artist locks shares with the payer as recipient and `amount` set to the costs.
- **A pledge**, such as royalties for a charity. The artist locks shares for a term with the charity as recipient.
- **An on-chain advance**, through [`royalty_advance`](../royalty_advance), which creates the lock when it pays the artist.

The terms cover the common schemes:

| Scheme | `recipient_share` | `amount` | `duration_ms` |
|---|---|---|---|
| Recoup: all royalties until the amount is repaid | 10,000 | some | none |
| Revenue share up to a cap | below 10,000 | some | none |
| Term: a share of royalties for a fixed time | any | none | some |
| Capped term: repaid or the term ends, whichever comes first | any | some | some |

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_lock = { git = "https://github.com/misofm/framework.git", subdir = "royalty_lock", rev = "<commit>" }
```

## Objects

- **RoyaltyLock\<Share, Currency\>** is a shared object.
  - It holds the stake, the `owner` and `recipient` addresses, `recipient_share` (BPS), the optional `amount` with `claimed` (the recipient's progress toward it), and the optional `ends_at_ms`.
  - `Currency` is the currency `amount` is counted in. A lock with no `amount` still names one, and it has no effect.
- **RoyaltyLockTerms** is a `copy, drop, store` value holding `recipient_share`, `amount` and `duration_ms`. `royalty_advance` stores one in its offer.
- **RoyaltyLockOwnerCap** and **RoyaltyLockRecipientCap** (`key, store`) carry the `lock_id` and are the two roles' authority. `share` derives them from the lock, so their addresses are `derive_owner_cap_address(lock_id)` and `derive_recipient_cap_address(lock_id)`, and sends them to the owner and recipient addresses.
  - Holding a cap is what lets its holder act for that role, so a Party, vault or any object that can hold the cap can play either role.
  - Transferring a cap moves the role. The payout address is separate: the new holder changes it with `set_owner` or `set_recipient`.
  - A cap can be destroyed at any time. Destroying it gives up the role's actions for good, but payouts to the stored address continue.

## API

| Function | Who may call | What it does |
|---|---|---|
| `new_terms` | anyone | Checks and returns a `RoyaltyLockTerms`. |
| `new<Share, Currency>` | whoever holds the stake | Locks the stake and returns the lock. The term starts now. |
| `share` | anyone | Shares the lock and sends its owner cap to the owner and its recipient cap to the recipient. |
| `claim<Share, Currency, PoolCurrency>` | anyone | Settles the pool and splits the stake's royalties between the recipient and the owner. |
| `unlock` | anyone, once unlockable | Sends the stake to the owner and deletes the lock. |
| `buyout` | anyone | Pays exactly the remaining `amount` to the recipient, then unlocks. |
| `waive` | `RoyaltyLockRecipientCap` | Unlocks early. |
| `register<Share, Currency, PoolCurrency>` | anyone | Registers the locked stake in another pool. |
| `set_owner` | `RoyaltyLockOwnerCap` | Changes the owner's payout address; a no-op with no event if unchanged. |
| `set_recipient` | `RoyaltyLockRecipientCap` | Changes the recipient's payout address; a no-op with no event if unchanged. |
| `destroy_owner_cap`, `destroy_recipient_cap` | the cap's holder | Deletes a cap. |
| `stake`, `owner`, `recipient`, `recipient_share`, `amount`, `claimed`, `remaining`, `ends_at_ms`, `is_unlockable` | anyone | Views. |
| `royalty_lock_owner_cap_lock_id`, `royalty_lock_recipient_cap_lock_id`, `derive_owner_cap_address`, `derive_recipient_cap_address` | anyone | The cap's lock, also callable as `cap.lock_id()`, and where each cap lives. |
| `royalty_lock_terms_recipient_share`, `royalty_lock_terms_amount`, `royalty_lock_terms_duration_ms` | anyone | The terms' values, also callable as `terms.recipient_share()` and so on. |

- **`new_terms` checks the terms:**
  - a zero `recipient_share` aborts `EZeroRecipientShare`;
  - an `amount` of 0 aborts `EZeroAmount`, and a `duration_ms` of 0 aborts `EZeroDuration`;
  - terms with neither an `amount` nor a `duration_ms` abort `ENoTerms`, because the stake could only come back by `waive`.
- **`new` saturates the end of the term.** A `duration_ms` that would end past the largest `u64` timestamp ends there instead, which is effectively never.
- **The owner can't unlock early.** Only the recipient can end a lock before its terms are met, with `waive`, or anyone can with `buyout` when there's an `amount`. That's what makes a lock binding on the owner.
- **How `claim` splits the royalties:**
  - The recipient gets `recipient_share` of the claimed value, rounded down, while the term runs (`now < ends_at_ms`) and nothing after it ends.
  - With an `amount`, only royalties in `Currency` count toward it, and the recipient's part is capped at `amount - claimed`. Royalties in any other currency go wholly to the owner.
  - Without an `amount`, `recipient_share` applies to every currency.
  - The owner gets the rest.
  - `claim` does nothing when the stake isn't registered in the pool. When the stake has nothing pending, it settles the pool and emits no lock event.
- **The currency check runs at runtime.** `claim` compares the `type_name::with_defining_ids` of `PoolCurrency` and `Currency`. This is deliberate: a separate function for other currencies would let anyone claim `Currency` through it and skip repayment.
- **`is_unlockable`** is true once `claimed == amount` or once `now >= ends_at_ms`, whichever comes first. `unlock` aborts `ENotUnlockable` until then.
- **`buyout`** aborts `ENoAmount` on a lock with no `amount`, and `EWrongBuyout` for any value other than `remaining`.
  - It doesn't check the term. Once the term has ended, `unlock` is free and `buyout` still pays the recipient `remaining`, so check `is_unlockable` first.
  - Once the amount is repaid, a zero balance buys out. That ends the lock like `unlock` does, but it emits `RoyaltyLockBoughtOutEvent` instead of `RoyaltyLockUnlockedEvent`.
- **Caps are checked against the lock.** `set_owner` aborts `ENotOwner` and `set_recipient` and `waive` abort `ENotRecipient` for another lock's cap.
- **Payouts only go to the two stored addresses.** Royalties and buyouts are sent with `send_funds` to `recipient` or `owner`, and the stake is transferred to `owner`. `set_owner` and `set_recipient` take the role's cap, and they redirect all later payouts.
- **Pool registrations.** A stake can already be registered in pools before it's locked, and it keeps those registrations. `register` adds later pools.

## Events

- `RoyaltyLockCreatedEvent<Share, Currency> { lock_id, stake_id, shares, owner, recipient, recipient_share_bps, amount, ends_at_ms }`
- `RoyaltyLockClaimedEvent<PoolCurrency> { lock_id, pool_id, recipient_value, owner_value, claimed }`, when a claim pays anything. `claimed` is the total after the claim.
- `RoyaltyLockUnlockedEvent { lock_id, stake_id }`
- `RoyaltyLockBoughtOutEvent { lock_id, stake_id, value }`
- `RoyaltyLockWaivedEvent { lock_id, stake_id }`
- `RoyaltyLockOwnerChangedEvent { lock_id, owner }`
- `RoyaltyLockRecipientChangedEvent { lock_id, recipient }`

## Known limitations

- **Royalties earned before the lock.** A stake that is already registered keeps its pending royalties, and the lock splits them at its first claim. The owner should first claim every pool the stake is registered in, in the same PTB.
- **Claim before changing the recipient.** `set_recipient` doesn't settle what has accrued, so the new recipient gets royalties earned before the change. A recipient selling its position should `claim` every pool in the same PTB, before `set_recipient`.
- **Timing at the end of the term.** Royalties that accrue before `ends_at_ms` but are claimed after it go to the owner. Royalties still pending at `unlock` go to the owner with the stake. A recipient owed them should claim first.
- **Off-chain payments are trusted.** A lock can't prove an off-chain payment was made, and a payer can't make an artist lock after being paid. The safe order is to create the lock first: it is public and the owner can't undo it, so the payer can check it before paying.
- **Pool linkage.** Claims reach only pools of the `royalty_pool` package this one links. The published package must link the same `royalty_pool` the live pools come from.

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `bps` | [unconfirmedlabs/bps](https://github.com/unconfirmedlabs/bps) | `4ca1972` |

## Layout and testing

```
sources/royalty_lock.move       the module
tests/royalty_lock_tests.move   unit tests
```

The unit-test VM does not settle accumulators into pools, so pool `settle` folds nothing in. The tests fund pools with `pool::deposit` and check payouts with `test_scenario::settled_balance`. Settlement of pool funds needs an end-to-end test on a Sui network.

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
