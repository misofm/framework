# royalty_grant

Locks a rights holder's `RoyaltyPoolStake<Share>` and grants part of its royalties to a recipient. The recipient takes `recipient_share` of each sweep until it has been paid `repayment_value`, until the term ends, or both. After that the owner cap's holder takes the stake back.

No payment is involved. Uses:
- **Recouping an off-chain advance**, such as studio costs paid in fiat. The artist creates a grant with the payer as recipient and `repayment_value` set to the costs.
- **Producer points.** A share of royalties for a term, or until a fee is recouped.
- **A pledge or gift**, such as royalties for a charity for a term.

An advance paid on-chain goes through [`royalty_advance`](../royalty_advance), which pays the owner and creates a grant in one transaction.

The terms cover the common schemes:

| Scheme | `recipient_share` | `repayment_value` | `duration_ms` |
|---|---|---|---|
| Recoup: all royalties in `Currency` until the amount is repaid | 10,000 | some | none |
| Revenue share up to a cap | below 10,000 | some | none |
| Term: a share of royalties for a fixed time | any | none | some |
| Capped term: repaid or the term ends, whichever comes first | any | some | some |

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_grant = { git = "https://github.com/misofm/framework.git", subdir = "royalty_grant", rev = "<commit>" }
```

## Objects

- **RoyaltyGrant\<Share, Currency\>** (`key`) holds the stake and the grant's state, and is shared with `share`.
  - The state is the `owner` and `recipient` payout addresses, `recipient_share` (BPS), the optional `repayment_value` with `repaid_value` (the recipient's progress toward it), the per-currency rounding `remainders`, and the optional `ends_at_ms`.
  - `Currency` is the currency `repayment_value` is counted in. A grant with no `repayment_value` still names one, and it only picks the pool `new` registers in.
- **RoyaltyGrantTerms** is a `copy, drop, store` value holding `recipient_share`, `repayment_value` and `duration_ms`. An offer in `royalty_advance` stores the terms of the grant it will create.
- **The two roles' caps** (`key, store`) carry the `grant_id` and are derived from the grant.
  - **RoyaltyGrantOwnerCap**, at `grant.derive_owner_cap_address()`, changes the owner's payout address and reclaims the stake. `new` returns it to the caller. It can't be destroyed: `reclaim` consumes it.
  - **RoyaltyGrantRecipientCap**, at `grant.derive_recipient_cap_address()`, waives and changes the recipient's payout address. `new` sends it to the `recipient` address itself, so the caller never holds it. It can be destroyed at any time, which gives up those actions for good while payouts to the stored address continue.
  - Holding a cap is what lets its holder act for that role, so a Party, vault or any object that can hold the cap can play either role. Transferring a cap moves the role. The payout address is separate: the new holder changes it with `set_owner` or `set_recipient`.

## API

| Function | Who may call | What it does |
|---|---|---|
| `new_terms` | anyone | Checks and returns a `RoyaltyGrantTerms`. |
| `new<Share, Currency>` | whoever holds the stake | Locks the stake, registers it in the `Currency` pool, sends the recipient cap to `recipient`, and returns the grant with its owner cap. The term starts now. |
| `share` | anyone | Shares the grant. |
| `register<Share, Currency, PoolCurrency>` | anyone | Registers the locked stake in another pool. |
| `sweep<Share, Currency, PoolCurrency>` | anyone | Settles the pool, splits the stake's royalties between the recipient and the owner, and returns the value swept. |
| `buyout` | anyone | Pays exactly the remaining `repayment_value` to the recipient, which makes the grant reclaimable. |
| `reclaim` | `RoyaltyGrantOwnerCap`, once reclaimable | Deletes the grant and the cap and returns the stake. |
| `waive` | `RoyaltyGrantRecipientCap`, before the grant is reclaimable | Ends the term now. |
| `set_owner` | `RoyaltyGrantOwnerCap` | Changes the owner's payout address; a no-op with no event if unchanged. |
| `set_recipient` | `RoyaltyGrantRecipientCap` | Changes the recipient's payout address; a no-op with no event if unchanged. |
| `destroy_recipient_cap` | the cap's holder | Deletes the cap. |
| `stake`, `owner`, `recipient`, `recipient_share`, `repayment_value`, `repaid_value`, `remaining_value`, `ends_at_ms`, `is_reclaimable` | anyone | Views. |
| `derive_owner_cap_address`, `derive_recipient_cap_address`, `royalty_grant_owner_cap_grant_id`, `royalty_grant_recipient_cap_grant_id` | anyone | Where the caps live, and each cap's grant, also callable as `cap.grant_id()`. |
| `royalty_grant_terms_*` | anyone | The terms' values, also callable as `terms.recipient_share()`, `terms.repayment_value()` and `terms.duration_ms()`. |

- **`new_terms` checks the terms:**
  - a zero `recipient_share` aborts `EZeroRecipientShare`;
  - a `repayment_value` of 0 aborts `EZeroRepaymentValue`, and a `duration_ms` of 0 aborts `EZeroDuration`;
  - terms with neither a `repayment_value` nor a `duration_ms` abort `ENoTerms`, because the stake could only come back by `waive`.
- **`new` requires an unregistered stake.** It aborts `EStakeRegistered` when the stake has any pool registration. A registered stake carries the royalties it earned before the grant, and the first sweep would split them with the recipient. The client unregisters the stake from each pool, calls `new`, then `register` for the other pools, in one PTB.
- **`new` saturates the end of the term:** a `duration_ms` that would end past the largest `u64` timestamp ends there instead, which is effectively never.
- **The owner can't end a grant early.** Only the recipient can, with `waive`, or anyone with `buyout` when there's a `repayment_value`. That's what makes a grant binding on the owner.
- **How `sweep` splits the royalties:**
  - The recipient gets `recipient_share` of the swept value, rounded down, while the term runs (`now < ends_at_ms`) and nothing after it ends.
  - The rounding remainder carries to the next sweep, kept per pool currency, so the recipient's total is `recipient_share` of everything swept, rounded down once. How the royalties are split into sweeps doesn't change the total.
  - So one sweep's `recipient_value` can exceed `recipient_share` of its value by one unit. Indexers should take the split from `RoyaltyGrantSweptEvent`, not recompute it.
  - Without a `repayment_value`, `recipient_share` applies to every currency.
  - With a `repayment_value`, only royalties in `Currency` count toward it, and the recipient's part is capped at `repayment_value - repaid_value`.
  - With a `repayment_value`, royalties in any other currency go wholly to the owner, with or without a term: an advance is repaid in the currency it was paid in.
  - The owner gets the rest.
  - `sweep` returns 0 when the stake isn't registered in the pool. When the stake has nothing pending, it settles the pool, returns 0 and emits no event.
- **The currency check runs at runtime.** `sweep` compares the `type_name::with_defining_ids` of `PoolCurrency` and `Currency`. This is deliberate: a separate function for other currencies would let anyone sweep `Currency` through it and skip repayment.
- **`is_reclaimable`** is true once `repaid_value == repayment_value` or once `now >= ends_at_ms`, whichever comes first.
- **`reclaim`** aborts `EUnauthorized` for another grant's owner cap and `ENotReclaimable` until the grant is reclaimable. The stake is returned to the caller, not sent to the `owner` payout address, and keeps its registrations and pending royalties.
- **`buyout`** aborts `ENoRepaymentValue` on a grant with no `repayment_value`, and `EWrongBuyout` for any value other than `remaining_value`.
  - It sets `repaid_value` to `repayment_value` and leaves the stake locked until it is reclaimed.
  - It doesn't check the term. Once the term has ended the grant is reclaimable without it, and `buyout` still pays the recipient `remaining_value`, so check `is_reclaimable` first.
  - Once the amount is repaid, a zero balance buys out.
- **`waive`** sets `ends_at_ms` to now. Later sweeps pay the owner, and the grant is reclaimable. It aborts `EAlreadyReclaimable` once the grant is already reclaimable, so it can't move a past end date or run twice.
- **Caps are checked against the grant.** `set_owner`, `set_recipient` and `waive` abort `EUnauthorized` for another grant's cap.
- **Payouts only go to the two stored addresses.** Royalties and buyouts are sent with `send_funds` to `recipient` or `owner`. `set_owner` and `set_recipient` redirect all later payouts.

## Flow

1. The owner builds the terms with `new_terms`, then calls `new`, `transfer::public_transfer` of the owner cap, and `share` in one PTB. The recipient cap is already at the recipient.
2. Anyone sweeps the grant's pools.
3. Once it is reclaimable, the owner cap's holder calls `reclaim`.

## Events

- `RoyaltyGrantCreatedEvent<Share, Currency> { grant_id, stake_id, pool_id, shares, owner, recipient, recipient_share_bps, repayment_value, ends_at_ms }`
- `RoyaltyGrantSweptEvent<PoolCurrency> { grant_id, pool_id, recipient, recipient_value, owner, owner_value, repaid_value }`, when a sweep pays anything. `recipient` and `owner` are the addresses paid; `repaid_value` is the total counted toward `repayment_value` after the sweep.
- `RoyaltyGrantBoughtOutEvent { grant_id, recipient, value }`
- `RoyaltyGrantReclaimedEvent { grant_id, stake_id }`
- `RoyaltyGrantWaivedEvent { grant_id, ends_at_ms }`
- `RoyaltyGrantOwnerSetEvent { grant_id, owner }`
- `RoyaltyGrantRecipientSetEvent { grant_id, recipient }`

## Known limitations

- **Off-chain payments are trusted.** A grant can't prove an off-chain payment was made, and a payer can't make an artist create a grant after being paid. The safe order is grant first, then pay: the payer checks that the grant is shared, that `recipient` is theirs and that they hold the recipient cap at `derive_recipient_cap_address`. If the payer then never pays, the stake stays locked until the term ends, the amount is repaid or the payer waives. Use `royalty_advance` whenever the payment can be on-chain, and off-chain grants only between parties who trust each other.
- **Sweep before changing the recipient.** `set_recipient` doesn't settle what has accrued, so the new recipient gets royalties earned before the change. A recipient selling its position should `sweep` every pool in the same PTB, before `set_recipient`.
- **Timing at the end of the term.** Royalties that accrue before `ends_at_ms` but are swept after it go to the owner, and so do those pending at `waive`. Royalties still pending at `reclaim` go with the stake. A recipient owed them should sweep first.
- **Object recipients.** A Party, vault or other object named as recipient can only use the recipient cap if its module can receive objects sent to its address.
- **Pool linkage.** A grant reaches only pools of the `royalty_pool` package this one links. The published package must link the same `royalty_pool` the live pools come from.

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `bps` | [unconfirmedlabs/bps](https://github.com/unconfirmedlabs/bps) | `4ca1972` |

## Layout and testing

```
sources/royalty_grant.move       the module
tests/royalty_grant_tests.move   unit tests
```

The unit-test VM does not settle accumulators into pools, so pool `settle` folds nothing in. The tests fund pools with `royalty_pool::deposit` and check payouts with `test_scenario::settled_balance`. Settlement of pool funds needs an end-to-end test on a Sui network.

```sh
sui move build
sui move test --coverage
```

This package has not had a third-party audit. Formal verification evidence is in [misofm/audits](https://github.com/misofm/audits).

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
