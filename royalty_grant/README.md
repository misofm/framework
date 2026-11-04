# royalty_grant

Locks a rights holder's `RoyaltyPoolStake<Share>` and grants part of its royalties to a recipient. The recipient takes `recipient_share` of each sweep until it has been paid `repayment_value`, until the term ends, or both. After that the owner cap's holder takes the stake back. A grant starts pending and binds the owner only once the recipient activates it.

No payment is involved. Uses:
- **Recouping an off-chain advance**, such as studio costs paid in fiat. The artist creates a grant with the payer as recipient and `repayment_value` set to the costs.
- **Producer points.** A share of royalties for a term, or until a fee is recouped.
- **A pledge or gift**, such as royalties for a charity for a term.

An advance paid on-chain goes through [`royalty_advance`](../royalty_advance), which pays the owner and creates an active grant in one transaction.

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
  - The state is the `owner` and `recipient` payout addresses, `recipient_share` (BPS), the optional `repayment_value` with `repaid_value` (the recipient's progress toward it), the rounding `remainder`, the optional `duration_ms`, `activated_at_ms` (none while pending) and the optional `ends_at_ms` (set at activation, or by `waive`).
  - `Currency` is the one currency the grant covers: the stake is registered only in the work's `Currency` pool, and `repayment_value` is counted in it. Royalties the work earns in other currencies don't reach the grant's stake.
- **RoyaltyGrantTerms** is a `copy, drop, store` value holding `recipient_share`, `repayment_value` and `duration_ms`. An offer in `royalty_advance` stores the terms of the grant it will create.
- **The two roles' caps** (`key, store`) carry the `grant_id` and are derived from the grant.
  - **RoyaltyGrantOwnerCap**, at `grant.derive_owner_cap_address()`, cancels a pending grant, changes the owner's payout address and reclaims the stake. `new` returns it to the caller. It can't be destroyed: `cancel` or `reclaim` consumes it, together with the grant.
  - **RoyaltyGrantRecipientCap**, at `grant.derive_recipient_cap_address()`, waives and changes the recipient's payout address. It doesn't exist until the grant is activated: `activate` returns it to the recipient. It can be destroyed at any time, which gives up those actions for good while payouts to the stored address continue. After `reclaim` it refers to a deleted grant, and its holder destroys it to get the storage rebate.
  - Holding a cap is what lets its holder act for that role, so a Party, vault or any object that can hold the cap can play either role. Transferring a cap moves the role. The payout address is separate: the new holder changes it with `set_owner` or `set_recipient`.

## Lifecycle

| State | Reached by | `sweep` pays the recipient | Owner cap | Recipient |
|---|---|---|---|---|
| Pending | `new` | nothing | `cancel`, `set_owner` | `activate`, by signing as `recipient` |
| Active | `activate`, or `new_active` | `recipient_share`, until repaid or the term ends | `set_owner` | `waive`, `set_recipient` |
| Reclaimable | repaid, the term ended, waived or bought out | nothing | `reclaim`, `set_owner` | `set_recipient` |

A grant binds the owner only once it is active. Until then the owner can cancel it, so a wrong `recipient` address or a recipient who never activates costs nothing: the owner keeps every royalty while it is pending and takes the stake back with `cancel`.

## API

| Function | Who may call | What it does |
|---|---|---|
| `new_terms` | anyone | Checks and returns a `RoyaltyGrantTerms`. |
| `new<Share, Currency>` | whoever holds the stake | Locks the stake, registers it in the `Currency` pool, and returns the pending grant with its owner cap. |
| `new_active<Share, Currency>` | whoever holds the stake | `new`, then activates the grant now, and returns the grant with both caps. For callers whose `recipient` address the recipient supplied, such as `royalty_advance`. |
| `share` | anyone | Shares the grant. |
| `activate` | the `recipient` address, while pending | Settles the pool, starts the term and returns the recipient cap. |
| `sweep<Share, Currency>` | anyone | Settles the `Currency` pool, splits the stake's royalties between the recipient and the owner, and returns the value swept. |
| `buyout` | anyone, while active and not reclaimable | Pays exactly the remaining `repayment_value` to the recipient, which makes the grant reclaimable. |
| `cancel` | `RoyaltyGrantOwnerCap`, while pending | Deletes the grant and the cap and returns the stake. |
| `reclaim` | `RoyaltyGrantOwnerCap`, once reclaimable | Deletes the grant and the cap and returns the stake. |
| `waive` | `RoyaltyGrantRecipientCap`, before the grant is reclaimable | Ends the term now. |
| `set_owner` | `RoyaltyGrantOwnerCap` | Changes the owner's payout address; a no-op with no event if unchanged. |
| `set_recipient` | `RoyaltyGrantRecipientCap` | Changes the recipient's payout address; a no-op with no event if unchanged. |
| `destroy_recipient_cap` | the cap's holder | Deletes the cap. |
| `stake`, `owner`, `recipient`, `recipient_share`, `repayment_value`, `repaid_value`, `remaining_value`, `duration_ms`, `is_active`, `activated_at_ms`, `ends_at_ms`, `is_reclaimable` | anyone | Views. |
| `derive_owner_cap_address`, `derive_recipient_cap_address`, `royalty_grant_owner_cap_grant_id`, `royalty_grant_recipient_cap_grant_id` | anyone | Where the caps live, and each cap's grant, also callable as `cap.grant_id()`. |
| `royalty_grant_terms_*` | anyone | The terms' values, also callable as `terms.recipient_share()`, `terms.repayment_value()` and `terms.duration_ms()`. |

- **`new_terms` checks the terms:**
  - a zero `recipient_share` aborts `EZeroRecipientShare`;
  - a `repayment_value` of 0 aborts `EZeroRepaymentValue`, and a `duration_ms` of 0 aborts `EZeroDuration`;
  - terms with neither a `repayment_value` nor a `duration_ms` abort `ENoTerms`, because the stake could only come back by `waive`.
- **`new` requires an unregistered stake.** It aborts `EStakeRegistered` when the stake has any pool registration. A registered stake carries the royalties it earned before the grant, and a sweep after activation would split them with the recipient. The client unregisters the stake from each pool before calling `new`, in the same PTB.
- **`activate`** aborts `ENotPending` once the grant is active, and `ENotRecipient` unless the transaction's sender is `recipient`, which proves the recipient controls that address. It settles the pool and aborts `EPendingRoyalties` while the stake has unswept royalties, so royalties earned while pending can't be split with the recipient: the client calls `sweep` then `activate` in one PTB. The term starts at activation, and an end past the largest `u64` timestamp saturates there, which is effectively never. A recipient that is an object activates through a signer, then moves the cap to the object and calls `set_recipient` in the same PTB.
- **`cancel`** aborts `EUnauthorized` for another grant's owner cap and `ENotPending` once the grant is active.
- **The owner can't end an active grant early.** Only the recipient can, with `waive`, or anyone with `buyout` when there's a `repayment_value`. That's what makes a grant binding on the owner.
- **How `sweep` splits the royalties:**
  - While the grant is pending, the owner gets everything.
  - Once it is active, the recipient gets `recipient_share` of the swept value, rounded down, while the term runs (`now < ends_at_ms`) and nothing after it ends.
  - The rounding remainder carries to the next sweep, so the recipient's total is `recipient_share` of everything swept while active, rounded down once. How the royalties are split into sweeps doesn't change the total.
  - So one sweep's `recipient_value` can exceed `recipient_share` of its value by one unit. Indexers should take the split from `RoyaltyGrantSweptEvent`, not recompute it.
  - With a `repayment_value`, the recipient's part is capped at `repayment_value - repaid_value`.
  - The owner gets the rest.
  - When the stake has nothing pending, it settles the pool, returns 0 and emits no event.
- **`is_reclaimable`** is false while pending, and true once `repaid_value == repayment_value` or once `now >= ends_at_ms`, whichever comes first.
- **`reclaim`** aborts `EUnauthorized` for another grant's owner cap and `ENotReclaimable` until the grant is reclaimable; a pending grant is ended with `cancel`. The stake is returned to the caller, not sent to the `owner` payout address, and keeps its registrations and pending royalties.
- **`buyout`** aborts `ENotActive` while pending, `EAlreadyReclaimable` once the grant is reclaimable, `ENoRepaymentValue` on a grant with no `repayment_value`, and `EWrongBuyout` for any value other than `remaining_value`. It sets `repaid_value` to `repayment_value` and leaves the stake locked until it is reclaimed.
- **`waive`** sets `ends_at_ms` to now. Later sweeps pay the owner, and the grant is reclaimable. It aborts `EAlreadyReclaimable` once the grant is already reclaimable, so it can't move a past end date or run twice.
- **Caps are checked against the grant.** `set_owner`, `set_recipient` and `waive` abort `EUnauthorized` for another grant's cap.
- **Payouts only go to the two stored addresses.** Royalties and buyouts are sent with `send_funds` to `recipient` or `owner`. `set_owner` and `set_recipient` redirect all later payouts.

## Flow

1. The owner builds the terms with `new_terms`, then calls `new`, `transfer::public_transfer` of the owner cap, and `share` in one PTB.
2. The recipient checks the grant and calls `sweep` then `activate` from the `recipient` address in one PTB, keeping the returned recipient cap. Until then the owner can `cancel`.
3. Anyone sweeps the grant's `Currency` pool.
4. Once it is reclaimable, the owner cap's holder calls `reclaim`, and the recipient destroys the recipient cap.

## Events

- `RoyaltyGrantCreatedEvent<Share, Currency> { grant_id, stake_id, pool_id, shares, owner, recipient, recipient_share_bps, repayment_value, duration_ms }`
- `RoyaltyGrantActivatedEvent { grant_id, recipient, activated_at_ms, ends_at_ms }`
- `RoyaltyGrantSweptEvent<Currency> { grant_id, pool_id, recipient, recipient_value, owner, owner_value, repaid_value }`, when a sweep pays anything. `recipient` and `owner` are the addresses paid; `repaid_value` is the total counted toward `repayment_value` after the sweep.
- `RoyaltyGrantBoughtOutEvent { grant_id, recipient, value }`
- `RoyaltyGrantCancelledEvent { grant_id, stake_id }`
- `RoyaltyGrantReclaimedEvent { grant_id, stake_id }`
- `RoyaltyGrantWaivedEvent { grant_id, ends_at_ms }`
- `RoyaltyGrantOwnerSetEvent { grant_id, owner }`
- `RoyaltyGrantRecipientSetEvent { grant_id, recipient }`

## Known limitations

- **Off-chain payments are trusted.** A grant can't prove an off-chain payment was made. The safe order is that the owner creates the grant, the payer activates it, and only then pays: once active, the grant binds the owner. If the payer then never pays, the stake stays locked until the term ends, the amount is repaid or the payer waives. Use `royalty_advance` whenever the payment can be on-chain, and off-chain grants only between parties who trust each other.
- **Sweep before changing the recipient.** `set_recipient` doesn't settle what has accrued, so the new recipient gets royalties earned before the change. A recipient selling its position should `sweep` in the same PTB, before `set_recipient`.
- **Timing at the end of the term.** Royalties that accrue before `ends_at_ms` but are swept after it go to the owner, and so do those pending at `waive`. Royalties still pending at `reclaim` go with the stake. A recipient owed them should sweep first.
- **Lost owner cap.** Without the owner cap a grant can't be cancelled or reclaimed, so the stake stays locked and later sweeps pay the `owner` address. Keep the cap in a wallet, Party or vault you control.
- **One currency.** A grant shares only royalties in `Currency`. If the work also earns in another currency, the stake doesn't earn there during the grant and those royalties go to the work's other registered stakes.
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
