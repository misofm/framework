# royalty_advance

Royalty advances paid on-chain. A provider offers a payment in exchange for a [`royalty_lock`](../royalty_lock) on a rights holder's stake. When the rights holder accepts, the payment goes to them and the stake is locked, with the provider as recipient, on the terms that were offered.

For an advance paid off-chain, such as studio costs paid in fiat, use `royalty_lock` directly.

There is no docs.miso.fm page yet, so the facts are below.

```toml
royalty_advance = { git = "https://github.com/misofm/framework.git", subdir = "royalty_advance", rev = "<commit>" }
```

## Objects

- **RoyaltyAdvance\<Share, Currency\>** is a shared offer.
  - It holds the payment in `Currency`, the `provider` and `owner` addresses, the number of `shares` asked for, the `RoyaltyLockTerms`, and `offer_expires_at_ms`.
  - It is deleted when it is accepted or cancelled.
- **RoyaltyAdvanceProviderCap** (`key, store`) carries the `advance_id` and is what lets the provider cancel. `new` derives it from the offer, at `derive_provider_cap_address(advance_id)`, and returns it with the offer. The caller sends it to the provider with `transfer::public_transfer`.
  - After `accept` or a cancel it points at a deleted offer, so its holder should destroy it. The lock's own caps take over.
- **Roles.** `owner` is the rights holder whose stake will be locked; it is the lock's `owner`. The `provider` pays the advance and becomes the lock's `recipient`.

## API

| Function | Who may call | What it does |
|---|---|---|
| `new<Share, Currency>` | anyone | Creates an offer holding the payment and returns it with its provider cap. |
| `share` | anyone | Shares the offer. |
| `accept` | anyone, before the offer expires | Takes a stake of exactly the offered shares, pays the owner, deletes the offer, sends the lock's recipient cap to the provider, and returns a `RoyaltyLock` with the same owner and the provider as recipient, plus its `RoyaltyLockOwnerCap`. |
| `cancel_expired` | anyone, once the offer expires | Refunds the provider and deletes the offer. |
| `destroy_provider_cap` | the cap's holder | Deletes the cap. |
| `cancel` | `RoyaltyAdvanceProviderCap` | Refunds the provider and deletes the offer, at any time. |
| `provider`, `owner`, `payment_value`, `shares`, `terms`, `offer_expires_at_ms` | anyone | Views. |
| `royalty_advance_provider_cap_advance_id`, `derive_provider_cap_address` | anyone | The cap's offer, also callable as `cap.advance_id()`, and where the cap lives. |

- **`new`** aborts `EZeroPayment` on an empty payment, `EZeroShares` on zero shares, and `EOfferExpired` on an expiry at or before now. `royalty_lock::new_terms` has already checked the terms.
- **`accept`** aborts `EOfferExpired` from `offer_expires_at_ms` onward and `EWrongShares` when the stake's value differs. The lock's term starts at acceptance. The recipient cap is transferred to the provider inside `accept`. Returning it to the caller would let an accepting owner `waive` its own lock. The caller keeps the returned owner cap, normally sends it to the owner, and shares the lock with `royalty_lock::share`, in the same PTB.
- **`cancel`** aborts `EUnauthorized` (4) for another offer's cap, and **`cancel_expired`** aborts `EOfferNotExpired` (5) before `offer_expires_at_ms`.
- **Payouts only go to the two stored addresses.** The payment goes to `owner` at `accept` or back to `provider` at either cancel. The lock is built from the stored terms and addresses, so it always matches what was offered.

## Flow

1. The provider builds the terms with `royalty_lock::new_terms`, then calls `new`, `transfer::public_transfer` of the returned provider cap to the provider, and `share` in one PTB.
2. Before the offer expires, anyone calls `accept` with a stake of exactly that many shares, sends the returned owner cap to the owner with `transfer::public_transfer`, then calls `royalty_lock::share` on the returned lock. The payment goes to the owner and the recipient cap goes to the provider.
3. From then on, the advance is an ordinary `royalty_lock`: sweeps, unlock, buyout and waive all go through it.

## Events

- `RoyaltyAdvanceCreatedEvent<Share, Currency> { advance_id, provider, owner, value, shares, recipient_share_bps, repayment_value, duration_ms, offer_expires_at_ms }`
- `RoyaltyAdvanceAcceptedEvent { advance_id, lock_id }`, alongside the lock's `RoyaltyLockCreatedEvent`.
- `RoyaltyAdvanceCancelledEvent { advance_id }`

## Known limitations

- **Royalties earned before `accept`.** A stake that is already registered keeps its pending royalties, and the lock splits them at its first sweep. The party accepting should first sweep every pool the stake is registered in, in the same PTB.
- The lock's own limitations are in the [`royalty_lock` README](../royalty_lock/README.md#known-limitations).

## Dependencies

| Package | Source | Commit |
|---|---|---|
| `royalty_pool` | [`../royalty_pool`](../royalty_pool) | local |
| `royalty_lock` | [`../royalty_lock`](../royalty_lock) | local |
| `bps` | [unconfirmedlabs/bps](https://github.com/unconfirmedlabs/bps) | `4ca1972` |

## Layout and testing

```
sources/royalty_advance.move       the module
tests/royalty_advance_tests.move   unit tests
```

The unit-test VM does not settle accumulators, so the tests check payouts with `test_scenario::settled_balance`.

```sh
sui move build
sui move test --coverage
```

This package has not been audited.

## License

[Functional Source License 1.1, ALv2 Future License](./LICENSE.md)
(FSL-1.1-ALv2). Any use except a Competing Use is permitted, and each version
becomes Apache-2.0 two years after its release.
